import SwiftUI

struct RangeControlRow: View {
    let title: String
    var unit: String? = nil
    @Binding var value: Double
    let range: CapabilityRange?
    let onCommit: () -> Void

    private var minValue: Double { range?.min ?? 0 }
    private var maxValue: Double { range?.max ?? 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(displayValue)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            Slider(value: $value, in: minValue...max(minValue + 1, maxValue), step: step)
                .tint(Theme.accent)

            HStack {
                Text("\(Int(minValue))")
                Spacer()
                Button("Set") { onCommit() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Text("\(Int(maxValue))")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var step: Double {
        max(range?.precision ?? 1, 1)
    }

    private var displayValue: String {
        let number = "\(Int(value.rounded()))"
        if let unit, !unit.isEmpty {
            let short = unit
                .replacingOccurrences(of: "unit.", with: "")
                .replacingOccurrences(of: "percent", with: "%")
            return "\(number)\(short == "%" ? "%" : " \(short)")"
        }
        return number
    }
}

struct ToggleControlRow: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { onChange($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
    }
}

struct ModePickerRow: View {
    let title: String
    let options: [CapabilityOption]
    let current: JSONValue?
    let onSelect: (CapabilityOption) -> Void

    private var selectedName: String {
        if let current,
           let match = options.first(where: { $0.value == current }) {
            return match.name ?? "Selected"
        }
        return "Choose…"
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Menu(selectedName) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(option.name ?? "Option") {
                        onSelect(option)
                    }
                }
            }
            .menuStyle(.borderlessButton)
        }
    }
}

struct SceneChipGrid: View {
    let title: String
    let options: [CapabilityOption]
    let onSelect: (CapabilityOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        onSelect(option)
                    } label: {
                        Text(option.name ?? "Scene")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accentSoft)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ReadingTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
    }
}

struct WorkModeSection: View {
    @Environment(AppState.self) private var appState
    let device: GoveeDevice

    @State private var selectedMode: Int?
    @State private var selectedModeValue: Int?

    private var capability: GoveeCapability? {
        device.capability(type: CapabilityType.workMode, instance: "workMode")
    }

    private var modeOptions: [CapabilityOption] {
        capability?.parameters?.fields?.first { $0.fieldName == "workMode" }?.options ?? []
    }

    private var modeValueField: CapabilityField? {
        capability?.parameters?.fields?.first { $0.fieldName == "modeValue" }
    }

    private var currentModeValueOptions: [CapabilityOption] {
        guard let selectedMode,
              let modeName = modeOptions.first(where: { $0.value?.intValue == selectedMode })?.name,
              let nested = modeValueField?.options?.first(where: { $0.name == modeName })?.options else {
            return []
        }
        return nested
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Work Mode")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            HStack {
                Text("Mode")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("Mode", selection: $selectedMode) {
                    Text("Choose…").tag(Optional<Int>.none)
                    ForEach(Array(modeOptions.enumerated()), id: \.offset) { _, option in
                        Text(option.name ?? "Mode")
                            .tag(Optional(option.value?.intValue))
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            if !currentModeValueOptions.isEmpty {
                HStack {
                    Text("Value")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("Value", selection: $selectedModeValue) {
                        Text("Choose…").tag(Optional<Int>.none)
                        ForEach(Array(currentModeValueOptions.enumerated()), id: \.offset) { _, option in
                            Text(option.name ?? option.value?.displayString ?? "Value")
                                .tag(Optional(option.value?.intValue))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            Button("Apply Work Mode") {
                guard let selectedMode else { return }
                var object: [String: JSONValue] = ["workMode": .int(selectedMode)]
                if let selectedModeValue {
                    object["modeValue"] = .int(selectedModeValue)
                }
                Task {
                    await appState.controlSelected(
                        type: CapabilityType.workMode,
                        instance: "workMode",
                        value: .object(object)
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Color.black)
            .disabled(selectedMode == nil)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .onAppear {
            if let state = capability?.state?.value?.objectValue {
                selectedMode = state["workMode"]?.intValue
                selectedModeValue = state["modeValue"]?.intValue
            }
        }
    }
}
