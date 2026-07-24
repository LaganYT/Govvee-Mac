import SwiftUI

@main
struct GoveacApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Devices") {
                Button("New Group…") {
                    appState.isPresentingNewGroup = true
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!appState.isAuthenticated)

                Button("Refresh Devices") {
                    Task {
                        do {
                            try await appState.refreshDevices()
                            await appState.refreshSelectedDeviceState()
                        } catch {
                            appState.errorMessage = error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appState.isAuthenticated)

                Divider()

                Button("Sign Out") {
                    Task { await appState.logout() }
                }
                .disabled(!appState.isAuthenticated)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            Theme.glowGradient.ignoresSafeArea()

            if appState.isBootstrapping {
                ProgressView("Opening Goveac…")
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.textSecondary)
            } else if appState.isAuthenticated {
                DeviceBrowserView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
