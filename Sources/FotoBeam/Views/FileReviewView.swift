import AppKit
import SwiftUI

struct FileReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let album: AlbumRow
    @State private var mode: ReviewMode = .duplicates
    @State private var thumbnailSize = 220.0

    private var items: [FilePreviewItem] {
        model.filePreviewItems(for: album)
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

    private var lowQualityFiles: [URL] {
        album.files.filter { file in
            let issues = quality.files[file.path]?.issues ?? []
            return issues.contains(.blurry)
                || issues.contains(.tooDark)
                || issues.contains(.tooBright)
                || issues.contains(.lowContrast)
                || issues.contains(.lowResolution)
                || issues.contains(.nearlyUniform)
                || issues.contains(.undecodable)
        }
    }

    private var reviewNeededFiles: [URL] {
        album.files.filter { file in
            !(quality.files[file.path]?.issues.isEmpty ?? true)
        }
    }

    private var duplicateGroups: [[URL]] {
        groups(from: quality.exactDuplicateGroups)
    }

    private var similarGroups: [[URL]] {
        groups(from: quality.similarGroups)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            qualitySummary(lowQualityCount: lowQualityFiles.count)
            actionBar
            modePicker

            ScrollView {
                let context = reviewContext
                switch mode {
                case .all:
                    fileGrid(files: album.files, context: context, emptyTitle: "Nessun file nell'album")
                case .duplicates:
                    groupList(
                        groups: duplicateGroups,
                        context: context,
                        title: "Gruppo duplicati",
                        emptyTitle: "Nessun duplicato esatto",
                        emptyDescription: "FotoBeam non ha trovato file identici in questo album."
                    )
                case .similar:
                    groupList(
                        groups: similarGroups,
                        context: context,
                        title: "Gruppo foto simili",
                        emptyTitle: "Nessuna foto simile",
                        emptyDescription: "FotoBeam non ha trovato scatti abbastanza simili da raggruppare."
                    )
                case .lowQuality:
                    fileGrid(
                        files: lowQualityFiles,
                        context: context,
                        emptyTitle: "Nessuna foto di bassa qualità",
                        emptyDescription: "Non ci sono immagini con problemi tecnici evidenti."
                    )
                case .reviewNeeded:
                    fileGrid(
                        files: reviewNeededFiles,
                        context: context,
                        emptyTitle: "Nessuna foto da valutare",
                        emptyDescription: "Non ci sono immagini con motivi di revisione aggiuntivi."
                    )
                }
            }
            .frame(minHeight: 420)

            HStack {
                Spacer()
                Button("Chiudi") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 1100, minHeight: 760)
    }

    private var header: some View {
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
    }

    private func qualitySummary(lowQualityCount: Int) -> some View {
        HStack(spacing: 10) {
            Label("\(quality.duplicateCount) duplicati", systemImage: "doc.on.doc")
                .foregroundStyle(quality.duplicateCount > 0 ? .orange : .secondary)
            Label("\(quality.similarCount) simili", systemImage: "rectangle.on.rectangle")
                .foregroundStyle(quality.similarCount > 0 ? .orange : .secondary)
            Label("\(lowQualityCount) qualità bassa", systemImage: "eye.slash")
                .foregroundStyle(lowQualityCount > 0 ? .orange : .secondary)
            Label("\(quality.reviewNeededCount) da valutare", systemImage: "exclamationmark.magnifyingglass")
                .foregroundStyle(quality.reviewNeededCount > 0 ? .orange : .secondary)
            Spacer()
            Label("Nessuna esclusione automatica", systemImage: "hand.raised")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var actionBar: some View {
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
                NSWorkspace.shared.open(album.path)
            } label: {
                Label("Apri cartella", systemImage: "folder")
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                Slider(value: $thumbnailSize, in: 150...360, step: 10)
                    .frame(width: 180)
                Image(systemName: "photo.fill")
                    .foregroundStyle(.secondary)
            }
            .help("Dimensione miniature")
        }
    }

    private var modePicker: some View {
        Picker("Vista", selection: $mode) {
            ForEach(ReviewMode.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private func groupList(groups: [[URL]], context: ReviewContext, title: String, emptyTitle: String, emptyDescription: String) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if groups.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "checkmark.seal",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, files in
                    ComparisonGroupView(
                        title: "\(title) \(index + 1)",
                        files: files,
                        items: context.itemsByPath,
                        quality: quality,
                        thumbnailSize: thumbnailSize,
                        isSelected: { model.isFileSelected($0) },
                        setSelected: { model.setFile($0, selected: $1) },
                        selectAll: { model.setFiles(files, selected: true) },
                        deselectAll: { model.setFiles(files, selected: false) }
                    )
                }
            }
        }
        .padding(2)
    }

    private func fileGrid(files: [URL], context: ReviewContext, emptyTitle: String, emptyDescription: String = "Non ci sono elementi da mostrare in questa vista.") -> some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "checkmark.seal",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: 12)], spacing: 12) {
                    ForEach(files, id: \.path) { file in
                        ReviewFileCard(
                            file: file,
                            item: context.itemsByPath[file.path],
                            quality: quality.files[file.path],
                            thumbnailSize: thumbnailSize,
                            isSelected: model.isFileSelected(file),
                            onSelectionChange: { selected in
                                model.setFile(file, selected: selected)
                            }
                        )
                    }
                }
                .padding(2)
            }
        }
    }

    private var reviewContext: ReviewContext {
        ReviewContext(items: items)
    }

    private func groups(from paths: [[String]]) -> [[URL]] {
        let filesByPath = Dictionary(uniqueKeysWithValues: album.files.map { ($0.path, $0) })
        let order = Dictionary(uniqueKeysWithValues: album.files.enumerated().map { ($0.element.path, $0.offset) })

        return paths
            .map { group in
                group.compactMap { filesByPath[$0] }
                    .sorted { (order[$0.path] ?? Int.max) < (order[$1.path] ?? Int.max) }
            }
            .filter { $0.count > 1 }
    }
}

