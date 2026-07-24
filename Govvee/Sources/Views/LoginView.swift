import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GOVVEE")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(Theme.textPrimary)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 4)

                    Text("Control your Govee lights and devices from the Mac menu.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("API Key")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    HStack(spacing: 10) {
                        Group {
                            if showKey {
                                TextField("Paste your Govee API key", text: $apiKey)
                            } else {
                                SecureField("Paste your Govee API key", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.28))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Theme.panelStroke, lineWidth: 1)
                                )
                        )

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help(showKey ? "Hide API key" : "Show API key")
                    }

                    Link("Get an API key from Govee Developer", destination: URL(string: "https://developer.govee.com/")!)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }

                if let errorMessage = appState.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    Task { await appState.login(apiKey: apiKey) }
                } label: {
                    HStack {
                        if appState.isLoadingDevices {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(appState.isLoadingDevices ? "Connecting…" : "Connect")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.06))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.82, blue: 0.42),
                                        Theme.accent
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isLoadingDevices)
                .opacity(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
            .padding(36)
            .frame(maxWidth: 460)
            .panelStyle()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.55), value: appeared)

            Spacer(minLength: 40)
        }
        .padding(32)
        .onAppear { appeared = true }
    }
}
