import AppKit
import SwiftUI

struct AlbumDateDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let album: AlbumRow

    @State private var selectedPaths: Set<String> = []
    @State private var filter: DateDetailFilter = .all
    @State private var sortAscending = true
    @State private var destinationFolderName = ""
    @State private var overrideDate = Date()
    @State private var message = ""
    @State private var errorMessage = ""

    private var currentAlbum: AlbumRow {
        model.currentAlbum(for: album)
    }

    private var analysis: AlbumDateAnalysis {
        model.albumDateAnalysis(for: currentAlbum)
    }

    private var visibleItems: [AlbumDateItem] {
        let filtered = analysis.items.filter { item in
            switch filter {
            case .all:
                return true
            case .suspicious:
                return !item.issues.isEmpty
            case .differentYear:
                return item.issues.contains(.differentYear)
            case .weakDate:
                return item.issues.contains(.weakDate)
            case .unavailable:
                return item.issues.contains(.unavailable)
            }
        }

        if sortAscending {
            return filtered
        }
        return filtered.reversed()
    }

    private var selectedFiles: [URL] {
        currentAlbum.files.filter { selectedPaths.contains($0.path) }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            summaryBar
            controls
            fileList
            metadataEditBar
            moveBar
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 680)
        .onChange(of: currentAlbum.files.map(\.path)) { _, paths in
            selectedPaths = selectedPaths.intersection(Set(paths))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentAlbum.albumName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(currentAlbum.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Chiudi", systemImage: "xmark")
            }
        }
    }

    private var summaryBar: some View {
        let summary = analysis.summary
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            DateSummaryPill(title: "File", value: "\(summary.fileCount)", icon: "photo.on.rectangle")
            DateSummaryPill(title: "Intervallo", value: summary.dateRange, icon: "calendar")
            DateSummaryPill(title: "Anni", value: yearsText(summary.years), icon: "number")
            DateSummaryPill(title: "Anno prevalente", value: summary.majorityYear.map(String.init) ?? "N/D", icon: "target")
            DateSummaryPill(title: "Da controllare", value: "\(summary.suspiciousCount)", icon: "exclamationmark.triangle")
            DateSummaryPill(title: "Solo data file", value: "\(summary.weakDateCount)", icon: "clock.badge.questionmark")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Filtro", selection: $filter) {
                ForEach(DateDetailFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Button {
                sortAscending.toggle()
            } label: {
                Label(sortAscending ? "Crescente" : "Decrescente", systemImage: sortAscending ? "arrow.up" : "arrow.down")
            }

            Spacer()

            Button {
                selectedPaths = Set(visibleItems.map { $0.file.path })
            } label: {
                Label("Seleziona visibili", systemImage: "checkmark.circle")
            }

            Button {
                selectedPaths.removeAll()
            } label: {
                Label("Deseleziona", systemImage: "circle")
            }
            .disabled(selectedPaths.isEmpty)
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(visibleItems) { item in
                    AlbumDateRow(
                        item: item,
                        isSelected: selectedPaths.contains(item.file.path),
                        toggleSelection: {
                            toggleSelection(item.file)
                        }
                    )
                }
            }
            .padding(4)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var moveBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(selectedFiles.count) selezionati")
                    .foregroundStyle(.secondary)

                TextField("Nuova cartella", text: $destinationFolderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)

                Button {
                    moveToNamedFolder()
                } label: {
                    Label("Crea e sposta", systemImage: "folder.badge.plus")
                }
                .disabled(selectedFiles.isEmpty || destinationFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    chooseExistingFolderAndMove()
                } label: {
                    Label("Scegli cartella", systemImage: "folder")
                }
                .disabled(selectedFiles.isEmpty)

                Spacer()
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var metadataEditBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(selectedFiles.count) selezionati")
                    .foregroundStyle(.secondary)

                DatePicker("Data corretta", selection: $overrideDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()

                Button {
                    applyDateOverride()
                } label: {
                    Label("Applica data", systemImage: "calendar.badge.clock")
                }
                .disabled(selectedFiles.isEmpty)
                .help("Salva una data manuale per FotoBeam e aggiorna creazione/modifica file su macOS.")

                Spacer()

                Text("Usata per rinomina e upload")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleSelection(_ file: URL) {
        if selectedPaths.contains(file.path) {
            selectedPaths.remove(file.path)
        } else {
            selectedPaths.insert(file.path)
        }
    }

    private func moveToNamedFolder() {
        let name = sanitizedFolderName(destinationFolderName)
        guard !name.isEmpty, let root = model.selectedFolder else {
            return
        }
        let destination = root.appendingPathComponent(name, isDirectory: true)
        moveSelectedFiles(to: destination)
    }

    private func chooseExistingFolderAndMove() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Sposta"
        panel.directoryURL = model.selectedFolder ?? currentAlbum.path.deletingLastPathComponent()

        if panel.runModal() == .OK, let destination = panel.url {
            moveSelectedFiles(to: destination)
        }
    }

    private func moveSelectedFiles(to destination: URL) {
        do {
            let count = try model.moveFiles(selectedFiles, from: currentAlbum, to: destination)
            if count > 0 {
                selectedPaths.removeAll()
                destinationFolderName = ""
            }
            errorMessage = ""
            message = count == 0 ? "Nessun file spostato." : "\(count) file spostati in \(destination.lastPathComponent)."
        } catch {
            message = ""
            errorMessage = "Spostamento non riuscito: \(error.localizedDescription)"
        }
    }

    private func applyDateOverride() {
        do {
            let count = try model.applyDateOverride(overrideDate, to: selectedFiles, in: currentAlbum)
            errorMessage = ""
            message = count == 0 ? "Nessuna data applicata." : "Data manuale applicata a \(count) file."
        } catch {
            message = ""
            errorMessage = "Modifica data non riuscita: \(error.localizedDescription)"
        }
    }

    private func sanitizedFolderName(_ rawName: String) -> String {
        rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }

    private func yearsText(_ years: [Int]) -> String {
        if years.isEmpty {
            return "N/D"
        }
        return years.map(String.init).joined(separator: ", ")
    }
}

