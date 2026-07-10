import Foundation

enum ReviewMode: String, CaseIterable, Identifiable {
    case all = "Tutti"
    case duplicates = "Duplicati"
    case similar = "Simili"
    case lowQuality = "Qualità bassa"
    case reviewNeeded = "Da valutare"

    var id: String { rawValue }
}

enum QualityFlag: String, CaseIterable {
    case exactDuplicate = "Duplicato"
    case similar = "Simile"
}

enum QualityIssue: String, CaseIterable {
    case blurry = "Probabilmente sfocata"
    case tooDark = "Molto scura"
    case tooBright = "Sovraesposta"
    case lowContrast = "Basso contrasto"
    case lowResolution = "Bassa risoluzione"
    case nearlyUniform = "Quasi vuota"
    case undecodable = "Non decodificabile"
    case crowdedSimilarGroup = "Raffica o gruppo simile numeroso"
}

struct FileQualityInfo {
    var exactDuplicateGroup: Int?
    var similarGroup: Int?
    var blurScore: Double?
    var perceptualHash: UInt64?
    var brightness: Double?
    var contrast: Double?
    var pixelCount: Int?
    var issues: [QualityIssue] = []

    var flags: [QualityFlag] {
        var result: [QualityFlag] = []
        if exactDuplicateGroup != nil {
            result.append(.exactDuplicate)
        }
        if similarGroup != nil {
            result.append(.similar)
        }
        return result
    }

    var summary: String {
        let values = flags.map(\.rawValue)
        let issueValues = issues.map(\.rawValue)
        let allValues = values + issueValues
        return allValues.isEmpty ? "OK" : allValues.joined(separator: ", ")
    }

    mutating func addIssue(_ issue: QualityIssue) {
        if !issues.contains(issue) {
            issues.append(issue)
        }
    }
}

struct QualityAnalysis {
    var files: [String: FileQualityInfo] = [:]
    var exactDuplicateGroups: [[String]] = []
    var similarGroups: [[String]] = []

    var flaggedCount: Int {
        files.values.filter { !$0.flags.isEmpty || !$0.issues.isEmpty }.count
    }

    var duplicateCount: Int {
        files.values.filter { $0.exactDuplicateGroup != nil }.count
    }

    var similarCount: Int {
        files.values.filter { $0.similarGroup != nil }.count
    }

    var blurryCount: Int {
        files.values.filter { $0.issues.contains(.blurry) }.count
    }

    var reviewNeededCount: Int {
        files.values.filter { !$0.issues.isEmpty }.count
    }
}

struct AlbumRow: Identifiable {
    let id = UUID()
    let path: URL
    let originalName: String
    var albumName: String
    var files: [URL]
    var dateRange: String
    var folderSizeBytes: Int64
    var isSelected = true
    var isCompleted = false

    var folderSizeText: String {
        let gigabytes = Double(folderSizeBytes) / 1_000_000_000
        if folderSizeBytes > 0 && gigabytes < 0.01 {
            return "< 0,01 GB"
        }

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: gigabytes)) ?? String(format: "%.2f", gigabytes)
        return "\(value) GB"
    }
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

enum RenameDateSource: String, Codable {
    case exifDateTimeOriginal = "EXIF DateTimeOriginal"
    case imageMetadata = "Metadata immagine"
    case fileName = "Nome file"
    case fileCreationDate = "Data creazione file"
    case fileModificationDate = "Data modifica file"
    case unavailable = "Data non trovata"
}

enum AlbumDateIssue: String, CaseIterable {
    case differentYear = "Anno diverso dalla maggioranza"
    case weakDate = "Solo data file"
    case unavailable = "Data non trovata"
}

struct AlbumDateItem: Identifiable {
    var id: String { file.path }
    let file: URL
    let date: Date?
    let dateSource: RenameDateSource
    let year: Int?
    let issues: [AlbumDateIssue]
}

struct AlbumDateSummary {
    let fileCount: Int
    let dateRange: String
    let years: [Int]
    let majorityYear: Int?
    let suspiciousCount: Int
    let weakDateCount: Int
    let unavailableCount: Int
}

struct AlbumDateAnalysis {
    let items: [AlbumDateItem]
    let summary: AlbumDateSummary
}

enum RenamePlanStatus: String, Codable {
    case ready = "OK"
    case unchanged = "Nome già corretto"
    case dateUnavailable = "Data non trovata"
    case destinationExists = "Nome già esistente"
}

struct RenamePlanItem: Identifiable, Codable {
    var id: String { originalPath }
    let originalPath: String
    let proposedPath: String
    let originalName: String
    let proposedName: String
    let date: Date?
    let dateSource: RenameDateSource
    let status: RenamePlanStatus

    var canApply: Bool {
        status == .ready || status == .unchanged
    }
}

struct RenameHistory: Codable {
    var renamedAt: Date
    var items: [RenameHistoryItem]
}

struct RenameHistoryItem: Codable {
    let oldPath: String
    let newPath: String
    let dateSource: RenameDateSource

    enum CodingKeys: String, CodingKey {
        case oldPath = "old_path"
        case newPath = "new_path"
        case dateSource = "date_source"
    }
}

struct MoveHistory: Codable {
    var movedAt: Date
    var items: [MoveHistoryItem]
}

struct MoveHistoryItem: Codable {
    let oldPath: String
    let newPath: String

    enum CodingKeys: String, CodingKey {
        case oldPath = "old_path"
        case newPath = "new_path"
    }
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
