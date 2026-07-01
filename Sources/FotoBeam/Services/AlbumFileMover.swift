import Foundation

struct AlbumFileMover {
    func move(files: [URL], to directory: URL) throws -> [MoveHistoryItem] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var usedDestinations: Set<String> = []
        var history: [MoveHistoryItem] = []

        for file in files {
            if sameFileURL(file.deletingLastPathComponent(), directory) {
                continue
            }
            let destination = availableURL(
                directory: directory,
                fileName: file.lastPathComponent,
                usedDestinations: &usedDestinations
            )
            try FileManager.default.moveItem(at: file, to: destination)
            history.append(MoveHistoryItem(oldPath: file.path, newPath: destination.path))
        }

        if !history.isEmpty {
            try MoveHistoryStore.append(items: history)
        }
        return history
    }

    private func availableURL(directory: URL, fileName: String, usedDestinations: inout Set<String>) -> URL {
        let original = URL(fileURLWithPath: fileName)
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        var suffix = 0

        while true {
            let candidateName: String
            if suffix == 0 {
                candidateName = fileName
            } else if ext.isEmpty {
                candidateName = "\(base)_\(String(format: "%03d", suffix + 1))"
            } else {
                candidateName = "\(base)_\(String(format: "%03d", suffix + 1)).\(ext)"
            }

            let candidate = directory.appendingPathComponent(candidateName)
            if !usedDestinations.contains(candidate.path) && !FileManager.default.fileExists(atPath: candidate.path) {
                usedDestinations.insert(candidate.path)
                return candidate
            }
            suffix += 1
        }
    }

    private func sameFileURL(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.path == second.standardizedFileURL.path
    }
}

enum MoveHistoryStore {
    static var url: URL {
        projectRoot.appendingPathComponent(AppConfig.moveHistoryFileName)
    }

    static func append(items: [MoveHistoryItem]) throws {
        var history = load()
        history.append(MoveHistory(movedAt: Date(), items: items))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)
        try data.write(to: url, options: .atomic)
    }

    private static func load() -> [MoveHistory] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MoveHistory].self, from: data)) ?? []
    }
}
