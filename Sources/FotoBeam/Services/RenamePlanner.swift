import Foundation
import ImageIO

struct RenamePlanner {
    func makePlan(files: [URL]) -> [RenamePlanItem] {
        let datedFiles = files.map { file in
            let captured = captureDate(for: file)
            return (file: file, captured: captured)
        }
        .sorted { first, second in
            switch (first.captured.date, second.captured.date) {
            case let (firstDate?, secondDate?):
                if firstDate == secondDate {
                    return first.file.path.localizedStandardCompare(second.file.path) == .orderedAscending
                }
                return firstDate < secondDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return first.file.path.localizedStandardCompare(second.file.path) == .orderedAscending
            }
        }

        var usedDestinations: Set<String> = []
        var sequenceBySecond: [String: Int] = [:]

        return datedFiles.map { entry in
            let file = entry.file
            let captured = entry.captured

            guard let date = captured.date else {
                return RenamePlanItem(
                    originalPath: file.path,
                    proposedPath: file.path,
                    originalName: file.lastPathComponent,
                    proposedName: file.lastPathComponent,
                    date: nil,
                    dateSource: .unavailable,
                    status: .dateUnavailable
                )
            }

            let secondKey = secondFormatter.string(from: date)
            sequenceBySecond[secondKey, default: 0] += 1
            let sequence = sequenceBySecond[secondKey, default: 1]
            let directory = file.deletingLastPathComponent()
            let prefix = mediaPrefix(for: file)
            let proposed = availableURL(
                directory: directory,
                baseName: "\(prefix)_\(secondKey)_\(String(format: "%03d", sequence))",
                extensionName: file.pathExtension.lowercased(),
                original: file,
                usedDestinations: &usedDestinations
            )

            let status: RenamePlanStatus
            if proposed.path == file.path {
                status = .unchanged
            } else if FileManager.default.fileExists(atPath: proposed.path) {
                status = .destinationExists
            } else {
                status = .ready
            }

            return RenamePlanItem(
                originalPath: file.path,
                proposedPath: proposed.path,
                originalName: file.lastPathComponent,
                proposedName: proposed.lastPathComponent,
                date: date,
                dateSource: captured.source,
                status: status
            )
        }
    }

    func apply(plan: [RenamePlanItem]) throws -> [RenameHistoryItem] {
        let applicable = plan.filter { $0.status == .ready }
        var history: [RenameHistoryItem] = []

        for item in applicable {
            let source = URL(fileURLWithPath: item.originalPath)
            let destination = URL(fileURLWithPath: item.proposedPath)
            try FileManager.default.moveItem(at: source, to: destination)
            history.append(RenameHistoryItem(oldPath: item.originalPath, newPath: item.proposedPath, dateSource: item.dateSource))
        }

        if !history.isEmpty {
            try RenameHistoryStore.append(items: history)
        }
        return history
    }

    private func availableURL(
        directory: URL,
        baseName: String,
        extensionName: String,
        original: URL,
        usedDestinations: inout Set<String>
    ) -> URL {
        var suffix = 0
        while true {
            let candidateName = suffix == 0 ? baseName : "\(baseName)_\(String(format: "%03d", suffix + 1))"
            let fileName = extensionName.isEmpty ? candidateName : "\(candidateName).\(extensionName)"
            let candidate = directory.appendingPathComponent(fileName)

            if candidate.path == original.path {
                usedDestinations.insert(candidate.path)
                return candidate
            }
            if !usedDestinations.contains(candidate.path) && !FileManager.default.fileExists(atPath: candidate.path) {
                usedDestinations.insert(candidate.path)
                return candidate
            }
            suffix += 1
        }
    }

    private func captureDate(for file: URL) -> (date: Date?, source: RenameDateSource) {
        if let imageDate = imageCaptureDate(for: file) {
            return imageDate
        }
        if let date = dateFromFileName(file.lastPathComponent) {
            return (date, .fileName)
        }

        let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        if let creationDate = values?.creationDate {
            return (creationDate, .fileCreationDate)
        }
        if let modificationDate = values?.contentModificationDate {
            return (modificationDate, .fileModificationDate)
        }
        return (nil, .unavailable)
    }

    private func imageCaptureDate(for file: URL) -> (date: Date, source: RenameDateSource)? {
        guard
            let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        if
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            let date = exifFormatter.date(from: value)
        {
            return (date, .exifDateTimeOriginal)
        }

        if
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
            let value = tiff[kCGImagePropertyTIFFDateTime] as? String,
            let date = exifFormatter.date(from: value)
        {
            return (date, .imageMetadata)
        }

        return nil
    }

    private func dateFromFileName(_ fileName: String) -> Date? {
        let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let pattern = #"^(IMG|VID)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_\d{3}(?:_\d{3})?$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
            let range = Range(match.range(at: 2), in: name)
        else {
            return nil
        }
        return secondFormatter.date(from: String(name[range]))
    }

    private func mediaPrefix(for file: URL) -> String {
        let videoExtensions = ["mp4", "mov", "avi"]
        return videoExtensions.contains(file.pathExtension.lowercased()) ? "VID" : "IMG"
    }

    private var secondFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    private var exifFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }
}

enum RenameHistoryStore {
    static var url: URL {
        projectRoot.appendingPathComponent(AppConfig.renameHistoryFileName)
    }

    static func append(items: [RenameHistoryItem]) throws {
        var history = load()
        history.append(RenameHistory(renamedAt: Date(), items: items))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)
        try data.write(to: url, options: .atomic)
    }

    private static func load() -> [RenameHistory] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RenameHistory].self, from: data)) ?? []
    }
}
