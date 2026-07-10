import Foundation

enum DateOverrideStore {
    static var url: URL {
        projectRoot.appendingPathComponent(AppConfig.dateOverrideFileName)
    }

    static func date(for file: URL) -> Date? {
        load()[file.path]
    }

    static func set(date: Date, for files: [URL]) throws {
        var overrides = load()
        for file in files {
            overrides[file.path] = date
            try updateFileDates(file, date: date)
        }
        try save(overrides)
    }

    private static func load() -> [String: Date] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }

    private static func save(_ overrides: [String: Date]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(overrides)
        try data.write(to: url, options: .atomic)
    }

    private static func updateFileDates(_ file: URL, date: Date) throws {
        try FileManager.default.setAttributes(
            [
                .creationDate: date,
                .modificationDate: date
            ],
            ofItemAtPath: file.path
        )
    }
}
