import Foundation

enum AppError: LocalizedError {
    case auth(String)
    case api(String)
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .auth(let message), .api(let message), .fileSystem(let message):
            return message
        }
    }
}
