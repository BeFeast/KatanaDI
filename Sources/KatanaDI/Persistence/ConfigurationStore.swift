import Foundation

struct ConfigurationStore {
    let fileURL: URL

    init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".katanadi.json")) {
        self.fileURL = fileURL
    }

    func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaults
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    func save(_ configuration: AppConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }
}
