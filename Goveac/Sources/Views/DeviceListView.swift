import AppKit
import SwiftUI

struct DeviceBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredGroups: [DeviceGroup] {
        guard !query.isEmpty else { return appState.groups }
        return appState.groups.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
                || appState.devices(in: group).contains {
                    matchesSearch($0)
                }
        }
    }

    private var filteredUngroupedDevices: [GoveeDevice] {
        let devices = appState.ungroupedDevices
        guard !query.isEmpty else { return devices }
        return devices.filter(matchesSearch)
    }

    private var filteredAllDevices: [GoveeDevice] {
        guard !query.isEmpty else { return appState.devices }
        return appState.devices.filter(matchesSearch)
    }

    private var isSearching: Bool { !query.isEmpty }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarHeader
                Divider().overlay(Theme.panelStroke)
                deviceList
            }
            .background(Color.black.opacity(0.18))
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detailContent
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
                    appState.isPresentingNewGroup = true
                } label: {
                    Label("New Group", systemImage: "plus.rectangle.on.folder")
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
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search devices & groups")
        .sheet(isPresented: Binding(
            get: { appState.isPresentingNewGroup },
            set: { appState.isPresentingNewGroup = $0 }
        )) {
            GroupEditorSheet(existingGroupID: nil)
                .environment(appState)
        }
        .sheet(item: Binding(
            get: { appState.editingGroupID.map(IdentifiedUUID.init) },
            set: { appState.editingGroupID = $0?.id }
        )) { identified in
            GroupEditorSheet(existingGroupID: identified.id)
                .environment(appState)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch appState.selection {
        case .device(let id):
            if let device = appState.devices.first(where: { $0.id == id }) {
                DeviceDetailView(device: device)
                    .id(device.id)
            } else {
                emptyDetail
            }
        case .group(let id):
            GroupDetailView(groupID: id)
                .id(id)
        case nil:
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView(
            "Nothing Selected",
            systemImage: "lightbulb",
            description: Text("Choose a group or device from the sidebar.")
        )
        .foregroundStyle(Theme.textSecondary)
    }

    private var sidebarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOVEAC")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(appState.devices.count) devices · \(appState.groups.count) groups")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                appState.isPresentingNewGroup = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.accentSoft))
            }
            .buttonStyle(.plain)
            .help("New Group")

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
            get: { appState.selection },
            set: { appState.selection = $0 }
        )) {
            if isSearching {
                Section("Results") {
                    ForEach(filteredGroups) { group in
                        GroupRowView(group: group, memberCount: appState.devices(in: group).count)
                            .tag(SidebarSelection.group(group.id))
                            .listRowBackground(Color.clear)
                            .contextMenu { groupContextMenu(group) }
                    }
                    ForEach(filteredAllDevices) { device in
                        DeviceRowView(device: device)
                            .tag(SidebarSelection.device(device.id))
                            .listRowBackground(Color.clear)
                            .contextMenu { deviceContextMenu(device) }
                    }
                }
            } else {
                Section("Groups") {
                    if appState.groups.isEmpty {
                        Text("No groups yet")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredGroups) { group in
                            GroupRowView(group: group, memberCount: appState.devices(in: group).count)
                                .tag(SidebarSelection.group(group.id))
                                .listRowBackground(Color.clear)
                                .contextMenu { groupContextMenu(group) }
                        }
                        .onMove { source, destination in
                            appState.moveGroups(from: source, to: destination)
                        }
                    }
                }

                Section(ungroupedSectionTitle) {
                    ForEach(filteredUngroupedDevices) { device in
                        DeviceRowView(device: device)
                            .tag(SidebarSelection.device(device.id))
                            .listRowBackground(Color.clear)
                            .contextMenu { deviceContextMenu(device) }
                    }
                }

                if !appState.groups.isEmpty {
                    Section("All Devices") {
                        ForEach(appState.devices) { device in
                            DeviceRowView(device: device)
                                .tag(SidebarSelection.device(device.id))
                                .listRowBackground(Color.clear)
                                .contextMenu { deviceContextMenu(device) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var ungroupedSectionTitle: String {
        appState.groups.isEmpty ? "Devices" : "Ungrouped"
    }

    @ViewBuilder
    private func groupContextMenu(_ group: DeviceGroup) -> some View {
        Button("Edit Group…") {
            appState.editingGroupID = group.id
        }
        Button("Delete Group", role: .destructive) {
            appState.deleteGroup(group.id)
        }
    }

    @ViewBuilder
    private func deviceContextMenu(_ device: GoveeDevice) -> some View {
        if appState.groups.isEmpty {
            Button("New Group with Device…") {
                appState.createGroup(name: "New Group", deviceIDs: [device.id])
                if let id = appState.groups.last?.id {
                    appState.editingGroupID = id
                }
            }
        } else {
            Menu("Add to Group") {
                ForEach(appState.groups) { group in
                    Button(group.name) {
                        appState.addDevice(device.id, toGroup: group.id)
                    }
                    .disabled(group.deviceIDs.contains(device.id))
                }
            }
            let memberships = appState.groups(containing: device.id)
            if !memberships.isEmpty {
                Menu("Remove from Group") {
                    ForEach(memberships) { group in
                        Button(group.name) {
                            appState.removeDevice(device.id, fromGroup: group.id)
                        }
                    }
                }
            }
        }
    }

    private func matchesSearch(_ device: GoveeDevice) -> Bool {
        device.displayName.localizedCaseInsensitiveContains(query)
            || device.sku.localizedCaseInsensitiveContains(query)
            || device.typeLabel.localizedCaseInsensitiveContains(query)
    }
}

private struct IdentifiedUUID: Identifiable {
    let id: UUID
}

struct GroupRowView: View {
    let group: DeviceGroup
    let memberCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accentSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(memberCount) device\(memberCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
