import SwiftUI

/// Pick a different cover from the book's editions online, English ones first.
struct CoverChooserView: View {
    let title: String
    let author: String?
    let isbn: String?
    let onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options: [BookCandidate]?
    @State private var downloading: String?
    @State private var failed = false

    private let lookup = BookLookup()
    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let options, !options.isEmpty {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(options) { option in
                            Button { choose(option) } label: { tile(option) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .paperScreen()
            .navigationTitle("Choose a Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if options == nil {
                    ProgressView("Finding covers…")
                } else if options?.isEmpty == true {
                    ContentUnavailableView(
                        "No other covers found",
                        systemImage: "photo.on.rectangle",
                        description: Text("You can scan the cover or pick a photo instead.")
                    )
                }
            }
            .alert("Couldn't download that cover", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
            .task {
                options = await lookup.coverOptions(title: title, author: author, isbn: isbn)
            }
        }
    }

    private func tile(_ option: BookCandidate) -> some View {
        VStack(spacing: 6) {
            AsyncImage(url: option.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 96, height: 144)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if downloading == option.id {
                    ProgressView().padding(8).background(.regularMaterial, in: Circle())
                }
            }
            Text(caption(option))
                .font(.inter(.caption2))
                .foregroundStyle(option.isEnglish ? .secondary : .tertiary)
                .lineLimit(1)
        }
    }

    private func caption(_ option: BookCandidate) -> String {
        let language = option.isEnglish ? "English" : "Other language"
        return [language, option.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    private func choose(_ option: BookCandidate) {
        guard downloading == nil else { return }
        downloading = option.id
        Task {
            defer { downloading = nil }
            if let data = await lookup.coverData(for: option) {
                onPick(data)
                dismiss()
            } else {
                failed = true
            }
        }
    }
}
