import Foundation
import SMC

public enum DaemonClientError: Error, CustomStringConvertible {
    case notRunning
    case connectionFailed(String)
    case badResponse(String)
    case daemonError(String)

    public var description: String {
        switch self {
        case .notRunning:
            return "fanctld is not running (install it with: make install)"
        case .connectionFailed(let msg): return "Could not talk to fanctld: \(msg)"
        case .badResponse(let msg): return "Bad response from fanctld: \(msg)"
        case .daemonError(let msg): return msg
        }
    }
}

/// Blocking one-shot client for the fanctld Unix socket.
public enum DaemonClient {

    public static func isDaemonReachable() -> Bool {
        (try? send(DaemonRequest(cmd: "status"))) != nil
    }

    public static func status() throws -> DaemonStatus {
        let response = try send(DaemonRequest(cmd: "status"))
        guard response.ok, let status = response.status else {
            throw DaemonClientError.daemonError(response.error ?? "no status returned")
        }
        return status
    }

    public static func sensors() throws -> [SensorStatus] {
        let response = try send(DaemonRequest(cmd: "sensors"))
        guard response.ok, let sensors = response.sensors else {
            throw DaemonClientError.daemonError(response.error ?? "no sensors returned")
        }
        return sensors
    }

    @discardableResult
    public static func apply(_ config: DaemonConfig) throws -> DaemonStatus {
        let response = try send(DaemonRequest(cmd: "set", config: config))
        guard response.ok else {
            throw DaemonClientError.daemonError(response.error ?? "set failed")
        }
        guard let status = response.status else {
            throw DaemonClientError.badResponse("set returned no status")
        }
        return status
    }

    public static func send(_ request: DaemonRequest) throws -> DaemonResponse {
        do {
            return try send(request, path: FanControlConstants.socketPath)
        } catch DaemonClientError.notRunning {
            return try send(request, path: FanControlConstants.fallbackSocketPath)
        }
    }

    static func send(_ request: DaemonRequest, path: String) throws -> DaemonResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw DaemonClientError.connectionFailed("socket() failed: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            path.utf8CString.withUnsafeBytes { src in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(raw.count - 1)))
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED {
                throw DaemonClientError.notRunning
            }
            throw DaemonClientError.connectionFailed(String(cString: strerror(errno)))
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        let sent = payload.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, raw.count)
        }
        guard sent == payload.count else {
            throw DaemonClientError.connectionFailed("short write")
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < 1_048_576 {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if chunk[0..<n].contains(0x0A) { break }
        }
        guard let newline = buffer.firstIndex(of: 0x0A) else {
            throw DaemonClientError.badResponse("no reply")
        }

        do {
            return try JSONDecoder().decode(DaemonResponse.self, from: buffer[..<newline])
        } catch {
            throw DaemonClientError.badResponse("\(error)")
        }
    }
}

// MARK: - Direct (daemon-less) read-only status

// Enumerating sensors is the expensive part (~3400 keys), so keep one
// connection + catalog around for callers that poll.
private let directSMCLock = NSLock()
private var cachedDirect: (smc: SMCConnection, catalog: SensorCatalog)?

private func directSMC() throws -> (smc: SMCConnection, catalog: SensorCatalog) {
    directSMCLock.lock()
    defer { directSMCLock.unlock() }
    if let cachedDirect { return cachedDirect }
    let smc = try SMCConnection()
    let pair = (smc: smc, catalog: SensorCatalog(smc: smc))
    cachedDirect = pair
    return pair
}

/// Builds a status snapshot straight from the SMC. Used by the CLI and app as a
/// read-only fallback when fanctld is not installed/running.
public func directStatus() throws -> DaemonStatus {
    let (smc, catalog) = try directSMC()
    let summary = catalog.summary()
    let fans = smc.allFans().map { fan in
        FanStatus(
            id: fan.id, name: fan.name, actualRPM: fan.actualRPM,
            targetRPM: fan.targetRPM, minRPM: fan.minRPM, maxRPM: fan.maxRPM,
            forced: fan.forced, systemOverride: fan.systemOverride)
    }
    return DaemonStatus(
        fans: fans,
        cpuTemp: summary.cpuHot,
        gpuTemp: summary.gpuHot,
        maxTemp: summary.overallMax,
        controlTemp: [summary.cpuHot, summary.gpuHot].compactMap { $0 }.max()
            ?? summary.overallMax,
        config: DaemonConfig(),
        failsafeActive: false,
        canControl: false,
        version: FanControlConstants.version)
}

public func directSensors() throws -> [SensorStatus] {
    let (_, catalog) = try directSMC()
    return catalog.readAll().map {
        SensorStatus(key: $0.key, group: $0.group.rawValue, value: $0.value)
    }
}
