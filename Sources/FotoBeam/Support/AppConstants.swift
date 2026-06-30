import Foundation

enum AppConfig {
    static let validExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "mp4", "mov", "avi"]
    static let reportFileName = "report_upload_swift.json"
    static let tokenFileName = "token_swift.json"
    static let googleScope = "https://www.googleapis.com/auth/photoslibrary.appendonly"
    static let similarPhotoDistanceThreshold = 8
    static let blurScoreThreshold = 7.0
    static let lowResolutionPixelThreshold = 1_000_000
    static let darkBrightnessThreshold = 35.0
    static let brightBrightnessThreshold = 220.0
    static let lowContrastThreshold = 18.0
    static let uniformImageThreshold = 10.0
    static let largeSimilarGroupThreshold = 6
}
