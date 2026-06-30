import AppKit
import Foundation
import SwiftUI

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
    @Published var fileSelections: [String: Bool] = [:]
    @Published var qualityAnalyses: [UUID: QualityAnalysis] = [:]

    private let scanner = AlbumScanner()
    private let qualityAnalyzer = QualityAnalyzer()
    private var report = UploadReportStore.load()

    func showFilePreview(for album: AlbumRow) {
        previewAlbum = album
    }

    func qualityAnalysis(for album: AlbumRow) -> QualityAnalysis? {
        qualityAnalyses[album.id]
    }

    func isFileSelected(_ file: URL) -> Bool {
        fileSelections[file.path] ?? true
    }

    func setFile(_ file: URL, selected: Bool) {
        fileSelections[file.path] = selected
    }

    func setFiles(_ files: [URL], selected: Bool) {
        for file in files {
            fileSelections[file.path] = selected
        }
    }

    func selectedUploadFiles(for album: AlbumRow) -> [URL] {
        let title = album.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? album.originalName : album.albumName
        let albumReport = report.albums[title] ?? report.albums[album.originalName]
        return album.files.filter { file in
            isFileSelected(file) && albumReport?.files[file.path]?.status != "SUCCESS"
        }
    }

    func filteredFiles(for album: AlbumRow, filter: ReviewFilter) -> [URL] {
        let analysis = qualityAnalyses[album.id]
        return album.files.filter { file in
            let info = analysis?.files[file.path]
            switch filter {
            case .all:
                return true
            case .flagged:
                return !(info?.flags.isEmpty ?? true)
            case .duplicates:
                return info?.exactDuplicateGroup != nil
            case .similar:
                return info?.similarGroup != nil
            case .blurry:
                if let score = info?.blurScore {
                    return score < AppConfig.blurScoreThreshold
                }
                return false
            }
        }
    }

    func filePreviewItems(for album: AlbumRow) -> [FilePreviewItem] {
        let title = album.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? album.originalName : album.albumName
        let albumReport = report.albums[title] ?? report.albums[album.originalName]
        let analysis = qualityAnalyses[album.id]

        return album.files.map { file in
            let status = albumReport?.files[file.path]?.status ?? "PENDING"
            let alreadyUploaded = status == "SUCCESS"
            let manuallySelected = isFileSelected(file)
            let willUpload = album.isSelected && !album.isCompleted && !alreadyUploaded && manuallySelected
            let reason: String

            if alreadyUploaded {
                reason = "Già caricato nel report"
            } else if album.isCompleted {
                reason = "Album già completato"
            } else if !album.isSelected {
                reason = "Album non selezionato"
            } else if !manuallySelected {
                reason = "Escluso manualmente"
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
                reason: reason,
                isManuallySelected: manuallySelected,
                qualitySummary: analysis?.files[file.path]?.summary ?? "OK"
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

        Task.detached { [scanner, qualityAnalyzer, report] in
            let scanned = scanner.scan(folder: folder, report: report)
            var analyses: [UUID: QualityAnalysis] = [:]
            for album in scanned {
                analyses[album.id] = qualityAnalyzer.analyze(files: album.files)
            }
            await MainActor.run {
                self.albums = scanned
                self.fileSelections = Dictionary(uniqueKeysWithValues: scanned.flatMap { album in
                    album.files.map { ($0.path, true) }
                })
                self.qualityAnalyses = analyses
                self.isScanning = false
                self.isWorking = false
                self.status = scanned.isEmpty ? "Nessuna cartella con foto compatibili trovata." : "\(scanned.count) album trovati."
                self.log(self.status)
                let flagged = analyses.values.reduce(0) { $0 + $1.flaggedCount }
                if flagged > 0 {
                    self.log("\(flagged) file segnalati per revisione. Nessun file è stato escluso automaticamente.")
                }
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
                let filesToUpload = selectedUploadFiles(for: album)
                guard !filesToUpload.isEmpty else {
                    log("Album '\(title)' saltato: nessun file selezionato per l'upload.")
                    continue
                }
                status = "Album \(albumIndex + 1)/\(selected.count): \(title)"
                log("Creazione album '\(title)' (\(filesToUpload.count) file selezionati su \(album.files.count))...")

                do {
                    let albumId = try await client.createAlbum(title: title)
                    report.albums[title, default: AlbumReport(status: "IN_PROGRESS", albumId: albumId, files: [:])].albumId = albumId
                    report.albums[title]?.status = "IN_PROGRESS"
                    UploadReportStore.save(report)

                    var pending: [(file: URL, token: String)] = []
                    for (fileIndex, file) in filesToUpload.enumerated() {
                        let fileKey = file.path
                        if report.albums[title]?.files[fileKey]?.status == "SUCCESS" {
                            continue
                        }

                        log("  Upload byte: \(file.lastPathComponent) (\(fileIndex + 1)/\(filesToUpload.count))")
                        do {
                            let token = try await client.uploadBytes(file: file)
                            pending.append((file, token))
                            report.albums[title]?.files[fileKey] = FileReport(status: "TOKEN_GENERATED")
                        } catch {
                            report.albums[title]?.files[fileKey] = FileReport(status: "FAILED")
                            log("  Errore upload byte: \(file.lastPathComponent) - \(error.localizedDescription)")
                        }
                        UploadReportStore.save(report)
                        progress = (Double(albumIndex) + Double(fileIndex + 1) / Double(max(filesToUpload.count, 1))) / Double(selected.count)
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

                    let remainingUnuploaded = album.files.contains { file in
                        report.albums[title]?.files[file.path]?.status != "SUCCESS"
                    }
                    report.albums[title]?.status = remainingUnuploaded ? "PARTIAL_SELECTION" : "COMPLETED"
                    UploadReportStore.save(report)
                    completed += 1
                    if remainingUnuploaded {
                        log("Album '\(title)' completato per i file selezionati. Alcuni file restano esclusi o non caricati.")
                    } else {
                        log("Album '\(title)' completato.")
                    }
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
