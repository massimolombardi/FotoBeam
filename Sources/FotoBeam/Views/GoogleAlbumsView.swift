import SwiftUI

struct GoogleAlbumsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredAlbums: [GooglePhotoAlbum] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return model.googleAlbums
        }

        return model.googleAlbums.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Album Google Photos")
                        .font(.title2.weight(.semibold))
                    Text("\(filteredAlbums.count) di \(model.googleAlbums.count) album creati da FotoBeam")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Chiudi") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            TextField("Cerca titolo album", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Table(filteredAlbums) {
                TableColumn("Titolo") { album in
                    Text(album.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 280, ideal: 420)

                TableColumn("Elementi") { album in
                    if let count = album.mediaItemsCount {
                        Text("\(count)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("-")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(90)

                TableColumn("ID") { album in
                    Text(album.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 180, ideal: 260)
            }
            .overlay {
                if filteredAlbums.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Nessun album trovato" : "Nessun risultato",
                        systemImage: "photo.stack",
                        description: Text("Google Photos espone qui solo gli album creati da questa app.")
                    )
                }
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 500)
    }
}