enum DateDetailFilter: String, CaseIterable, Identifiable {
    case all = "Tutto"
    case suspicious = "Da controllare"
    case differentYear = "Anno diverso"
    case weakDate = "Solo data file"
    case unavailable = "Senza data"

    var id: String { rawValue }
}

struct DateSummaryPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AlbumDateRow: View {
    let item: AlbumDateItem
    let isSelected: Bool
    let toggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggleSelection() }))
                .labelsHidden()

            ThumbnailView(file: item.file, pixelSize: 88)
                .frame(width: 88, height: 66)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.file.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.file.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 260, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(dateText(item.date))
                    .font(.callout.monospacedDigit())
                Text(item.dateSource.rawValue)
                    .font(.caption)
                    .foregroundStyle(dateSourceColor(item.dateSource))
            }
            .frame(width: 190, alignment: .leading)

            Text(item.year.map(String.init) ?? "N/D")
                .font(.callout.monospacedDigit())
                .frame(width: 70, alignment: .leading)

            IssueChips(issues: item.issues)

            Spacer()
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection()
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return "N/D"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func dateSourceColor(_ source: RenameDateSource) -> Color {
        switch source {
        case .manualOverride:
            return .green
        case .exifDateTimeOriginal, .imageMetadata, .fileName:
            return .secondary
        case .fileCreationDate, .fileModificationDate:
            return .orange
        case .unavailable:
            return .red
        }
    }
}

struct IssueChips: View {
    let issues: [AlbumDateIssue]

    var body: some View {
        HStack(spacing: 6) {
            if issues.isEmpty {
                Text("OK")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(issues, id: \.rawValue) { issue in
                    Label(issue.rawValue, systemImage: icon(for: issue))
                        .font(.caption)
                        .foregroundStyle(color(for: issue))
                        .lineLimit(1)
                }
            }
        }
    }

    private func icon(for issue: AlbumDateIssue) -> String {
        switch issue {
        case .differentYear:
            return "calendar.badge.exclamationmark"
        case .weakDate:
            return "clock.badge.questionmark"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }

    private func color(for issue: AlbumDateIssue) -> Color {
        switch issue {
        case .differentYear, .weakDate:
            return .orange
        case .unavailable:
            return .red
        }
    }
}
