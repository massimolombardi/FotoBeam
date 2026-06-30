import AppKit
import Foundation
import Network

final class GoogleAuth {
    private let credentials: GoogleCredentials
    private var token: OAuthToken?

    init() throws {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("credentials.json"))
        credentials = try JSONDecoder().decode(GoogleCredentials.self, from: data)
        token = Self.loadToken()
    }

    func accessToken() async throws -> String {
        try await ensureToken()
        guard let token else {
            throw AppError.auth("Token mancante")
        }
        return token.accessToken
    }

    func ensureToken() async throws {
        if let token, token.isValid {
            return
        }
        if let refreshToken = token?.refreshToken {
            self.token = try await refresh(refreshToken: refreshToken)
            Self.saveToken(self.token)
            return
        }
        self.token = try await authorize()
        Self.saveToken(self.token)
    }

    private func authorize() async throws -> OAuthToken {
        let receiver = try LoopbackReceiver()
        let redirectURI = "http://127.0.0.1:\(receiver.port)/oauth2callback"

        var components = URLComponents(string: credentials.installed.authUri)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.installed.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: AppConfig.googleScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw AppError.auth("URL OAuth non valido")
        }
        NSWorkspace.shared.open(authURL)
        let code = try await receiver.waitForCode()
        return try await exchange(code: code, redirectURI: redirectURI)
    }

    private func exchange(code: String, redirectURI: String) async throws -> OAuthToken {
        let params = [
            "code": code,
            "client_id": credentials.installed.clientId,
            "client_secret": credentials.installed.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        return try await tokenRequest(params: params)
    }

    private func refresh(refreshToken: String) async throws -> OAuthToken {
        let params = [
            "client_id": credentials.installed.clientId,
            "client_secret": credentials.installed.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        var refreshed = try await tokenRequest(params: params)
        refreshed.refreshToken = refreshed.refreshToken ?? refreshToken
        return refreshed
    }

    private func tokenRequest(params: [String: String]) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: credentials.installed.tokenUri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.auth(String(data: data, encoding: .utf8) ?? "Errore token OAuth")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            tokenType: decoded.tokenType,
            expiresAt: Date().addingTimeInterval(decoded.expiresIn)
        )
    }

    private static func loadToken() -> OAuthToken? {
        guard let data = try? Data(contentsOf: projectRoot.appendingPathComponent(AppConfig.tokenFileName)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OAuthToken.self, from: data)
    }

    private static func saveToken(_ token: OAuthToken?) {
        guard let token else {
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(token) {
            try? data.write(to: projectRoot.appendingPathComponent(AppConfig.tokenFileName), options: .atomic)
        }
    }
}

final class LoopbackReceiver: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?

    init() throws {
        let selectedPort = UInt16.random(in: 49152...65535)
        guard let nwPort = NWEndpoint.Port(rawValue: selectedPort) else {
            throw AppError.auth("Impossibile aprire porta OAuth locale")
        }
        listener = try NWListener(using: .tcp, on: nwPort)
        port = selectedPort
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: .main)
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.continuation?.resume(throwing: error)
                self.listener.cancel()
                return
            }
            guard
                let data,
                let request = String(data: data, encoding: .utf8),
                let firstLine = request.components(separatedBy: "\r\n").first,
                let path = firstLine.split(separator: " ").dropFirst().first,
                let components = URLComponents(string: "http://127.0.0.1\(path)"),
                let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                self.continuation?.resume(throwing: AppError.auth("Codice OAuth non ricevuto"))
                self.listener.cancel()
                return
            }

            let body = "<html><body><h2>Autenticazione completata</h2><p>Puoi tornare all'app FotoBeam.</p></body></html>"
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            self.continuation?.resume(returning: code)
            self.continuation = nil
            self.listener.cancel()
        }
    }
}
