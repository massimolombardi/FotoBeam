import Foundation

struct AlbumScanner {
    func scan(folder: URL, report: UploadReport) -> [AlbumRow] {
        guard let albumDirectories = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return albumDirectories
            .filter { isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { directory in
                let files = mediaFilesRecursively(in: directory)
                guard !files.isEmpty else {
                    return nil
                }

                let albumName = directory.lastPathComponent
                let completed = report.albums[albumName]?.status == "COMPLETED"

                return AlbumRow(
                    path: directory,
                    originalName: albumName,
                    albumName: albumName,
                    files: files,
                    dateRange: dateRange(files: files),
                    isSelected: !completed,
                    isCompleted: completed
                )
            }
    }

    private func mediaFilesRecursively(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            if AppConfig.validExtensions.contains(file.pathExtension.lowercased()) {
                files.append(file)
            }
        }

        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func dateRange(files: [URL]) -> String {
        let dates = files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        guard let minDate = dates.min(), let maxDate = dates.max() else {
            return "N/D"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        let start = formatter.string(from: minDate)
        let end = formatter.string(from: maxDate)
        return start == end ? start : "\(start) - \(end)"
    }
}
