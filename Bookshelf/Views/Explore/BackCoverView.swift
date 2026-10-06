import SwiftUI
import SwiftData

/// A book picked off the shelf on Explore, as a 3D object: it shows its front, then
/// turns over so you can read the back before deciding. Tap to turn it over.
struct BackCoverView: View {
    @Bindable var book: Book
    @State private var faces = Book3DView.Faces()
    @State private var searching = false
    @State private var notFound = false
    @Environment(\.dismiss) private var dismiss

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
                Book3DView(faces: faces, thickness: Self.thickness(pages: book.pageCount),
                           label: book.title, blurb: book.summary)
                    .task(id: ArtKey(width: width, summary: book.summary, cover: book.coverImage)) {
                        guard width > 0 else { return }
                        faces = BookArt.faces(for: book, width: width)
                    }
            }
            VStack(spacing: 2) {
                Text(book.title)
                    .font(Font.inter(.title3, .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                if !book.authors.isEmpty {
                    Text("by \(book.authorLine)")
                        .font(Font.inter(.subheadline).italic())
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
        .paperScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var findDescription: some View {
        if searching {
            ProgressView()
        } else {
            Button(notFound ? "No description found online" : "Find description", systemImage: "text.magnifyingglass") {
                searching = true
                Task {
                    notFound = !(await BookLookup().fillMissingDescription(of: book))
                    searching = false
                }
            }
            .font(.inter(.footnote, .semibold))
            .disabled(notFound)
        }
    }

    /// Thicker books for more pages, within sensible limits (as a fraction of the width).
    static func thickness(pages: Int?) -> CGFloat {
        min(max(CGFloat(pages ?? 300) / 3500, 0.06), 0.16)
    }
}

/// Draws a book's covers and spine as images, to wrap around the 3D book.
@MainActor
enum BookArt {
    static func faces(for book: Book, width: CGFloat) -> Book3DView.Faces {
        let color = CoverColor.average(of: book.coverImage)
        let size = CGSize(width: width, height: width * 1.5)
        let thickness = width * BackCoverView.thickness(pages: book.pageCount)
        return Book3DView.Faces(
            front: image(FrontArt(book: book, size: size)),
            back: image(BackArt(summary: book.summary, pages: book.pageCount, year: book.publishedYear,
                                isbn: book.isbn, color: color, size: size)),
            spine: image(SpineArt(title: book.title, color: color, size: CGSize(width: thickness, height: size.height)))
        )
    }

    private static func image(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct FrontArt: View {
    let book: Book
    let size: CGSize

    var body: some View {
        Group {
            if let data = book.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // No cover image: the app's usual placeholder with the title on it.
                CoverView(book: book, width: size.width)
                    .scaleEffect(1.06)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .leading) { Hinge(edge: .leading) }
        .clipped()
    }
}

/// The back of the book: its description on the cover's own colour, with the page
/// count and a barcode at the bottom. The text is as large as will fit.
private struct BackArt: View {
    let summary: String?
    let pages: Int?
    let year: Int?
    let isbn: String?
    let color: CoverColor.RGB
    let size: CGSize

    private static let textStyles: [Font.TextStyle] = [.body, .callout, .subheadline, .footnote, .caption, .caption2]

    private var ink: Color { CoverColor.prefersLightText(on: color) ? .white : .black }

    private var facts: String {
        var facts: [String] = []
        if let pages { facts.append("\(pages) pages") }
        if let year { facts.append(String(year)) }
        return facts.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            blurb
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .bottom) {
                Text(facts)
                    .font(.inter(.caption2))
                    .foregroundStyle(ink.opacity(0.75))
                Spacer()
                if let isbn {
                    BarcodeBox(isbn: isbn)
                }
            }
        }
        .padding(20)
        .frame(width: size.width, height: size.height)
        .background(Color(red: color.r, green: color.g, blue: color.b))
        .overlay(alignment: .trailing) { Hinge(edge: .trailing) }
    }

    @ViewBuilder
    private var blurb: some View {
        if let summary {
            // The largest text size at which the whole description fits; a very long
            // one ends up at the smallest size and is cut short.
            ViewThatFits(in: .vertical) {
                ForEach(Self.textStyles, id: \.self) { style in
                    blurbText(summary, style)
                        .fixedSize(horizontal: false, vertical: true)
                }
                blurbText(summary, .caption2)
            }
        } else {
            Text("No description yet")
                .font(Font.inter(.callout).italic())
                .foregroundStyle(ink.opacity(0.85))
        }
    }

    private func blurbText(_ summary: String, _ style: Font.TextStyle) -> some View {
        Text(summary)
            .font(Font.inter(style))
            .lineSpacing(2)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The darker band where a cover bends at the spine.
private struct Hinge: View {
    let edge: HorizontalEdge

    var body: some View {
        LinearGradient(colors: [.black.opacity(0.22), .black.opacity(0.04), .white.opacity(0.10), .clear],
                       startPoint: edge == .leading ? .leading : .trailing,
                       endPoint: edge == .leading ? .trailing : .leading)
            .frame(width: 14)
    }
}

/// The book's spine: a darker shade of the cover, with the title running down it.
private struct SpineArt: View {
    let title: String
    let color: CoverColor.RGB
    let size: CGSize

    private var shade: CoverColor.RGB { .init(r: color.r * 0.82, g: color.g * 0.82, b: color.b * 0.82) }

    var body: some View {
        ZStack {
            Color(red: shade.r, green: shade.g, blue: shade.b)
            // Rounded like a real spine: lighter down the middle.
            LinearGradient(colors: [.black.opacity(0.18), .white.opacity(0.10), .black.opacity(0.18)],
                           startPoint: .leading, endPoint: .trailing)
            Text(title)
                .font(.custom("Inter-SemiBold", size: min(size.width * 0.42, 15)))
                .foregroundStyle(CoverColor.prefersLightText(on: shade) ? Color.white : Color.black)
                .lineLimit(1)
                .frame(width: size.height - 40)
                .rotationEffect(.degrees(90))
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// The white barcode box printed on the back of a book.
private struct BarcodeBox: View {
    let isbn: String

    var body: some View {
        VStack(spacing: 2) {
            if let barcode = CoverColor.barcode(for: isbn) {
                Image(uiImage: barcode)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 84, height: 30)
            }
            Text(isbn)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.black)
        }
        .padding(5)
        .background(.white, in: RoundedRectangle(cornerRadius: 2))
        .accessibilityLabel("ISBN \(isbn)")
    }
}
