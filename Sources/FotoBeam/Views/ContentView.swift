import SwiftUI

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

            Table(model.albums) {
                TableColumn("✓") { album in
                    Toggle("", isOn: Binding(
                        get: { model.currentAlbum(for: album).isSelected },
                        set: { model.setAlbumSelected(album, selected: $0) }
                    ))
                        .labelsHidden()
                }
                .width(44)

                TableColumn("Cartella originale") { album in
                    Text(album.originalName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 180, ideal: 260)

                TableColumn("Nome album Google") { album in
                    TextField("Nome album", text: Binding(
                        get: { model.currentAlbum(for: album).albumName },
                        set: { model.setAlbumName(album, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .width(min: 240, ideal: 360)

                TableColumn("File") { album in
                    HStack {
                        Text("\(album.files.count) file")
                        Text(album.folderSizeText)
                            .foregroundStyle(.secondary)
                        Text(album.dateRange)
                            .foregroundStyle(.secondary)
                        if let quality = model.qualityAnalysis(for: album), quality.flaggedCount > 0 {
                            Text("\(quality.flaggedCount) qualità")
                                .foregroundStyle(.orange)
                        }
                        if album.isCompleted {
                            Text("già caricato")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .width(min: 220, ideal: 300)

                TableColumn("Azioni") { album in
                    HStack(spacing: 8) {
                        Button {
                            model.showDateDetails(for: album)
                        } label: {
                            Label("Date e cartelle", systemImage: "calendar")
                        }

                        Button {
                            model.showFilePreview(for: album)
                        } label: {
                            Label("Revisiona", systemImage: "rectangle.stack.badge.person.crop")
                        }
                    }
                }
                .width(220)
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
                FileReviewView(album: album)
                    .environmentObject(model)
            }
            .sheet(item: $model.dateDetailAlbum) { album in
                AlbumDateDetailView(album: album)
                    .environmentObject(model)
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
