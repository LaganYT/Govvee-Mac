import SwiftUI

struct DeviceDetailView: View {
    @Environment(AppState.self) private var appState
    let device: GoveeDevice

    @State private var dynamicScenes: [CapabilityOption] = []
    @State private var diyScenes: [CapabilityOption] = []
    @State private var isLoadingExtras = false
    @State private var brightnessDraft: Double = 50
    @State private var colorTempDraft: Double = 4000
    @State private var selectedColor = Color.white
    @State private var rangeDrafts: [String: Double] = [:]

    private var liveDevice: GoveeDevice {
        appState.devices.first { $0.id == device.id } ?? device
    }

    private var powerCapability: GoveeCapability? {
        liveDevice.capability(type: CapabilityType.onOff, instance: "powerSwitch")
    }

    private var brightnessCapability: GoveeCapability? {
        liveDevice.capability(type: CapabilityType.range, instance: "brightness")
    }

    private var colorCapability: GoveeCapability? {
        liveDevice.capability(type: CapabilityType.colorSetting, instance: "colorRgb")
    }

    private var colorTempCapability: GoveeCapability? {
        liveDevice.capability(type: CapabilityType.colorSetting, instance: "colorTemperatureK")
    }

    private var isOn: Bool {
        powerCapability?.state?.value?.intValue == 1
    }

    private var isOnline: Bool? {
        liveDevice.capability(type: CapabilityType.online, instance: "online")?.state?.value?.boolValue
    }

    private var toggleCapabilities: [GoveeCapability] {
        liveDevice.capabilities.filter { $0.type == CapabilityType.toggle }
    }

    private var modeCapabilities: [GoveeCapability] {
        liveDevice.capabilities.filter { $0.type == CapabilityType.mode }
    }

    private var otherRangeCapabilities: [GoveeCapability] {
        liveDevice.capabilities.filter {
            $0.type == CapabilityType.range && $0.instance != "brightness"
        }
    }

    private var propertyCapabilities: [GoveeCapability] {
        liveDevice.capabilities.filter { $0.type == CapabilityType.property }
    }

    private var staticScenes: [CapabilityOption] {
        liveDevice.capability(type: CapabilityType.dynamicScene, instance: "lightScene")?
            .parameters?.options ?? []
    }

    private var snapshotScenes: [CapabilityOption] {
        liveDevice.capability(type: CapabilityType.dynamicScene, instance: "snapshot")?
            .parameters?.options ?? []
    }

