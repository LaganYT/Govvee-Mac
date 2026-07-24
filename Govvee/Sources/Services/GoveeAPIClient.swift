import Foundation

enum GoveeAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case rateLimited
    case badStatus(Int, String)
    case api(Int, String)
    case emptyData
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .unauthorized:
            return "Unauthorized. Check your API key."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .badStatus(let code, let message):
            return "HTTP \(code): \(message)"
        case .api(let code, let message):
            return "Govee \(code): \(message)"
        case .emptyData:
            return "No data returned from Govee."
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

actor GoveeAPIClient {
    static let shared = GoveeAPIClient()

    private let baseURL = URL(string: "https://openapi.api.govee.com")!
    private let session: URLSession
    private var apiKey: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func setAPIKey(_ key: String?) {
        apiKey = key?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validateAPIKey(_ key: String) async throws -> [GoveeDevice] {
        setAPIKey(key)
        return try await fetchDevices()
    }

    func fetchDevices() async throws -> [GoveeDevice] {
        let response: GoveeAPIResponse<[GoveeDevice]> = try await request(
            method: "GET",
            path: "/router/api/v1/user/devices"
        )
        guard let devices = response.data else {
            throw GoveeAPIError.emptyData
        }
        return devices.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func fetchDeviceState(sku: String, device: String) async throws -> DeviceStatePayload {
        let body = DeviceLookupRequest(
            requestId: UUID().uuidString,
            payload: DeviceLookupPayload(sku: sku, device: device)
        )
        let response: GoveeAPIResponse<DeviceStatePayload> = try await request(
            method: "POST",
            path: "/router/api/v1/device/state",
            body: body
        )
        guard let payload = response.payload else {
            throw GoveeAPIError.emptyData
        }
        return payload
    }

    func fetchScenes(sku: String, device: String) async throws -> [CapabilityOption] {
        let body = DeviceLookupRequest(
            requestId: UUID().uuidString,
            payload: DeviceLookupPayload(sku: sku, device: device)
        )
        let response: GoveeAPIResponse<ScenesPayload> = try await request(
            method: "POST",
            path: "/router/api/v1/device/scenes",
            body: body
        )
        return response.payload?
            .capabilities
            .first { $0.type == CapabilityType.dynamicScene && $0.instance == "lightScene" }?
            .parameters?
            .options ?? []
    }

    func fetchDIYScenes(sku: String, device: String) async throws -> [CapabilityOption] {
        let body = DeviceLookupRequest(
            requestId: UUID().uuidString,
            payload: DeviceLookupPayload(sku: sku, device: device)
        )
        let response: GoveeAPIResponse<ScenesPayload> = try await request(
            method: "POST",
            path: "/router/api/v1/device/diy-scenes",
            body: body
        )
        return response.payload?
            .capabilities
            .first?
            .parameters?
            .options ?? []
    }

    func control(
        sku: String,
        device: String,
        type: String,
        instance: String,
        value: JSONValue
    ) async throws {
        let body = ControlRequest(
            requestId: UUID().uuidString,
            payload: ControlPayload(
                sku: sku,
                device: device,
                capability: ControlCapability(type: type, instance: instance, value: value)
            )
        )
        let response: GoveeAPIResponse<EmptyPayload> = try await request(
            method: "POST",
            path: "/router/api/v1/device/control",
            body: body
        )
        if let code = response.code, code != 200 {
            throw GoveeAPIError.api(code, response.bodyMessage)
        }
    }

    private struct EmptyPayload: Decodable {}

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws -> GoveeAPIResponse<T> {
        guard let apiKey, !apiKey.isEmpty else {
            throw GoveeAPIError.unauthorized
        }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw GoveeAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Govee-API-Key")
        request.timeoutInterval = 30

        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoveeAPIError.badStatus(-1, "Invalid response")
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw GoveeAPIError.unauthorized
        case 429:
            throw GoveeAPIError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw GoveeAPIError.badStatus(http.statusCode, message)
        }

        do {
            let decoded = try JSONDecoder().decode(GoveeAPIResponse<T>.self, from: data)
            if let code = decoded.code, !(200...299).contains(code) {
                if code == 401 { throw GoveeAPIError.unauthorized }
                if code == 429 { throw GoveeAPIError.rateLimited }
                throw GoveeAPIError.api(code, decoded.bodyMessage)
            }
            return decoded
        } catch let error as GoveeAPIError {
            throw error
        } catch {
            throw GoveeAPIError.decoding(error)
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeFunc = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
