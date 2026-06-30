import Foundation

enum ReviewMode: String, CaseIterable, Identifiable {
    case all = "Tutti"
    case duplicates = "Duplicati"
    case similar = "Simili"
    case lowQuality = "Qualità bassa"

    var id: String { rawValue }
}

enum QualityFlag: String, CaseIterable {
    case exactDuplicate = "Duplicato"
    case similar = "Simile"
    case blurry = "Sfocata"
}

struct FileQualityInfo {
    var exactDuplicateGroup: Int?
    var similarGroup: Int?
    var blurScore: Double?
    var perceptualHash: UInt64?

    var flags: [QualityFlag] {
        var result: [QualityFlag] = []
        if exactDuplicateGroup != nil {
            result.append(.exactDuplicate)
        }
        if similarGroup != nil {
            result.append(.similar)
        }
        if let blurScore, blurScore < AppConfig.blurScoreThreshold {
            result.append(.blurry)
        }
        return result
    }

    var summary: String {
        let values = flags.map(\.rawValue)
        return values.isEmpty ? "OK" : values.joined(separator: ", ")
    }
}

struct QualityAnalysis {
    var files: [String: FileQualityInfo] = [:]
    var exactDuplicateGroups: [[String]] = []
    var similarGroups: [[String]] = []

    var flaggedCount: Int {
        files.values.filter { !$0.flags.isEmpty }.count
    }

    var duplicateCount: Int {
        files.values.filter { $0.exactDuplicateGroup != nil }.count
    }

    var similarCount: Int {
        files.values.filter { $0.similarGroup != nil }.count
    }

    var blurryCount: Int {
        files.values.filter { info in
            if let score = info.blurScore {
                return score < AppConfig.blurScoreThreshold
            }
            return false
        }.count
    }
}

struct AlbumRow: Identifiable {
    let id = UUID()
    let path: URL
    let originalName: String
    var albumName: String
    let files: [URL]
    let dateRange: String
    var isSelected = true
    var isCompleted = false
}

struct FilePreviewItem: Identifiable {
    let id = UUID()
    let fileName: String
    let path: String
    let status: String
    let willUpload: Bool
    let reason: String
    let isManuallySelected: Bool
    let qualitySummary: String
}

struct GoogleCredentials: Decodable {
    let installed: Installed

    struct Installed: Decodable {
        let clientId: String
        let clientSecret: String
        let authUri: String
        let tokenUri: String

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case authUri = "auth_uri"
            case tokenUri = "token_uri"
        }
    }
}

struct OAuthToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
    }

    var isValid: Bool {
        expiresAt.timeIntervalSinceNow > 60
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct UploadReport: Codable {
    var sessionStart = Date()
    var albums: [String: AlbumReport] = [:]

    enum CodingKeys: String, CodingKey {
        case sessionStart = "session_start"
        case albums
    }
}

struct AlbumReport: Codable {
    var status: String
    var albumId: String?
    var files: [String: FileReport]

    enum CodingKeys: String, CodingKey {
        case status
        case albumId = "album_id"
        case files
    }
}

struct FileReport: Codable {
    var status: String
}
