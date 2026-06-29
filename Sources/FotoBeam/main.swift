import AppKit
import Foundation
import Network
import SwiftUI

let validExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "mp4", "mov", "avi"]
let reportFileName = "report_upload_swift.json"
let tokenFileName = "token_swift.json"
let googleScope = "https://www.googleapis.com/auth/photoslibrary.appendonly"

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

@main
struct FotoBeamApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Scegli cartella principale", systemImage: "folder")
                }

                Text(model.selectedFolder?.path ?? "Nessuna cartella selezionata")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }

            Table($model.albums) {
                TableColumn("✓") { $album in
                    Toggle("", isOn: $album.isSelected)
                        .labelsHidden()
                }
                .width(44)

                TableColumn("Cartella originale") { $album in
                    Text(album.originalName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 180, ideal: 260)

                TableColumn("Nome album Google") { $album in
                    TextField("Nome album", text: $album.albumName)
                        .textFieldStyle(.roundedBorder)
                }
                .width(min: 240, ideal: 360)

                TableColumn("File e date") { $album in
                    HStack {
                        Text("\(album.files.count) file")
                        Text(album.dateRange)
                            .foregroundStyle(.secondary)
                        if album.isCompleted {
                            Text("gia caricato")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .width(min: 220, ideal: 300)

                TableColumn("Dettagli") { $album in
                    Button {
                        model.showFilePreview(for: album)
                    } label: {
                        Label("File", systemImage: "list.bullet.rectangle")
                    }
                }
                .width(110)
            }
            .overlay {
                if model.albums.isEmpty {
                    ContentUnavailableView(
                        model.isScanning ? "Scansione in corso..." : "Nessun album da mostrare",
                        systemImage: model.isScanning ? "magnifyingglass" : "photo.on.rectangle",
                        description: Text("Seleziona una cartella principale con sottocartelle o file multimediali.")
                    )
                }
            }
            .sheet(item: $model.previewAlbum) { album in
                FilePreviewView(
                    album: album,
                    items: model.filePreviewItems(for: album)
                )
            }

            VStack(spacing: 8) {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text(model.status)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    Task { await model.uploadSelectedAlbums() }
                } label: {
                    Label("Avvia upload selezionati", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.albums.filter(\.isSelected).isEmpty || model.isWorking)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(model.logs.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .id(idx)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(height: 150)
                    .onChange(of: model.logs.count) { _, count in
                        if count > 0 {
                            proxy.scrollTo(count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(14)
    }
}

struct FilePreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let album: AlbumRow
    let items: [FilePreviewItem]

    var uploadCount: Int {
        items.filter(\.willUpload).count
    }

    var skippedCount: Int {
        items.count - uploadCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.albumName)
                        .font(.title3.bold())
                    Text(album.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(uploadCount) da caricare")
                        .foregroundStyle(.green)
                    Text("\(skippedCount) saltati")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            Table(items) {
                TableColumn("Stato") { item in
                    Label(
                        item.willUpload ? "Carica" : "Salta",
                        systemImage: item.willUpload ? "arrow.up.circle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(item.willUpload ? .green : .secondary)
                }
                .width(110)

                TableColumn("File") { item in
                    Text(item.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 220, ideal: 320)

                TableColumn("Motivo") { item in
                    Text(item.reason)
                        .foregroundStyle(.secondary)
                }
                .width(min: 180, ideal: 240)

                TableColumn("Percorso") { item in
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 260, ideal: 420)
            }

            HStack {
                Spacer()
                Button("Chiudi") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 860, minHeight: 520)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedFolder: URL?
    @Published var albums: [AlbumRow] = []
    @Published var logs: [String] = []
    @Published var status = ""
    @Published var progress = 0.0
    @Published var isScanning = false
    @Published var isWorking = false
    @Published var previewAlbum: AlbumRow?

    private let scanner = AlbumScanner()
    private var report = UploadReportStore.load()

    func showFilePreview(for album: AlbumRow) {
        previewAlbum = album
    }

    func filePreviewItems(for album: AlbumRow) -> [FilePreviewItem] {
        let title = album.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? album.originalName : album.albumName
        let albumReport = report.albums[title] ?? report.albums[album.originalName]

        return album.files.map { file in
            let status = albumReport?.files[file.path]?.status ?? "PENDING"
            let alreadyUploaded = status == "SUCCESS"
            let willUpload = album.isSelected && !album.isCompleted && !alreadyUploaded
            let reason: String

            if alreadyUploaded {
                reason = "Gia caricato nel report"
            } else if album.isCompleted {
                reason = "Album gia completato"
            } else if !album.isSelected {
                reason = "Album non selezionato"
            } else if status == "FAILED" || status == "FAILED_BATCH" {
                reason = "Riprova dopo errore precedente"
            } else if status == "TOKEN_GENERATED" {
                reason = "Token creato, da completare"
            } else {
                reason = "Pronto per upload"
            }

            return FilePreviewItem(
                fileName: file.lastPathComponent,
                path: file.path,
                status: status,
                willUpload: willUpload,
                reason: reason
            )
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scegli"

        if panel.runModal() == .OK, let folder = panel.url {
            selectedFolder = folder
            scan(folder: folder)
        }
    }

    private func scan(folder: URL) {
        isScanning = true
        isWorking = true
        status = "Scansione cartella..."
        log("Scansione cartella in corso...")

        Task.detached { [scanner, report] in
            let scanned = scanner.scan(folder: folder, report: report)
            await MainActor.run {
                self.albums = scanned
                self.isScanning = false
                self.isWorking = false
                self.status = scanned.isEmpty ? "Nessuna cartella con foto compatibili trovata." : "\(scanned.count) album trovati."
                self.log(self.status)
            }
        }
    }

    func uploadSelectedAlbums() async {
        let selected = albums.filter(\.isSelected)
        guard !selected.isEmpty else {
            log("Nessun album selezionato.")
            return
        }

        isWorking = true
        progress = 0

        do {
            log("Autenticazione con Google in corso...")
            let client = try await GooglePhotosClient()
            var completed = 0
            var failed = 0

            for (albumIndex, album) in selected.enumerated() {
                let title = album.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? album.originalName : album.albumName
                status = "Album \(albumIndex + 1)/\(selected.count): \(title)"
                log("Creazione album '\(title)' (\(album.files.count) file)...")

                do {
                    let albumId = try await client.createAlbum(title: title)
                    report.albums[title, default: AlbumReport(status: "IN_PROGRESS", albumId: albumId, files: [:])].albumId = albumId
                    report.albums[title]?.status = "IN_PROGRESS"
                    UploadReportStore.save(report)

                    var pending: [(file: URL, token: String)] = []
                    for (fileIndex, file) in album.files.enumerated() {
                        let fileKey = file.path
                        if report.albums[title]?.files[fileKey]?.status == "SUCCESS" {
                            continue
                        }

                        log("  Upload byte: \(file.lastPathComponent) (\(fileIndex + 1)/\(album.files.count))")
                        do {
                            let token = try await client.uploadBytes(file: file)
                            pending.append((file, token))
                            report.albums[title]?.files[fileKey] = FileReport(status: "TOKEN_GENERATED")
                        } catch {
                            report.albums[title]?.files[fileKey] = FileReport(status: "FAILED")
                            log("  Errore upload byte: \(file.lastPathComponent) - \(error.localizedDescription)")
                        }
                        UploadReportStore.save(report)
                        progress = (Double(albumIndex) + Double(fileIndex + 1) / Double(max(album.files.count, 1))) / Double(selected.count)
                    }

                    for chunkStart in stride(from: 0, to: pending.count, by: 50) {
                        let chunk = Array(pending[chunkStart..<min(chunkStart + 50, pending.count)])
                        log("  Salvataggio blocco \(chunkStart / 50 + 1) nell'album...")
                        let results = try await client.batchCreate(albumId: albumId, items: chunk)
                        for item in chunk {
                            let state = results[item.file.lastPathComponent] == false ? "FAILED_BATCH" : "SUCCESS"
                            report.albums[title]?.files[item.file.path] = FileReport(status: state)
                        }
                        UploadReportStore.save(report)
                    }

                    report.albums[title]?.status = "COMPLETED"
                    UploadReportStore.save(report)
                    completed += 1
                    log("Album '\(title)' completato.")
                } catch {
                    failed += 1
                    log("Errore album '\(title)': \(error.localizedDescription)")
                }
            }

            progress = 1
            status = "Upload completato. Successi: \(completed), falliti: \(failed)."
            log(status)
        } catch {
            log("Errore autenticazione/API: \(error.localizedDescription)")
            status = "Errore: \(error.localizedDescription)"
        }

        isWorking = false
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
    }
}

struct AlbumScanner {
    func scan(folder: URL, report: UploadReport) -> [AlbumRow] {
        guard let albumDirectories = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return albumDirectories
            .filter { isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { directory in
                let files = mediaFilesRecursively(in: directory)
                guard !files.isEmpty else {
                    return nil
                }

                let albumName = directory.lastPathComponent
                let completed = report.albums[albumName]?.status == "COMPLETED"

                return AlbumRow(
                    path: directory,
                    originalName: albumName,
                    albumName: albumName,
                    files: files,
                    dateRange: dateRange(files: files),
                    isSelected: !completed,
                    isCompleted: completed
                )
            }
    }

    private func mediaFilesRecursively(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            if validExtensions.contains(file.pathExtension.lowercased()) {
                files.append(file)
            }
        }

        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func dateRange(files: [URL]) -> String {
        let dates = files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        guard let minDate = dates.min(), let maxDate = dates.max() else {
            return "N/D"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        let start = formatter.string(from: minDate)
        let end = formatter.string(from: maxDate)
        return start == end ? start : "\(start) - \(end)"
    }
}

enum UploadReportStore {
    static var url: URL {
        projectRoot.appendingPathComponent(reportFileName)
    }

    static func load() -> UploadReport {
        guard let data = try? Data(contentsOf: url) else {
            return UploadReport()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(UploadReport.self, from: data)) ?? UploadReport()
    }

    static func save(_ report: UploadReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(report) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

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
            URLQueryItem(name: "scope", value: googleScope),
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
        guard let data = try? Data(contentsOf: projectRoot.appendingPathComponent(tokenFileName)) else {
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
            try? data.write(to: projectRoot.appendingPathComponent(tokenFileName), options: .atomic)
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
