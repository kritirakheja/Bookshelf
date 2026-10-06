import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws a book's covers and spine as images, to wrap around the 3D book.
@MainActor
enum BookArt {
    static func faces(for book: Book, width: CGFloat) -> Book3DView.Faces {
        let color = CoverColor.average(of: book.coverImage)
        let size = CGSize(width: width, height: width * 1.5)
        let thickness = width * thickness(pages: book.pageCount)
        return Book3DView.Faces(
            front: image(FrontArt(book: book, size: size)),
            back: image(BackArt(summary: book.summary, pages: book.pageCount, year: book.publishedYear,
                                isbn: book.isbn, color: color, size: size)),
            spine: image(SpineArt(title: book.title, color: color, size: CGSize(width: thickness, height: size.height)))
        )
    }

    /// Thicker books for more pages, within sensible limits (as a fraction of the width).
    static func thickness(pages: Int?) -> CGFloat {
        min(max(CGFloat(pages ?? 300) / 3500, 0.06), 0.16)
    }

    /// A barcode image for an ISBN, as printed on a back cover.
    nonisolated static func barcode(for isbn: String) -> UIImage? {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(isbn.utf8)
        filter.quietSpace = 2
        guard let output = filter.outputImage,
              let cgImage = barcodeContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    nonisolated private static let barcodeContext = CIContext()

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
            if let data = book.coverImage, let image = CoverImage.enlarged(data, toWidth: size.width * 3) {
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
                .font(.inter(.callout).italic())
                .foregroundStyle(ink.opacity(0.85))
        }
    }

    private func blurbText(_ summary: String, _ style: Font.TextStyle) -> some View {
        Text(summary)
            .font(.inter(style))
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
                .font(.inter(size: min(size.width * 0.42, 15), .semibold))
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
            if let barcode = BookArt.barcode(for: isbn) {
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