private struct ReviewContext {
    let itemsByPath: [String: FilePreviewItem]

    init(items: [FilePreviewItem]) {
        itemsByPath = Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0) })
    }
}

struct ComparisonGroupView: View {
    let title: String
    let files: [URL]
    let items: [String: FilePreviewItem]
    let quality: QualityAnalysis
    let thumbnailSize: Double
    let isSelected: (URL) -> Bool
    let setSelected: (URL, Bool) -> Void
    let selectAll: () -> Void
    let deselectAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("\(files.count) file affiancati per confronto")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectAll()
                } label: {
                    Label("Carica gruppo", systemImage: "checkmark.circle")
                }
                Button {
                    deselectAll()
                } label: {
                    Label("Salta gruppo", systemImage: "xmark.circle")
                }
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(files, id: \.path) { file in
                        ReviewFileCard(
                            file: file,
                            item: items[file.path],
                            quality: quality.files[file.path],
                            thumbnailSize: thumbnailSize,
                            isSelected: isSelected(file),
                            onSelectionChange: { selected in
                                setSelected(file, selected)
                            }
                        )
                        .frame(width: thumbnailSize)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ReviewFileCard: View {
    let file: URL
    let item: FilePreviewItem?
    let quality: FileQualityInfo?
    let thumbnailSize: Double
    let isSelected: Bool
    let onSelectionChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(file: file, pixelSize: thumbnailPixelSize)
                    .frame(height: thumbnailHeight)
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

            FlowTags(flags: quality?.flags ?? [])
            IssueTags(issues: quality?.issues ?? [])
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var thumbnailHeight: Double {
        max(110, thumbnailSize * 0.68)
    }

    private var thumbnailPixelSize: Int {
        Int((thumbnailSize * 1.5).rounded(.up))
    }

    private var borderColor: Color {
        if !(quality?.flags.isEmpty ?? true) {
            return .orange
        }
        return .secondary.opacity(0.25)
    }
}

struct IssueTags: View {
    let issues: [QualityIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues, id: \.rawValue) { issue in
                    Label(issue.rawValue, systemImage: icon(for: issue))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
    }

    private func icon(for issue: QualityIssue) -> String {
        switch issue {
        case .blurry:
            return "eye.slash"
        case .tooDark:
            return "moon"
        case .tooBright:
            return "sun.max"
        case .lowContrast, .nearlyUniform:
            return "circle.lefthalf.filled"
        case .lowResolution:
            return "arrow.down.right.and.arrow.up.left"
        case .undecodable:
            return "exclamationmark.triangle"
        case .crowdedSimilarGroup:
            return "rectangle.stack"
        }
    }
}

struct ThumbnailView: View {
    let file: URL
    let pixelSize: Int

    @State private var image: NSImage?
    @State private var didFailToLoad = false

    var body: some View {
        Group {
            if let image {
                imageView(image)
            } else {
                placeholder
            }
        }
        .task(id: cacheKey) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: placeholderIcon)
                .font(.largeTitle)
            Text(file.pathExtension.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isVideo && !didFailToLoad {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func imageView(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
    }

    private func loadImage() async {
        guard !isVideo else {
            didFailToLoad = true
            return
        }

        if let cached = ThumbnailLoader.shared.cachedImage(for: file, pixelSize: normalizedPixelSize) {
            image = cached
            didFailToLoad = false
            return
        }

        image = nil
        didFailToLoad = false
        if let loaded = await ThumbnailLoader.shared.image(for: file, pixelSize: normalizedPixelSize) {
            image = loaded
        } else {
            didFailToLoad = true
        }
    }

    private var normalizedPixelSize: Int {
        max(160, min(640, Int((Double(pixelSize) / 80.0).rounded(.up) * 80)))
    }

    private var cacheKey: String {
        "\(file.path)|\(normalizedPixelSize)"
    }

    private var placeholderIcon: String {
        if isVideo {
            return "video"
        }
        return didFailToLoad ? "doc" : "photo"
    }

    private var isVideo: Bool {
        ["mp4", "mov", "avi"].contains(file.pathExtension.lowercased())
    }
}

struct FlowTags: View {
    let flags: [QualityFlag]

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
        return flag.rawValue
    }

    private func icon(for flag: QualityFlag) -> String {
        switch flag {
        case .exactDuplicate:
            return "doc.on.doc"
        case .similar:
            return "rectangle.on.rectangle"
        }
    }
}
