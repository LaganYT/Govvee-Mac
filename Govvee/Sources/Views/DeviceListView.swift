import AppKit
import SwiftUI

struct DeviceBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var filteredDevices: [GoveeDevice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.devices }
        return appState.devices.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.sku.localizedCaseInsensitiveContains(query)
                || ($0.typeLabel.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarHeader
                Divider().overlay(Theme.panelStroke)
                deviceList
            }
            .background(Color.black.opacity(0.18))
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            if let device = appState.selectedDevice {
                DeviceDetailView(device: device)
                    .id(device.id)
            } else {
                ContentUnavailableView(
                    "No Device Selected",
                    systemImage: "lightbulb",
                    description: Text("Choose a Govee device from the sidebar.")
                )
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let status = appState.statusMessage {
                    Text(status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        do {
                            try await appState.refreshDevices()
                            await appState.refreshSelectedDeviceState()
                        } catch {
                            appState.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isLoadingDevices)
            }
            ToolbarItem(placement: .automatic) {
                Button("Sign Out") {
                    Task { await appState.logout() }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search devices")
        .alert("Something went wrong", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private var sidebarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOVVEE")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(appState.devices.count) devices")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if appState.isLoadingDevices {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var deviceList: some View {
        List(selection: Binding(
            get: { appState.selectedDeviceID },
            set: { appState.selectedDeviceID = $0 }
        )) {
            ForEach(filteredDevices) { device in
                DeviceRowView(device: device)
                    .tag(device.id)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

struct DeviceRowView: View {
    let device: GoveeDevice

    private var isOnline: Bool? {
        device.capability(type: CapabilityType.online, instance: "online")?.state?.value?.boolValue
    }

    private var isOn: Bool {
        device.capability(type: CapabilityType.onOff, instance: "powerSwitch")?.state?.value?.intValue == 1
    }

    private var previewColor: Color {
        if let rgb = device.capability(type: CapabilityType.colorSetting, instance: "colorRgb")?.state?.value?.intValue {
            return Color(rgb: rgb)
        }
        return isOn ? Theme.accent : Theme.offline
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(previewColor.opacity(0.25))
                    .frame(width: 34, height: 34)
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(previewColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(device.typeLabel) · \(device.sku)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let isOnline {
                Circle()
                    .fill(isOnline ? Theme.online : Theme.offline)
                    .frame(width: 7, height: 7)
                    .help(isOnline ? "Online" : "Offline")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        let type = device.type ?? ""
        if type.contains("light") { return "lightbulb.fill" }
        if type.contains("socket") { return "powerplug.fill" }
        if type.contains("heater") { return "flame.fill" }
        if type.contains("humidifier") { return "humidity.fill" }
        if type.contains("purifier") { return "wind" }
        if type.contains("thermometer") || type.contains("sensor") { return "sensor.fill" }
        if type.contains("diffuser") { return "aqi.medium" }
        return "cpu"
    }
}

extension Color {
    init(rgb: Int) {
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    var rgbInt: Int {
        #if canImport(AppKit)
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return 0xFFFFFF }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return (r << 16) | (g << 8) | b
        #else
        return 0xFFFFFF
        #endif
    }
}
