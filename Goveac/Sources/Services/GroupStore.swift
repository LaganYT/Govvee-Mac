import Foundation

enum GroupStore {
    private static let fileName = "device-groups.json"

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Goveac", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static func load() -> [DeviceGroup] {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            // Migrate groups saved by the previous Govvee app name.
            let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Govvee", isDirectory: true)
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: legacy.path),
               let data = try? Data(contentsOf: legacy) {
                try? data.write(to: url, options: [.atomic])
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([DeviceGroup].self, from: data)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            return []
        }
    }

    static func save(_ groups: [DeviceGroup]) {
        do {
            let sorted = groups.enumerated().map { index, group in
                var copy = group
                copy.sortOrder = index
                return copy
            }
            let data = try JSONEncoder().encode(sorted)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence failure is non-fatal; groups remain in memory for the session.
        }
    }
}
