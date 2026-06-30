import Foundation

enum AppConfig {
    static let validExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "mp4", "mov", "avi"]
    static let reportFileName = "report_upload_swift.json"
    static let tokenFileName = "token_swift.json"
    static let googleScope = "https://www.googleapis.com/auth/photoslibrary.appendonly"
    static let similarPhotoDistanceThreshold = 8
    static let blurScoreThreshold = 7.0
}
