import Foundation

enum AppError: LocalizedError {
    case auth(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .auth(let message), .api(let message):
            return message
        }
    }
}
