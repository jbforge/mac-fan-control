import SwiftUI

@main
struct FanControlApp: App {
    @StateObject private var model = FanModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "fanblades.fill")
                Text(model.headline)
                    .font(.system(.body, design: .rounded).monospacedDigit())
            }
        }
        .menuBarExtraStyle(.window)
    }
}
