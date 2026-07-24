import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        case .string(let value):
            if value.lowercased() == "true" { return true }
            if value.lowercased() == "false" { return false }
            return nil
        default: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var displayString: String {
        switch self {
        case .null: return "—"
        case .bool(let value): return value ? "On" : "Off"
        case .int(let value): return String(value)
        case .double(let value): return String(format: "%.1f", value)
        case .string(let value): return value.isEmpty ? "—" : value
        case .array(let value): return "[\(value.count)]"
        case .object: return "Object"
        }
    }
}

struct GoveeAPIResponse<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let msg: String?
    let requestId: String?
    let data: T?
    let payload: T?

    var bodyMessage: String {
        message ?? msg ?? "Unknown error"
    }
}

struct GoveeDevice: Identifiable, Hashable, Codable, Sendable {
    var id: String { "\(sku)|\(device)" }
    let sku: String
    let device: String
    let deviceName: String?
    let type: String?
    let capabilities: [GoveeCapability]

    var displayName: String {
        if let deviceName, !deviceName.isEmpty { return deviceName }
        return sku
    }

    var typeLabel: String {
        guard let type else { return "Device" }
        return type
            .replacingOccurrences(of: "devices.types.", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    func capability(type: String, instance: String) -> GoveeCapability? {
        capabilities.first { $0.type == type && $0.instance == instance }
    }

    var hasPower: Bool {
        capability(type: CapabilityType.onOff, instance: "powerSwitch") != nil
    }

    var hasBrightness: Bool {
        capability(type: CapabilityType.range, instance: "brightness") != nil
    }

    var hasColor: Bool {
        capability(type: CapabilityType.colorSetting, instance: "colorRgb") != nil
    }

    var hasColorTemp: Bool {
        capability(type: CapabilityType.colorSetting, instance: "colorTemperatureK") != nil
    }
}

struct GoveeCapability: Hashable, Codable, Sendable {
    let type: String
    let instance: String
    let parameters: CapabilityParameters?
    let state: CapabilityState?
    let alarmType: Int?
}

struct CapabilityParameters: Hashable, Codable, Sendable {
    let dataType: String?
    let unit: String?
    let options: [CapabilityOption]?
    let range: CapabilityRange?
    let fields: [CapabilityField]?
}

struct CapabilityOption: Hashable, Codable, Sendable {
    let name: String?
    let value: JSONValue?
    let message: String?
    let options: [CapabilityOption]?
    let defaultValue: JSONValue?
}

struct CapabilityRange: Hashable, Codable, Sendable {
    let min: Double?
    let max: Double?
    let precision: Double?
}

struct CapabilityField: Hashable, Codable, Sendable {
    let fieldName: String?
    let dataType: String?
    let required: Bool?
    let unit: String?
    let options: [CapabilityOption]?
    let range: CapabilityRange?
    let size: CapabilityRange?
    let elementRange: CapabilityRange?
    let elementType: String?
    let defaultValue: JSONValue?
}

struct CapabilityState: Hashable, Codable, Sendable {
    let value: JSONValue?
}

enum CapabilityType {
    static let onOff = "devices.capabilities.on_off"
    static let toggle = "devices.capabilities.toggle"
    static let range = "devices.capabilities.range"
    static let mode = "devices.capabilities.mode"
    static let colorSetting = "devices.capabilities.color_setting"
    static let segmentColorSetting = "devices.capabilities.segment_color_setting"
    static let musicSetting = "devices.capabilities.music_setting"
    static let dynamicScene = "devices.capabilities.dynamic_scene"
    static let workMode = "devices.capabilities.work_mode"
    static let temperatureSetting = "devices.capabilities.temperature_setting"
    static let online = "devices.capabilities.online"
    static let property = "devices.capabilities.property"
    static let event = "devices.capabilities.event"
    static let diyColorSetting = "devices.capabilities.diy_color_setting"
}

struct ControlRequest: Encodable {
    let requestId: String
    let payload: ControlPayload
}

struct ControlPayload: Encodable {
    let sku: String
    let device: String
    let capability: ControlCapability
}

struct ControlCapability: Encodable {
    let type: String
    let instance: String
    let value: JSONValue
}

struct DeviceLookupRequest: Encodable {
    let requestId: String
    let payload: DeviceLookupPayload
}

struct DeviceLookupPayload: Encodable {
    let sku: String
    let device: String
}

struct DeviceStatePayload: Decodable {
    let sku: String
    let device: String
    let capabilities: [GoveeCapability]
}

struct ScenesPayload: Decodable {
    let sku: String
    let device: String
    let capabilities: [GoveeCapability]
}

extension GoveeDevice {
    func withMergedState(_ stateCapabilities: [GoveeCapability]) -> GoveeDevice {
        let stateMap = Dictionary(uniqueKeysWithValues: stateCapabilities.map { ("\($0.type)|\($0.instance)", $0) })
        let merged = capabilities.map { capability -> GoveeCapability in
            let key = "\(capability.type)|\(capability.instance)"
            if let stateCap = stateMap[key] {
                return GoveeCapability(
                    type: capability.type,
                    instance: capability.instance,
                    parameters: capability.parameters,
                    state: stateCap.state,
                    alarmType: capability.alarmType
                )
            }
            return capability
        }

        var extras = stateCapabilities.filter { stateCap in
            !capabilities.contains { $0.type == stateCap.type && $0.instance == stateCap.instance }
        }

        return GoveeDevice(
            sku: sku,
            device: device,
            deviceName: deviceName,
            type: type,
            capabilities: merged + extras
        )
    }
}
