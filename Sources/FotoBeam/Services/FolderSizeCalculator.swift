import Foundation

struct FolderSizeCalculator {
    func sizeBytes(for directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
