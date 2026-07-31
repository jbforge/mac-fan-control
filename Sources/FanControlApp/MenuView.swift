import SwiftUI
import FanCore

struct MenuView: View {
    @EnvironmentObject var model: FanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let status = model.status {
                temperatureRow(status)
                Divider()
                fansSection(status)
                Divider()
                modeSection(status)
            } else if let error = model.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.setMenuOpen(true) }
        .onDisappear { model.setMenuOpen(false) }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Label("Fan Control", systemImage: "fanblades.fill")
                .font(.headline)
            Spacer()
            if model.status?.failsafeActive == true {
                Label("Failsafe", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
    }

    private func temperatureRow(_ status: DaemonStatus) -> some View {
        HStack(spacing: 16) {
            if let cpu = status.cpuTemp {
                tempBadge("CPU", cpu)
            }
            if let gpu = status.gpuTemp {
                tempBadge("GPU", gpu)
            }
            Spacer()
        }
    }

    private func tempBadge(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value, specifier: "%.0f")°C")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(tempColor(value))
        }
    }

    private func tempColor(_ value: Double) -> Color {
        switch value {
        case ..<70: return .primary
        case ..<90: return .orange
        default: return .red
        }
    }

    private func fansSection(_ status: DaemonStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(status.fans) { fan in
                HStack {
                    Image(systemName: "fanblades")
                        .foregroundStyle(.secondary)
                    Text(fan.name)
                    Spacer()
                    Text("\(Int(fan.actualRPM)) RPM")
                        .font(.body.monospacedDigit())
                    if let percent = fan.percent {
                        Text("\(Int(percent.rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    let (label, color): (String, Color) = fan.systemOverride
                        ? ("system", .blue)
                        : fan.forced ? ("forced", .orange) : ("auto", .green)
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.18), in: Capsule())
                        .foregroundStyle(color)
                }
            }
            if status.fans.isEmpty {
                Text("No fans detected")
                    .foregroundStyle(.secondary)
            }
            if status.fans.contains(where: \.systemOverride) {
                Label(
                    "macOS has parked the fans and locked fan control (a macOS 26 " +
                    "firmware behavior). Reclaiming automatically the moment it lets go.",
                    systemImage: "lock.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func modeSection(_ status: DaemonStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $model.mode) {
                Text("Auto").tag(FanMode.auto)
                Text("Manual").tag(FanMode.manual)
                Text("Target temp").tag(FanMode.curve)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.mode) { _, _ in model.userChangedSettings() }
            .disabled(!model.daemonAvailable)

            if !model.daemonAvailable {
                Label("Helper not running — read-only. Install with `make install`.",
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if status.canControl == false {
                Label("Helper is running without root and cannot control fans.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            switch model.mode {
            case .auto:
                Text("macOS manages fan speed (system default).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .manual:
                ForEach(status.fans) { fan in
                    if fan.id < model.manualRPM.count {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(fan.name).font(.caption)
                                Spacer()
                                Text(manualLabel(for: fan))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { model.manualRPM[fan.id] },
                                    set: { model.manualRPM[fan.id] = $0 }),
                                in: fan.minRPM...max(fan.maxRPM, fan.minRPM + 1),
                                onEditingChanged: { editing in
                                    if !editing { model.userChangedSettings() }
                                })
                                .disabled(!model.daemonAvailable)
                        }
                    }
                }

            case .curve:
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Keep below").font(.caption)
                        Spacer()
                        Text("\(Int(model.targetTemp))°C")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $model.targetTemp,
                        in: 65...95,
                        step: 1,
                        onEditingChanged: { editing in
                            if !editing { model.userChangedSettings() }
                        })
                        .disabled(!model.daemonAvailable)
                    Text("Fans ramp instantly as temps approach the ceiling and idle at minimum speed when cool.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func manualLabel(for fan: FanStatus) -> String {
        let rpm = model.manualRPM[fan.id]
        guard fan.maxRPM > fan.minRPM else { return "\(Int(rpm)) RPM" }
        let fraction = (rpm - fan.minRPM) / (fan.maxRPM - fan.minRPM)
        let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
        return "\(Int(rpm)) RPM · \(percent)%"
    }

    private var footer: some View {
        HStack {
            if let error = model.lastError, model.status != nil {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.caption)
        }
    }
}
