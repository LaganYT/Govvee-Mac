import Foundation

struct DeviceGroup: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var deviceIDs: [String]
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, deviceIDs: [String] = [], sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.deviceIDs = deviceIDs
        self.sortOrder = sortOrder
    }

    mutating func addDevice(_ deviceID: String) {
        guard !deviceIDs.contains(deviceID) else { return }
        deviceIDs.append(deviceID)
    }

    mutating func removeDevice(_ deviceID: String) {
        deviceIDs.removeAll { $0 == deviceID }
    }

    mutating func prune(validDeviceIDs: Set<String>) {
        deviceIDs.removeAll { !validDeviceIDs.contains($0) }
    }
}

enum SidebarSelection: Hashable {
    case device(String)
    case group(UUID)
}
