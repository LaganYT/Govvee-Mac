import SwiftUI

struct GroupDetailView: View {
    @Environment(AppState.self) private var appState
    let groupID: UUID

    @State private var brightnessDraft: Double = 70
    @State private var selectedColor = Color(red: 1.0, green: 0.82, blue: 0.45)

    private var group: DeviceGroup? {
        appState.groups.first { $0.id == groupID }
    }

    private var members: [GoveeDevice] {
        guard let group else { return [] }
        return appState.devices(in: group)
    }

    private var powerCapable: [GoveeDevice] {
        members.filter { $0.hasPower }
    }

    private var brightnessCapable: [GoveeDevice] {
        members.filter { $0.hasBrightness }
    }

    private var colorCapable: [GoveeDevice] {
        members.filter { $0.hasColor }
    }

    var body: some View {
        Group {
            if let group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(group)
                        if !members.isEmpty {
                            groupControls
                        }
                        membersSection(group)
                    }
                    .padding(28)
                }
            } else {
                ContentUnavailableView(
                    "Group Not Found",
                    systemImage: "rectangle.3.group",
                    description: Text("This group may have been deleted.")
                )
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func header(_ group: DeviceGroup) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(group.name)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(members.count) device\(members.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button("Edit Group") {
                appState.editingGroupID = group.id
            }
            .buttonStyle(.bordered)
        }
        .padding(22)
        .panelStyle()
    }

    private var groupControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Group Controls")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            HStack(spacing: 12) {
                if !powerCapable.isEmpty {
                    Button {
                        Task { await controlGroupPower(on: true) }
                    } label: {
                        Label("All On", systemImage: "power.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Color.black)

                    Button {
                        Task { await controlGroupPower(on: false) }
                    } label: {
                        Label("All Off", systemImage: "power.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !brightnessCapable.isEmpty {
                RangeControlRow(
                    title: "Brightness",
                    unit: "%",
                    value: $brightnessDraft,
                    range: CapabilityRange(min: 1, max: 100, precision: 1)
                ) {
                    Task {
                        guard let group else { return }
                        await appState.controlGroup(
                            group,
                            type: CapabilityType.range,
                            instance: "brightness",
                            value: .int(Int(brightnessDraft.rounded()))
                        )
                    }
                }
            }

            if !colorCapable.isEmpty {
                HStack(spacing: 16) {
                    Text("Color")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 110, alignment: .leading)

                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44, height: 28)

                    Spacer()

                    Button("Apply Color") {
                        Task {
                            guard let group else { return }
                            await appState.controlGroup(
                                group,
                                type: CapabilityType.colorSetting,
                                instance: "colorRgb",
                                value: .int(selectedColor.rgbInt)
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Color.black)
                }
            }

            if powerCapable.isEmpty && brightnessCapable.isEmpty && colorCapable.isEmpty {
                Text("Add lights with power, brightness, or color support to use group controls.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    private func membersSection(_ group: DeviceGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Members")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.1)
                Spacer()
                Button("Edit Members") {
                    appState.editingGroupID = group.id
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
            }

            if members.isEmpty {
                Text("No devices in this group yet.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(members) { device in
                    Button {
                        appState.selection = .device(device.id)
                    } label: {
                        HStack {
                            DeviceRowView(device: device)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Group", role: .destructive) {
                            appState.removeDevice(device.id, fromGroup: group.id)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    private func controlGroupPower(on: Bool) async {
        guard let group else { return }
        await appState.controlGroup(
            group,
            type: CapabilityType.onOff,
            instance: "powerSwitch",
            value: .int(on ? 1 : 0)
        )
    }
}
