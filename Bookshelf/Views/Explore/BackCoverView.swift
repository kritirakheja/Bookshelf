import SwiftUI
import SwiftData

/// A book picked off the shelf on Explore, as a 3D object: it shows its front, then
/// turns over so you can read the back before deciding. Tap to turn it over.
struct BackCoverView: View {
    @Bindable var book: Book
    /// Called when "Start reading" is tapped, just before the screen closes.
    var onStartReading: () -> Void = {}
    @State private var faces = Book3DView.Faces()
    @State private var search = DescriptionSearch()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// What the covers are drawn from; they're redrawn when any of it changes.
    private struct ArtKey: Equatable {
        var width: CGFloat
        var summary: String?
        var cover: Data?
    }

    var body: some View {
        VStack(spacing: 14) {
            // The book takes all the room the title and buttons leave it.
            GeometryReader { proxy in
                let width = Book3DView.bookWidth(in: proxy.size).rounded()
                let overflow = (proxy.size.height * 0.04).rounded()
                Book3DView(faces: faces, thickness: BookArt.thickness(pages: book.pageCount),
                           label: book.title, blurb: book.summary, overflow: overflow)
                    .padding(.vertical, -overflow)
                    .task(id: ArtKey(width: width, summary: book.summary, cover: book.coverImage)) {
                        guard width > 0 else { return }
                        faces = BookArt.faces(for: book, width: width)
                    }
            }
            VStack(spacing: 2) {
                Text(book.title)
                    .font(.inter(.title3, .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                if !book.authors.isEmpty {
                    Text("by \(book.authorLine)")
                        .font(.inter(.subheadline).italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if book.summary == nil {
                findDescription
            }
            HStack(spacing: 12) {
                Button {
                    withAnimation { book.setStatus(.reading) }
                    onStartReading()
                    dismiss()
                } label: {
                    Label("Start reading", systemImage: "book.fill")
                        .font(.inter(.subheadline, .semibold))
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink(value: book) {
                    Text("Full details")
                        .font(.inter(.subheadline, .semibold))
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(.bottom, 12)
        .themedScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // The buttons take the book's own colour, as its full details page does.
        .tint(book.accentColor(for: colorScheme))
    }

    @ViewBuilder
    private var findDescription: some View {
        if search.isSearching {
            ProgressView()
        } else {
            Button(search.notFound ? "No description found online" : "Find description", systemImage: "text.magnifyingglass") {
                search.run(for: book)
            }
            .font(.inter(.footnote, .semibold))
            .disabled(search.notFound)
        }
    }
}
