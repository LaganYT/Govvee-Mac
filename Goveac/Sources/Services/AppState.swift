import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isAuthenticated = false
    var isBootstrapping = true
    var isLoadingDevices = false
    var devices: [GoveeDevice] = []
    var groups: [DeviceGroup] = []
    var selection: SidebarSelection?
    var errorMessage: String?
    var statusMessage: String?
    var editingGroupID: UUID?
    var isPresentingNewGroup = false

    private let client = GoveeAPIClient.shared

    var selectedDevice: GoveeDevice? {
        guard case .device(let id) = selection else { return nil }
        return devices.first { $0.id == id }
    }

    var selectedGroup: DeviceGroup? {
        guard case .group(let id) = selection else { return nil }
        return groups.first { $0.id == id }
    }

    var ungroupedDevices: [GoveeDevice] {
        let assigned = Set(groups.flatMap(\.deviceIDs))
        return devices.filter { !assigned.contains($0.id) }
    }

    func devices(in group: DeviceGroup) -> [GoveeDevice] {
        let lookup = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        return group.deviceIDs.compactMap { lookup[$0] }
    }

    func groups(containing deviceID: String) -> [DeviceGroup] {
        groups.filter { $0.deviceIDs.contains(deviceID) }
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        groups = GroupStore.load()

        guard let key = KeychainStore.loadAPIKey() else {
            isAuthenticated = false
            return
        }

        do {
            await client.setAPIKey(key)
            try await refreshDevices()
            isAuthenticated = true
        } catch {
            KeychainStore.deleteAPIKey()
            await client.setAPIKey(nil)
            isAuthenticated = false
            errorMessage = error.localizedDescription
        }
    }

    func login(apiKey: String) async {
        errorMessage = nil
        isLoadingDevices = true
        defer { isLoadingDevices = false }

        do {
            let devices = try await client.validateAPIKey(apiKey)
            try KeychainStore.saveAPIKey(apiKey)
            self.devices = devices
            pruneGroupsAgainstDevices()
            ensureSelection()
            isAuthenticated = true
            statusMessage = "Connected · \(devices.count) device\(devices.count == 1 ? "" : "s")"
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticated = false
        }
    }

    func logout() async {
        KeychainStore.deleteAPIKey()
        await client.setAPIKey(nil)
        devices = []
        selection = nil
        isAuthenticated = false
        statusMessage = nil
        errorMessage = nil
    }

    func refreshDevices() async throws {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        let fetched = try await client.fetchDevices()
        devices = fetched
        pruneGroupsAgainstDevices()
        ensureSelection()
        statusMessage = "\(fetched.count) device\(fetched.count == 1 ? "" : "s")"
    }

    func refreshSelectedDeviceState() async {
        guard let device = selectedDevice else { return }
        do {
            let state = try await client.fetchDeviceState(sku: device.sku, device: device.device)
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index] = devices[index].withMergedState(state.capabilities)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func controlSelected(
        type: String,
        instance: String,
        value: JSONValue,
        optimistic: Bool = true
    ) async {
        guard let device = selectedDevice else { return }
        await control(
            device: device,
            type: type,
            instance: instance,
            value: value,
            optimistic: optimistic
        )
    }

    func controlGroup(
        _ group: DeviceGroup,
        type: String,
        instance: String,
        value: JSONValue
    ) async {
        errorMessage = nil
        let members = devices(in: group).filter {
            $0.capability(type: type, instance: instance) != nil
        }
        guard !members.isEmpty else {
            errorMessage = "No devices in this group support that control."
            return
        }

        var failures: [String] = []
        for device in members {
            updateDeviceCapabilityState(
                deviceID: device.id,
                type: type,
                instance: instance,
                value: value
            )
            do {
                try await client.control(
                    sku: device.sku,
                    device: device.device,
                    type: type,
                    instance: instance,
                    value: value
                )
            } catch {
                failures.append(device.displayName)
            }
        }

        if failures.isEmpty {
            statusMessage = "Updated \(group.name) · \(members.count) device\(members.count == 1 ? "" : "s")"
        } else {
            errorMessage = "Failed for: \(failures.joined(separator: ", "))"
        }
    }

    func createGroup(name: String, deviceIDs: [String] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = DeviceGroup(
            name: trimmed,
            deviceIDs: deviceIDs,
            sortOrder: groups.count
        )
        groups.append(group)
        persistGroups()
        selection = .group(group.id)
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
        persistGroups()
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        if case .group(let selected) = selection, selected == id {
            ensureSelection()
        }
        persistGroups()
    }

    func setDevices(_ deviceIDs: [String], inGroup id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].deviceIDs = deviceIDs
        persistGroups()
    }

    func addDevice(_ deviceID: String, toGroup id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].addDevice(deviceID)
        persistGroups()
    }

    func removeDevice(_ deviceID: String, fromGroup id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].removeDevice(deviceID)
        persistGroups()
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        persistGroups()
    }

    func updateDeviceCapabilityState(deviceID: String, type: String, instance: String, value: JSONValue) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        let device = devices[index]
        let capabilities = device.capabilities.map { capability -> GoveeCapability in
            if capability.type == type && capability.instance == instance {
                return GoveeCapability(
                    type: capability.type,
                    instance: capability.instance,
                    parameters: capability.parameters,
                    state: CapabilityState(value: value),
                    alarmType: capability.alarmType
                )
            }
            return capability
        }
        devices[index] = GoveeDevice(
            sku: device.sku,
            device: device.device,
            deviceName: device.deviceName,
            type: device.type,
            capabilities: capabilities
        )
    }

    private func control(
        device: GoveeDevice,
        type: String,
        instance: String,
        value: JSONValue,
        optimistic: Bool
    ) async {
        errorMessage = nil

        if optimistic {
            updateDeviceCapabilityState(
                deviceID: device.id,
                type: type,
                instance: instance,
                value: value
            )
        }

        do {
            try await client.control(
                sku: device.sku,
                device: device.device,
                type: type,
                instance: instance,
                value: value
            )
            statusMessage = "Updated \(device.displayName)"
        } catch {
            errorMessage = error.localizedDescription
            try? await refreshDevices()
            await refreshSelectedDeviceState()
        }
    }

    private func pruneGroupsAgainstDevices() {
        let valid = Set(devices.map(\.id))
        for index in groups.indices {
            groups[index].prune(validDeviceIDs: valid)
        }
        persistGroups()
    }

    private func ensureSelection() {
        switch selection {
        case .device(let id) where devices.contains(where: { $0.id == id }):
            return
        case .group(let id) where groups.contains(where: { $0.id == id }):
            return
        default:
            break
        }

        if let firstGroup = groups.first {
            selection = .group(firstGroup.id)
        } else if let firstDevice = devices.first {
            selection = .device(firstDevice.id)
        } else {
            selection = nil
        }
    }

    private func persistGroups() {
        GroupStore.save(groups)
    }
}