    private var diyStaticScenes: [CapabilityOption] {
        liveDevice.capability(type: CapabilityType.dynamicScene, instance: "diyScene")?
            .parameters?.options
            ?? liveDevice.capability(type: CapabilityType.diyColorSetting, instance: "diyScene")?
            .parameters?.options
            ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                groupsMembership

                if powerCapability != nil || brightnessCapability != nil || colorCapability != nil || colorTempCapability != nil {
                    primaryControls
                }

                if !propertyCapabilities.isEmpty {
                    sectionCard(title: "Readings") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            ForEach(propertyCapabilities, id: \.instance) { capability in
                                ReadingTile(
                                    title: friendlyInstanceName(capability.instance),
                                    value: capability.state?.value?.displayString ?? "—"
                                )
                            }
                        }
                    }
                }

                if !toggleCapabilities.isEmpty {
                    sectionCard(title: "Toggles") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(toggleCapabilities, id: \.instance) { capability in
                                ToggleControlRow(
                                    title: friendlyInstanceName(capability.instance),
                                    isOn: capability.state?.value?.intValue == 1
                                ) { newValue in
                                    Task {
                                        await appState.controlSelected(
                                            type: CapabilityType.toggle,
                                            instance: capability.instance,
                                            value: .int(newValue ? 1 : 0)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if !otherRangeCapabilities.isEmpty {
                    sectionCard(title: "Levels") {
                        VStack(spacing: 16) {
                            ForEach(otherRangeCapabilities, id: \.instance) { capability in
                                RangeControlRow(
                                    title: friendlyInstanceName(capability.instance),
                                    unit: capability.parameters?.unit,
                                    value: Binding(
                                        get: {
                                            rangeDrafts[capability.instance]
                                                ?? capability.state?.value?.intValue.map(Double.init)
                                                ?? capability.parameters?.range?.min
                                                ?? 0
                                        },
                                        set: { rangeDrafts[capability.instance] = $0 }
                                    ),
                                    range: capability.parameters?.range
                                ) {
                                    let value = Int(rangeDrafts[capability.instance]
                                        ?? capability.state?.value?.intValue.map(Double.init)
                                        ?? 0)
                                    Task {
                                        await appState.controlSelected(
                                            type: CapabilityType.range,
                                            instance: capability.instance,
                                            value: .int(value)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if !modeCapabilities.isEmpty {
                    sectionCard(title: "Modes") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(modeCapabilities, id: \.instance) { capability in
                                ModePickerRow(
                                    title: friendlyInstanceName(capability.instance),
                                    options: capability.parameters?.options ?? [],
                                    current: capability.state?.value
                                ) { option in
                                    guard let value = option.value else { return }
                                    Task {
                                        await appState.controlSelected(
                                            type: CapabilityType.mode,
                                            instance: capability.instance,
                                            value: value
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                scenesSection

                if liveDevice.capabilities.contains(where: { $0.type == CapabilityType.workMode }) {
                    WorkModeSection(device: liveDevice)
                }

                metadataFooter
            }
            .padding(28)
        }
        .background(Color.clear)
        .task(id: liveDevice.id) {
            syncDrafts(from: liveDevice)
            await appState.refreshSelectedDeviceState()
            syncDrafts(from: appState.selectedDevice ?? liveDevice)
            await loadExtraScenes()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(liveDevice.displayName)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 10) {
                    Label(liveDevice.typeLabel, systemImage: "tag")
                    Text("·")
                    Text(liveDevice.sku)
                        .font(.system(.body, design: .monospaced))
                    if let isOnline {
                        Text("·")
                        Label(isOnline ? "Online" : "Offline", systemImage: "circle.fill")
                            .foregroundStyle(isOnline ? Theme.online : Theme.offline)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer()

            if powerCapability != nil {
                Button {
                    let next = !isOn
                    Task {
                        await appState.controlSelected(
                            type: CapabilityType.onOff,
                            instance: "powerSwitch",
                            value: .int(next ? 1 : 0)
                        )
                    }
                } label: {
                    Label(isOn ? "On" : "Off", systemImage: isOn ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .foregroundStyle(isOn ? Color(red: 0.12, green: 0.10, blue: 0.06) : Theme.textPrimary)
                        .background(
                            Capsule()
                                .fill(isOn ? Theme.accent : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .panelStyle()
    }

    private var groupsMembership: some View {
        sectionCard(title: "Groups") {
            let memberships = appState.groups(containing: liveDevice.id)

            VStack(alignment: .leading, spacing: 12) {
                if memberships.isEmpty {
                    Text("Not in any group.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    FlowChips(items: memberships.map(\.name)) { name in
                        if let group = memberships.first(where: { $0.name == name }) {
                            appState.selection = .group(group.id)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Menu("Add to Group") {
                        if appState.groups.isEmpty {
                            Button("Create Group…") {
                                appState.createGroup(name: "New Group", deviceIDs: [liveDevice.id])
                                if let id = appState.groups.last?.id {
                                    appState.editingGroupID = id
                                }
                            }
                        } else {
                            ForEach(appState.groups) { group in
                                Button(group.name) {
                                    appState.addDevice(liveDevice.id, toGroup: group.id)
                                }
                                .disabled(group.deviceIDs.contains(liveDevice.id))
                            }
                            Divider()
                            Button("New Group…") {
                                appState.isPresentingNewGroup = true
                            }
                        }
                    }

                    if !memberships.isEmpty {
                        Menu("Remove from") {
                            ForEach(memberships) { group in
                                Button(group.name, role: .destructive) {
                                    appState.removeDevice(liveDevice.id, fromGroup: group.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var primaryControls: some View {
        sectionCard(title: "Lighting") {
            VStack(alignment: .leading, spacing: 20) {
                if let brightnessCapability {
                    RangeControlRow(
                        title: "Brightness",
                        unit: "%",
                        value: $brightnessDraft,
                        range: brightnessCapability.parameters?.range
                    ) {
                        let value = Int(brightnessDraft.rounded())
                        Task {
                            await appState.controlSelected(
                                type: CapabilityType.range,
                                instance: "brightness",
                                value: .int(value)
                            )
                        }
                    }
                }

                if colorCapability != nil {
                    HStack(spacing: 16) {
                        Text("Color")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 110, alignment: .leading)

                        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44, height: 28)

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedColor)
                            .frame(width: 72, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.panelStroke, lineWidth: 1)
                            )

                        Spacer()

                        Button("Apply Color") {
                            let rgb = selectedColor.rgbInt
                            Task {
                                await appState.controlSelected(
                                    type: CapabilityType.colorSetting,
                                    instance: "colorRgb",
                                    value: .int(rgb)
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Color.black)
                    }
                }

                if let colorTempCapability {
                    RangeControlRow(
                        title: "Color Temp",
                        unit: "K",
                        value: $colorTempDraft,
                        range: colorTempCapability.parameters?.range
                    ) {
                        let value = Int(colorTempDraft.rounded())
                        Task {
                            await appState.controlSelected(
                                type: CapabilityType.colorSetting,
                                instance: "colorTemperatureK",
                                value: .int(value)
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scenesSection: some View {
        let allDynamic = dynamicScenes.isEmpty ? staticScenes : dynamicScenes
        let allDIY = diyScenes.isEmpty ? diyStaticScenes : diyScenes

        if !allDynamic.isEmpty || !allDIY.isEmpty || !snapshotScenes.isEmpty || isLoadingExtras {
            sectionCard(title: "Scenes") {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoadingExtras {
                        ProgressView("Loading scenes…")
                            .controlSize(.small)
                            .tint(Theme.accent)
                    }

                    if !allDynamic.isEmpty {
                        SceneChipGrid(title: "Light Scenes", options: allDynamic) { option in
                            guard let value = option.value else { return }
                            Task {
                                await appState.controlSelected(
                                    type: CapabilityType.dynamicScene,
                                    instance: "lightScene",
                                    value: value
                                )
                            }
                        }
                    }

                    if !allDIY.isEmpty {
                        SceneChipGrid(title: "DIY Scenes", options: allDIY) { option in
                            guard let value = option.value else { return }
                            let type = liveDevice.capabilities.contains(where: {
                                $0.type == CapabilityType.diyColorSetting && $0.instance == "diyScene"
                            }) ? CapabilityType.diyColorSetting : CapabilityType.dynamicScene
                            Task {
                                await appState.controlSelected(
                                    type: type,
                                    instance: "diyScene",
                                    value: value
                                )
                            }
                        }
                    }

                    if !snapshotScenes.isEmpty {
                        SceneChipGrid(title: "Snapshots", options: snapshotScenes) { option in
                            guard let value = option.value else { return }
                            Task {
                                await appState.controlSelected(
                                    type: CapabilityType.dynamicScene,
                                    instance: "snapshot",
                                    value: value
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var metadataFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device ID")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            Text(liveDevice.device)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
        .padding(.top, 8)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    private func syncDrafts(from device: GoveeDevice) {
        if let brightness = device.capability(type: CapabilityType.range, instance: "brightness")?.state?.value?.intValue {
            brightnessDraft = Double(brightness)
        } else if let min = device.capability(type: CapabilityType.range, instance: "brightness")?.parameters?.range?.min {
            brightnessDraft = min
        }

        if let kelvin = device.capability(type: CapabilityType.colorSetting, instance: "colorTemperatureK")?.state?.value?.intValue {
            colorTempDraft = Double(kelvin)
        } else if let min = device.capability(type: CapabilityType.colorSetting, instance: "colorTemperatureK")?.parameters?.range?.min {
            colorTempDraft = min
        }

        if let rgb = device.capability(type: CapabilityType.colorSetting, instance: "colorRgb")?.state?.value?.intValue {
            selectedColor = Color(rgb: rgb)
        }

        for capability in device.capabilities where capability.type == CapabilityType.range && capability.instance != "brightness" {
            if let value = capability.state?.value?.intValue {
                rangeDrafts[capability.instance] = Double(value)
            } else if rangeDrafts[capability.instance] == nil, let min = capability.parameters?.range?.min {
                rangeDrafts[capability.instance] = min
            }
        }
    }

    private func loadExtraScenes() async {
        isLoadingExtras = true
        defer { isLoadingExtras = false }
        async let scenes = GoveeAPIClient.shared.fetchScenes(sku: liveDevice.sku, device: liveDevice.device)
        async let diy = GoveeAPIClient.shared.fetchDIYScenes(sku: liveDevice.sku, device: liveDevice.device)
        do {
            dynamicScenes = try await scenes
        } catch {
            dynamicScenes = []
        }
        do {
            diyScenes = try await diy
        } catch {
            diyScenes = []
        }
    }
}

func friendlyInstanceName(_ instance: String) -> String {
    let cleaned = instance
        .replacingOccurrences(of: "Toggle", with: "")
        .replacingOccurrences(of: "Switch", with: "")
    return cleaned
        .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        .capitalized
}

struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Theme.accentSoft)
                                .overlay(Capsule().stroke(Theme.accent.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
