import Foundation
import FanCore
import SMC

// fanctl — command-line client for fanctld.

let usage = """
usage: fanctl <command>

commands:
  status            show temps, fan speeds and current mode
  sensors           list every temperature sensor
  auto              hand fan control back to macOS (default behavior)
  manual <rpm ...>  fixed speed; one RPM for all fans, or one per fan.
                    accepts percentages too, e.g. `fanctl manual 60%`
  target <temp>     curve mode: ramp fans to keep temps below <temp> °C

status and sensors fall back to reading the SMC directly when fanctld
is not running; the control commands require the daemon (make install).
"""

func fetchStatus() throws -> (DaemonStatus, viaDaemon: Bool) {
    do {
        return (try DaemonClient.status(), true)
    } catch DaemonClientError.notRunning {
        return (try directStatus(), false)
    }
}

func rpmString(_ value: Double) -> String {
    String(format: "%5d", Int(value.rounded()))
}

func printStatus(_ status: DaemonStatus, viaDaemon: Bool) {
    let mode: String
    switch status.config.mode {
    case .auto: mode = "auto (macOS default)"
    case .manual: mode = "manual"
    case .curve: mode = "target ≤ \(Int(status.config.targetTemp))°C"
    }
    print("mode:      \(mode)\(viaDaemon ? "" : "  [daemon not running — read-only]")")
    if status.failsafeActive {
        print("FAILSAFE:  active — temperature reached \(Int(FanControlConstants.failsafeTemp))°C, fans forced to max")
    }
    if let cpu = status.cpuTemp { print("cpu:       \(String(format: "%.1f", cpu))°C") }
    if let gpu = status.gpuTemp { print("gpu:       \(String(format: "%.1f", gpu))°C") }
    for fan in status.fans {
        let control: String
        if fan.systemOverride {
            control = "system (macOS parked this fan; resumes automatically)"
        } else if fan.forced {
            control = "forced → \(Int(fan.targetRPM)) RPM"
        } else {
            control = "auto"
        }
        let percent = fan.percent.map { String(format: "%3d%%", Int($0.rounded())) } ?? "  ?%"
        print("\(fan.name.lowercased().padding(toLength: 10, withPad: " ", startingAt: 0)) "
            + "\(rpmString(fan.actualRPM)) RPM  \(percent)  (range \(Int(fan.minRPM))–\(Int(fan.maxRPM)), \(control))")
    }
}

