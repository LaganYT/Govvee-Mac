import SwiftUI

struct GroupEditorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existingGroupID: UUID?

    @State private var name = ""
    @State private var selectedDeviceIDs: Set<String> = []

    private var title: String {
        existingGroupID == nil ? "New Group" : "Edit Group"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider().overlay(Theme.panelStroke)

            Form {
                Section("Name") {
                    TextField("Living Room", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Devices") {
                    if appState.devices.isEmpty {
                        Text("No devices available.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(appState.devices) { device in
                            Toggle(isOn: Binding(
                                get: { selectedDeviceIDs.contains(device.id) },
                                set: { isOn in
                                    if isOn {
                                        selectedDeviceIDs.insert(device.id)
                                    } else {
                                        selectedDeviceIDs.remove(device.id)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.displayName)
                                    Text("\(device.typeLabel) · \(device.sku)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider().overlay(Theme.panelStroke)

            HStack {
                if existingGroupID != nil {
                    Button("Delete Group", role: .destructive) {
                        if let existingGroupID {
                            appState.deleteGroup(existingGroupID)
                        }
                        dismiss()
                    }
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Color.black)
                    .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 440, height: 520)
        .background(Theme.bgBottom)
        .onAppear(perform: load)
    }

    private func load() {
        if let existingGroupID,
           let group = appState.groups.first(where: { $0.id == existingGroupID }) {
            name = group.name
            selectedDeviceIDs = Set(group.deviceIDs)
        }
    }

    private func save() {
        let ids = appState.devices
            .map(\.id)
            .filter { selectedDeviceIDs.contains($0) }

        if let existingGroupID {
            appState.renameGroup(existingGroupID, to: name)
            appState.setDevices(ids, inGroup: existingGroupID)
        } else {
            appState.createGroup(name: name, deviceIDs: ids)
        }
        dismiss()
    }
}
