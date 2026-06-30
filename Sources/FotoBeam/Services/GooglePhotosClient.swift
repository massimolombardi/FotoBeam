import Foundation

final class GooglePhotosClient {
    private let auth: GoogleAuth

    init() async throws {
        auth = try GoogleAuth()
        try await auth.ensureToken()
    }

    func createAlbum(title: String) async throws -> String {
        let body = ["album": ["title": title]]
        let data = try await request(
            url: URL(string: "https://photoslibrary.googleapis.com/v1/albums")!,
            method: "POST",
            jsonBody: body
        )
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String
        else {
            throw AppError.api("Risposta creazione album non valida")
        }
        return id
    }

    func uploadBytes(file: URL) async throws -> String {
        var request = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType(for: file), forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        request.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue(file.lastPathComponent, forHTTPHeaderField: "X-Goog-Upload-File-Name")
        request.httpBody = try Data(contentsOf: file)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw AppError.api("Upload token vuoto")
        }
        return token
    }

    func batchCreate(albumId: String, items: [(file: URL, token: String)]) async throws -> [String: Bool] {
        let mediaItems = items.map {
            [
                "description": $0.file.lastPathComponent,
                "simpleMediaItem": ["uploadToken": $0.token]
            ] as [String: Any]
        }
        let data = try await request(
            url: URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate")!,
            method: "POST",
            jsonBody: ["albumId": albumId, "newMediaItems": mediaItems]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        let results = object["newMediaItemResults"] as? [[String: Any]] ?? []
        var states: [String: Bool] = [:]
        for result in results {
            let status = result["status"] as? [String: Any] ?? [:]
            let mediaItem = result["mediaItem"] as? [String: Any] ?? [:]
            let description = mediaItem["description"] as? String ?? ""
            let code = status["code"] as? Int ?? 0
            let message = (status["message"] as? String ?? "").lowercased()
            states[description] = code == 0 || message == "ok" || message == "success"
        }
        return states
    }

    private func request(url: URL, method: String, jsonBody: Any) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Risposta HTTP non valida")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Errore HTTP \(http.statusCode)"
            throw AppError.api(message)
        }
    }
}
