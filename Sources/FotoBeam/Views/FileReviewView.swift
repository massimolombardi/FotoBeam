import AppKit
import SwiftUI

struct FileReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let album: AlbumRow
    @State private var filter: ReviewFilter = .all

    private var items: [FilePreviewItem] {
        model.filePreviewItems(for: album)
    }

    private var visibleFiles: [URL] {
        model.filteredFiles(for: album, filter: filter)
    }

    private var uploadCount: Int {
        items.filter(\.willUpload).count
    }

    private var skippedCount: Int {
        items.count - uploadCount
    }

    private var quality: QualityAnalysis {
        model.qualityAnalysis(for: album) ?? QualityAnalysis()
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

            HStack(spacing: 8) {
                Label("\(quality.duplicateCount) duplicati", systemImage: "doc.on.doc")
                    .foregroundStyle(quality.duplicateCount > 0 ? .orange : .secondary)
                Label("\(quality.similarCount) simili", systemImage: "rectangle.on.rectangle")
                    .foregroundStyle(quality.similarCount > 0 ? .orange : .secondary)
                Label("\(quality.blurryCount) sfocate", systemImage: "eye.slash")
                    .foregroundStyle(quality.blurryCount > 0 ? .orange : .secondary)
                Spacer()
                Picker("Filtro", selection: $filter) {
                    ForEach(ReviewFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 520)
            }
            .font(.subheadline)

            HStack(spacing: 8) {
                Button {
                    model.setFiles(album.files, selected: true)
                } label: {
                    Label("Carica tutte", systemImage: "checkmark.circle")
                }

                Button {
                    model.setFiles(album.files, selected: false)
                } label: {
                    Label("Non caricare nessuna", systemImage: "xmark.circle")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([])
                    NSWorkspace.shared.open(album.path)
                } label: {
                    Label("Apri cartella", systemImage: "folder")
                }

                Spacer()

                Text("Gli avvisi non cambiano le spunte: decidi tu cosa caricare.")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    ForEach(visibleFiles, id: \.path) { file in
                        ReviewFileCard(
                            file: file,
                            item: items.first(where: { $0.path == file.path }),
                            quality: quality.files[file.path],
                            isSelected: model.isFileSelected(file),
                            onSelectionChange: { selected in
                                model.setFile(file, selected: selected)
                            }
                        )
                    }
                }
                .padding(2)
            }
            .frame(minHeight: 360)

            if filter != .all && visibleFiles.isEmpty {
                ContentUnavailableView(
                    "Nessun file in questo filtro",
                    systemImage: "checkmark.seal",
                    description: Text("Puoi tornare a Tutti per vedere l'intero album.")
                )
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
        .frame(minWidth: 980, minHeight: 700)
    }
}

struct ReviewFileCard: View {
    let file: URL
    let item: FilePreviewItem?
    let quality: FileQualityInfo?
    let isSelected: Bool
    let onSelectionChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(file: file)
                    .frame(height: 126)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )

                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { onSelectionChange($0) }
                ))
                .labelsHidden()
                .padding(8)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)
            }

            Text(file.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                Label(isSelected ? "Carica" : "Salta", systemImage: isSelected ? "arrow.up.circle.fill" : "minus.circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
                Text(item?.reason ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)

            FlowTags(flags: quality?.flags ?? [], blurScore: quality?.blurScore)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var borderColor: Color {
        if !(quality?.flags.isEmpty ?? true) {
            return .orange
        }
        return .secondary.opacity(0.25)
    }
}

struct ThumbnailView: View {
    let file: URL

    var body: some View {
        if let image = NSImage(contentsOf: file), image.isValid {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            VStack(spacing: 8) {
                Image(systemName: isVideo ? "video" : "doc")
                    .font(.largeTitle)
                Text(file.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isVideo: Bool {
        ["mp4", "mov", "avi"].contains(file.pathExtension.lowercased())
    }
}

struct FlowTags: View {
    let flags: [QualityFlag]
    let blurScore: Double?

    var body: some View {
        HStack(spacing: 6) {
            if flags.isEmpty {
                Text("OK")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(flags, id: \.rawValue) { flag in
                    Label(label(for: flag), systemImage: icon(for: flag))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
    }

    private func label(for flag: QualityFlag) -> String {
        if flag == .blurry, let blurScore {
            return "\(flag.rawValue) \(String(format: "%.1f", blurScore))"
        }
        return flag.rawValue
    }

    private func icon(for flag: QualityFlag) -> String {
        switch flag {
        case .exactDuplicate:
            return "doc.on.doc"
        case .similar:
            return "rectangle.on.rectangle"
        case .blurry:
            return "eye.slash"
        }
    }
}