func applyOrDie(_ config: DaemonConfig) {
    do {
        let status = try DaemonClient.apply(config)
        printStatus(status, viaDaemon: true)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(0)
}

switch command {
case "status":
    do {
        let (status, viaDaemon) = try fetchStatus()
        printStatus(status, viaDaemon: viaDaemon)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case "sensors":
    do {
        let sensors: [SensorStatus]
        if DaemonClient.isDaemonReachable() {
            sensors = try DaemonClient.sensors()
        } else {
            sensors = try directSensors()
        }
        for sensor in sensors.sorted(by: { ($0.group, $0.key) < ($1.group, $1.key) }) {
            print("\(sensor.key)  \(String(format: "%6.1f", sensor.value))°C  \(sensor.group)")
        }
        print("\(sensors.count) sensors")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case "auto":
    do {
        var config = (try DaemonClient.status()).config
        config.mode = .auto
        applyOrDie(config)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case "manual":
    let values = args.dropFirst()
    guard !values.isEmpty else {
        fputs("usage: fanctl manual <rpm|percent%> [more per-fan values]\n", stderr)
        exit(1)
    }
    do {
        let status = try DaemonClient.status()
        guard !status.fans.isEmpty else {
            fputs("error: no fans found\n", stderr)
            exit(1)
        }
        func parse(_ raw: String, fan: FanStatus) -> Double? {
            if raw.hasSuffix("%") {
                guard let pct = Double(raw.dropLast()) else { return nil }
                return fan.minRPM + (pct / 100.0) * (fan.maxRPM - fan.minRPM)
            }
            return Double(raw)
        }
        var rpms: [Double] = []
        for fan in status.fans {
            let raw = fan.id < values.count
                ? values[values.startIndex + fan.id] : values[values.startIndex]
            guard let rpm = parse(raw, fan: fan) else {
                fputs("error: could not parse '\(raw)'\n", stderr)
                exit(1)
            }
            rpms.append(rpm)
        }
        var config = status.config
        config.mode = .manual
        config.manualRPM = rpms
        applyOrDie(config)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case "target":
    guard args.count >= 2, let temp = Double(args[1]) else {
        fputs("usage: fanctl target <celsius>\n", stderr)
        exit(1)
    }
    do {
        var config = (try DaemonClient.status()).config
        config.mode = .curve
        config.targetTemp = temp
        applyOrDie(config)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case "_keys":
    // Hidden: list all SMC keys with a given prefix (default "F").
    let prefix = args.count >= 2 ? args[1] : "F"
    do {
        let smc = try SMCConnection()
        let count = try smc.keyCount()
        for index in 0..<count {
            guard let key = try? smc.key(atIndex: index), key.hasPrefix(prefix) else { continue }
            guard let info = try? smc.keyInfo(key) else { continue }
            let value = (try? smc.readNumeric(key)).map { String(format: "%.2f", $0) }
                ?? (try? smc.readBytes(key)).map { "bytes \($0.bytes.map { String(format: "%02x", $0) }.joined())" }
                ?? "?"
            print("\(key)  [\(info.dataType), \(info.dataSize)B]  \(value)")
        }
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case "_set":
    // Hidden: write a numeric SMC key directly. Root only. For experiments.
    guard args.count >= 3, let value = Double(args[2]) else {
        fputs("usage: fanctl _set <key> <value>\n", stderr)
        exit(1)
    }
    do {
        let smc = try SMCConnection()
        let before = (try? smc.readNumeric(args[1])).map { "\($0)" } ?? "?"
        try smc.writeNumeric(args[1], value: value)
        usleep(300_000)
        let after = (try? smc.readNumeric(args[1])).map { "\($0)" } ?? "?"
        print("\(args[1]): \(before) → \(after)")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case "_diag":
    // Hidden: exercises the raw SMC write path with verbose errors.
    // Run as root: sudo fanctl _diag
    do {
        let smc = try SMCConnection()
        print("euid: \(geteuid())")
        let count = smc.fanCount()
        print("fans: \(count)")
        for id in 0..<count {
            for key in ["F\(id)Md", "F\(id)Tg", "F\(id)Ac", "F\(id)Mn", "F\(id)Mx"] {
                do {
                    let info = try smc.keyInfo(key)
                    let value = try smc.readNumeric(key)
                    print("  \(key): \(value)  [type \(info.dataType), size \(info.dataSize)]")
                } catch {
                    print("  \(key): READ FAILED — \(error)")
                }
            }
            func testWrite(_ key: String, value: Double, restore: Double?) {
                print("  writing \(key) = \(value) ...")
                do {
                    try smc.writeNumeric(key, value: value)
                    usleep(400_000)
                    let readback = (try? smc.readNumeric(key)).map { "\($0)" } ?? "read failed"
                    print("    OK, readback after 0.4s: \(readback)")
                } catch {
                    print("    WRITE FAILED — \(error)")
                }
                if let restore {
                    try? smc.writeNumeric(key, value: restore)
                }
            }
            let origMin = try? smc.readNumeric("F\(id)Mn")
            testWrite("F\(id)Md", value: 0, restore: nil)
            testWrite("F\(id)Tg", value: (origMin ?? 1500) + 111, restore: nil)
            if let origMin {
                testWrite("F\(id)Mn", value: origMin + 222, restore: origMin)
            }
            let mode = (try? smc.readNumeric("F\(id)Md")).map { "\($0)" } ?? "?"
            let target = (try? smc.readNumeric("F\(id)Tg")).map { "\($0)" } ?? "?"
            let minNow = (try? smc.readNumeric("F\(id)Mn")).map { "\($0)" } ?? "?"
            print("  final: F\(id)Md=\(mode) F\(id)Tg=\(target) F\(id)Mn=\(minNow)")
        }
    } catch {
        print("diag failed: \(error)")
        exit(1)
    }

case "-h", "--help", "help":
    print(usage)

default:
    fputs("unknown command: \(command)\n\(usage)\n", stderr)
    exit(1)
}
