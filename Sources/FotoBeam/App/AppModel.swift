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
    @Published var dateDetailAlbum: AlbumRow?
    @Published var showingGoogleAlbums = false
    @Published var googleAlbums: [GooglePhotoAlbum] = []
    @Published var isLoadingGoogleAlbums = false
    @Published var hasLoadedGoogleAlbums = false
    @Published var fileSelections: [String: Bool] = [:]
    @Published var qualityAnalyses: [UUID: QualityAnalysis] = [:]
    @Published var renameBeforeUpload: [UUID: Bool] = [:]

    private let scanner = AlbumScanner()
    private let qualityAnalyzer = QualityAnalyzer()
    private let renamePlanner = RenamePlanner()
    private let dateAnalyzer = AlbumDateAnalyzer()
    private let fileMover = AlbumFileMover()
    private let dateReader = MediaDateReader()
    private let folderSizeCalculator = FolderSizeCalculator()
    private var report = UploadReportStore.load()

    func showFilePreview(for album: AlbumRow) {
        previewAlbum = album
    }

    func showDateDetails(for album: AlbumRow) {
        dateDetailAlbum = album
    }

    func googleAlbumExists(for album: AlbumRow) -> Bool {
        let title = album.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? album.originalName : album.albumName
        return googleAlbumTitles.contains(title.normalizedAlbumTitle)
    }

    func googleAlbumStatus(for album: AlbumRow) -> GoogleAlbumStatus {
        guard hasLoadedGoogleAlbums else {
            return .notChecked
        }
        return googleAlbumExists(for: album) ? .present : .missing
    }

    func setAlbumSelected(_ album: AlbumRow, selected: Bool) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else {
            return
        }
        albums[index].isSelected = selected
    }

    func setAlbumName(_ album: AlbumRow, name: String) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else {
            return
        }
        albums[index].albumName = name
        if let previewAlbum, previewAlbum.id == album.id {
            self.previewAlbum = albums[index]
        }
    }

    func qualityAnalysis(for album: AlbumRow) -> QualityAnalysis? {
        qualityAnalyses[album.id]
    }

    func albumDateAnalysis(for album: AlbumRow) -> AlbumDateAnalysis {
        dateAnalyzer.analyze(files: currentAlbum(for: album).files)
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

    func shouldRenameBeforeUpload(_ album: AlbumRow) -> Bool {
        renameBeforeUpload[album.id] ?? false
    }

    func setRenameBeforeUpload(_ album: AlbumRow, enabled: Bool) {
        renameBeforeUpload[album.id] = enabled
    }

    func selectedUploadFiles(for album: AlbumRow) -> [URL] {
        let title = album.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? album.originalName : album.albumName
        let albumReport = report.albums[title] ?? report.albums[album.originalName]
        return album.files.filter { file in
            isFileSelected(file) && albumReport?.files[file.path]?.status != "SUCCESS"
        }
    }

    func currentAlbum(for album: AlbumRow) -> AlbumRow {
        albums.first { $0.id == album.id } ?? album
    }

    func renamePlan(for album: AlbumRow) -> [RenamePlanItem] {
        renamePlanner.makePlan(files: selectedUploadFiles(for: currentAlbum(for: album)))
    }

    func applyRenamePlan(_ plan: [RenamePlanItem], to album: AlbumRow) throws {
        let history = try renamePlanner.apply(plan: plan)
        guard !history.isEmpty else {
            log("Nessun file rinominato.")
            return
        }

        let pathMap = Dictionary(uniqueKeysWithValues: history.map { ($0.oldPath, $0.newPath) })
        if let albumIndex = albums.firstIndex(where: { $0.id == album.id }) {
            albums[albumIndex].files = albums[albumIndex].files.map { file in
                if let newPath = pathMap[file.path] {
                    return URL(fileURLWithPath: newPath)
                }
                return file
            }
            albums[albumIndex].dateRange = dateReader.fileDateRange(files: albums[albumIndex].files)
            albums[albumIndex].folderSizeBytes = folderSizeCalculator.sizeBytes(for: albums[albumIndex].path)
            qualityAnalyses[album.id] = qualityAnalyzer.analyze(files: albums[albumIndex].files)
        }

        for item in history {
            let selected = fileSelections[item.oldPath] ?? true
            fileSelections.removeValue(forKey: item.oldPath)
            fileSelections[item.newPath] = selected
        }

        if let previewAlbum, previewAlbum.id == album.id {
            self.previewAlbum = albums.first { $0.id == album.id }
        }

        log("\(history.count) file rinominati. Storico salvato in \(AppConfig.renameHistoryFileName).")
    }

    func moveFiles(_ files: [URL], from album: AlbumRow, to directory: URL) throws -> Int {
        let current = currentAlbum(for: album)
        let sourcePaths = Set(files.map(\.path))
        guard !sourcePaths.isEmpty else {
            return 0
        }

        let history = try fileMover.move(files: files, to: directory)
        guard !history.isEmpty else {
            log("Nessun file spostato.")
            return 0
        }

        let movedFiles = history.map { URL(fileURLWithPath: $0.newPath) }

        if let sourceIndex = albums.firstIndex(where: { $0.id == current.id }) {
            albums[sourceIndex].files.removeAll { sourcePaths.contains($0.path) }
            albums[sourceIndex].dateRange = dateReader.fileDateRange(files: albums[sourceIndex].files)
            albums[sourceIndex].folderSizeBytes = folderSizeCalculator.sizeBytes(for: albums[sourceIndex].path)
            qualityAnalyses[current.id] = qualityAnalyzer.analyze(files: albums[sourceIndex].files)
        }

        if let destinationIndex = albums.firstIndex(where: { sameFileURL($0.path, directory) }) {
            albums[destinationIndex].files.append(contentsOf: movedFiles)
            albums[destinationIndex].files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            albums[destinationIndex].dateRange = dateReader.fileDateRange(files: albums[destinationIndex].files)
            albums[destinationIndex].folderSizeBytes = folderSizeCalculator.sizeBytes(for: albums[destinationIndex].path)
            qualityAnalyses[albums[destinationIndex].id] = qualityAnalyzer.analyze(files: albums[destinationIndex].files)
        } else if !sameFileURL(directory, selectedFolder ?? directory) {
            let newAlbum = AlbumRow(
                path: directory,
                originalName: directory.lastPathComponent,
                albumName: directory.lastPathComponent,
                files: movedFiles.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
                dateRange: dateReader.fileDateRange(files: movedFiles),
                folderSizeBytes: folderSizeCalculator.sizeBytes(for: directory)
            )
            albums.append(newAlbum)
            albums.sort { $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending }
            qualityAnalyses[newAlbum.id] = qualityAnalyzer.analyze(files: newAlbum.files)
            renameBeforeUpload[newAlbum.id] = false
        }

        for item in history {
            let selected = fileSelections[item.oldPath] ?? true
            fileSelections.removeValue(forKey: item.oldPath)
            fileSelections[item.newPath] = selected
        }

        if let previewAlbum, previewAlbum.id == current.id {
            self.previewAlbum = albums.first { $0.id == current.id }
        }
        if let dateDetailAlbum, dateDetailAlbum.id == current.id {
            self.dateDetailAlbum = albums.first { $0.id == current.id }
        }

        log("\(history.count) file spostati in '\(directory.lastPathComponent)'. Storico salvato in \(AppConfig.moveHistoryFileName).")
        return history.count
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
                self.renameBeforeUpload = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, false) })
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

            for (albumIndex, selectedAlbum) in selected.enumerated() {
                var album = currentAlbum(for: selectedAlbum)
                let title = album.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? album.originalName : album.albumName
                if shouldRenameBeforeUpload(album) {
                    let plan = renamePlan(for: album)
                    let applicable = plan.filter { $0.status == .ready }
                    if !applicable.isEmpty {
                        log("Rinomina pre-upload per album '\(title)' (\(applicable.count) file)...")
                        try applyRenamePlan(plan, to: album)
                        album = currentAlbum(for: album)
                    } else {
                        log("Rinomina pre-upload per album '\(title)': nessun file da rinominare.")
                    }
                }
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

    func loadGoogleAlbums() async {
        guard !isLoadingGoogleAlbums else {
            return
        }

        isLoadingGoogleAlbums = true
        status = "Lettura album Google Photos..."
        log("Lettura titoli album Google Photos creati da FotoBeam...")

        do {
            let client = try await GooglePhotosClient()
            googleAlbums = try await client.listAlbums()
            hasLoadedGoogleAlbums = true
            showingGoogleAlbums = true
            status = "\(googleAlbums.count) album Google Photos trovati."
            log(status)
            if googleAlbums.isEmpty {
                log("Google restituisce solo album creati da questa app con lo scope readonly.appcreateddata.")
            }
        } catch {
            status = "Errore lettura album Google Photos"
            log("Errore lettura album Google Photos: \(error.localizedDescription)")
        }

        isLoadingGoogleAlbums = false
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
    }

    private func sameFileURL(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.path == second.standardizedFileURL.path
    }

    private var googleAlbumTitles: Set<String> {
        Set(googleAlbums.map { $0.title.normalizedAlbumTitle })
    }
}

private extension String {
    var normalizedAlbumTitle: String {
        trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
