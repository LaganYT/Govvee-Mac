import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isAuthenticated = false
    var isBootstrapping = true
    var isLoadingDevices = false
    var devices: [GoveeDevice] = []
    var selectedDeviceID: String?
    var errorMessage: String?
    var statusMessage: String?

    private let client = GoveeAPIClient.shared

    var selectedDevice: GoveeDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

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
            selectedDeviceID = devices.first?.id
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
        selectedDeviceID = nil
        isAuthenticated = false
        statusMessage = nil
        errorMessage = nil
    }

    func refreshDevices() async throws {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        let fetched = try await client.fetchDevices()
        devices = fetched
        if selectedDeviceID == nil || !fetched.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = fetched.first?.id
        }
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
}
