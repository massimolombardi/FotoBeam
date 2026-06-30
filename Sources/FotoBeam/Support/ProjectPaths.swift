import Foundation

var projectRoot: URL {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("credentials.json").path) {
        return cwd
    }
    let parent = cwd.deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: parent.appendingPathComponent("credentials.json").path) {
        return parent
    }
    return cwd
}

func mimeType(for file: URL) -> String {
    switch file.pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "heic": return "image/heic"
    case "heif": return "image/heif"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "mp4": return "video/mp4"
    case "mov": return "video/quicktime"
    case "avi": return "video/x-msvideo"
    default: return "application/octet-stream"
    }
}

extension String {
    var urlFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
