import Foundation
import SwiftUI
import FanCore

@MainActor
final class FanModel: ObservableObject {
    @Published var status: DaemonStatus?
    @Published var daemonAvailable = false
    @Published var lastError: String?

    // Local editing state, so sliders feel responsive between polls.
    @Published var mode: FanMode = .auto
    @Published var manualRPM: [Double] = []
    @Published var targetTemp: Double = 75

    private var timer: Timer?
    private var pushTask: Task<Void, Never>?
    /// Suppress refresh-driven overwrites of controls the user is dragging.
    private var lastUserEdit = Date.distantPast
    /// Fingerprint of the last published status, so identical-looking updates
    /// don't trigger SwiftUI invalidation/layout every poll.
    private var lastFingerprint = ""
    private var menuOpen = false

    init() {
        refresh()
        scheduleTimer()
    }

    /// Poll fast while the popover is visible, slowly (and with generous timer
    /// tolerance, so the system can coalesce wakeups) while only the menu bar
    /// label is showing.
    func setMenuOpen(_ open: Bool) {
        guard menuOpen != open else { return }
        menuOpen = open
        scheduleTimer()
        if open { refresh() }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = menuOpen ? 2 : 10
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = interval * 0.25
        timer = t
    }

    /// Captures everything the UI actually displays, at display precision.
    private static func fingerprint(_ s: DaemonStatus) -> String {
        var parts: [String] = [
            s.config.mode.rawValue,
            "\(Int(s.config.targetTemp))",
            "\(s.failsafeActive)",
            "\(s.canControl)",
            s.config.manualRPM.map { "\(Int($0))" }.joined(separator: ","),
        ]
        if let c = s.cpuTemp { parts.append("c\(Int(c.rounded()))") }
        if let g = s.gpuTemp { parts.append("g\(Int(g.rounded()))") }
        if let t = s.controlTemp { parts.append("t\(Int(t.rounded()))") }
        for f in s.fans {
            parts.append("\(f.id):\(Int(f.actualRPM / 25)):\(Int(f.targetRPM / 25)):\(f.forced):\(f.systemOverride)")
        }
        return parts.joined(separator: "|")
    }

    var headline: String {
        guard let status else { return "–" }
        if let t = status.controlTemp { return "\(Int(t.rounded()))°" }
        return "–"
    }

    func refresh() {
        Task.detached(priority: .utility) {
            var fetched: DaemonStatus?
            var viaDaemon = false
            var errorText: String?
            do {
                fetched = try DaemonClient.status()
                viaDaemon = true
            } catch DaemonClientError.notRunning {
                do {
                    fetched = try directStatus()
                } catch {
                    errorText = "\(error)"
                }
            } catch {
                errorText = "\(error)"
            }
            let result = fetched
            let daemonOK = viaDaemon
            let errText = errorText
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Every @Published assignment invalidates SwiftUI views (menu
                // bar label included), so only assign what actually changed.
                if self.daemonAvailable != daemonOK { self.daemonAvailable = daemonOK }
                if self.lastError != errText { self.lastError = errText }
                if let result {
                    let fp = FanModel.fingerprint(result)
                    if fp != self.lastFingerprint {
                        self.lastFingerprint = fp
                        self.status = result
                    }
                    // Only sync editing state from the daemon when the user
                    // hasn't touched the controls very recently.
                    if Date().timeIntervalSince(self.lastUserEdit) > 3 {
                        if self.mode != result.config.mode {
                            self.mode = result.config.mode
                        }
                        if self.targetTemp != result.config.targetTemp {
                            self.targetTemp = result.config.targetTemp
                        }
                        if !result.config.manualRPM.isEmpty {
                            if self.manualRPM != result.config.manualRPM {
                                self.manualRPM = result.config.manualRPM
                            }
                        } else if self.manualRPM.count != result.fans.count {
                            self.manualRPM = result.fans.map(\.minRPM)
                        }
                    }
                    if self.manualRPM.count != result.fans.count {
                        self.manualRPM = result.fans.map { fan in
                            fan.id < self.manualRPM.count ? self.manualRPM[fan.id] : fan.minRPM
                        }
                    }
                }
            }
        }
    }

    func userChangedSettings() {
        lastUserEdit = Date()
        // Debounce: coalesce slider drags into one write.
        pushTask?.cancel()
        let config = DaemonConfig(mode: mode, manualRPM: manualRPM, targetTemp: targetTemp)
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let outcome: Result<DaemonStatus, Error> = await Task.detached(priority: .userInitiated) {
                do { return .success(try DaemonClient.apply(config)) }
                catch { return .failure(error) }
            }.value
            await MainActor.run {
                guard let self else { return }
                switch outcome {
                case .success(let status):
                    self.status = status
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = "\(error)"
                }
            }
        }
    }
}
