import SwiftUI
import SwiftData

/// A book picked off the shelf on Explore: it shows its front, then turns over so you
/// can read the back before deciding. Tap the book to turn it over again.
struct BackCoverView: View {
    @Bindable var book: Book
    @State private var showingBack = false
    @State private var color = CoverColor.fallback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            // The book takes all the room the title and buttons leave it.
            GeometryReader { proxy in
                bookInHand(width: min(proxy.size.width, proxy.size.height / 1.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 2) {
                Text(book.title)
                    .font(Theme.serif(.title3, .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !book.authors.isEmpty {
                    Text("by \(book.authorLine)")
                        .font(Theme.serif(.subheadline).italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                Button {
                    withAnimation { book.setStatus(.reading) }
                    dismiss()
                } label: {
                    Label("Start reading", systemImage: "book.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink(value: book) {
                    Text("Full details")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .paperScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            color = CoverColor.average(of: book.coverImage)
            // A beat with the front cover, then turn it over.
            try? await Task.sleep(for: .milliseconds(550))
            turn(to: true)
        }
    }

    private func bookInHand(width: CGFloat) -> some View {
        let angle: Double = showingBack ? 180 : 0
        return ZStack {
            CoverView(book: book, width: width)
                .modifier(FlipFace(angle: angle, isBack: false, flat: reduceMotion))
            BackCoverFace(book: book, color: color, width: width)
                .modifier(FlipFace(angle: angle, isBack: true, flat: reduceMotion))
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
        .contentShape(Rectangle())
        .onTapGesture { turn(to: !showingBack) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(showingBack ? "Shows the front cover" : "Shows the back cover")
    }

    private func turn(to back: Bool) {
        withAnimation(.spring(duration: 0.7, bounce: 0.2)) { showingBack = back }
    }
}

/// One side of the turning book. Each side is only visible while it faces you, so the
/// other never shows through mirrored.
private struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool
    /// Reduce Motion: fade between the sides instead of turning.
    let flat: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        if flat {
            content.opacity(isBack ? angle / 180 : 1 - angle / 180)
        } else {
            content
                .opacity((angle >= 90) == isBack ? 1 : 0)
                .rotation3DEffect(.degrees(isBack ? angle - 180 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        }
    }
}

/// The back of the book: its description on the cover's own colour, with the page
/// count and a barcode at the bottom.
private struct BackCoverFace: View {
    @Bindable var book: Book
    let color: CoverColor.RGB
    let width: CGFloat
    @State private var searching = false
    @State private var notFound = false

    private var ink: Color { CoverColor.prefersLightText(on: color) ? .white : .black }

    private var facts: String {
        var facts: [String] = []
        if let pages = book.pageCount { facts.append("\(pages) pages") }
        if let year = book.publishedYear { facts.append(String(year)) }
        return facts.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            blurb
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .bottom) {
                Text(facts)
                    .font(.caption2)
                    .foregroundStyle(ink.opacity(0.75))
                Spacer()
                if let isbn = book.isbn {
                    BarcodeBox(isbn: isbn)
                }
            }
        }
        .padding(20)
        .frame(width: width, height: width * 1.5)
        .background(Color(red: color.r, green: color.g, blue: color.b))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.08), lineWidth: 0.5))
    }

    private static let textStyles: [Font.TextStyle] = [.body, .callout, .subheadline, .footnote, .caption, .caption2]

    private func blurbText(_ summary: String, _ style: Font.TextStyle) -> some View {
        Text(summary)
            .font(Theme.serif(style))
            .lineSpacing(2)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var blurb: some View {
        if let summary = book.summary {
            // The largest text size at which the whole description fits; only a very
            // long one falls through to the last option and scrolls.
            ViewThatFits(in: .vertical) {
                ForEach(Self.textStyles, id: \.self) { style in
                    blurbText(summary, style)
                }
                ScrollView {
                    blurbText(summary, .caption2)
                }
                .scrollIndicators(.hidden)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(searching ? "Looking for a description…" : "No description yet")
                    .font(Theme.serif(.callout).italic())
                    .foregroundStyle(ink.opacity(0.85))
                if searching {
                    ProgressView().tint(ink)
                } else {
                    Button("Find description", systemImage: "text.magnifyingglass") {
                        searching = true
                        Task {
                            notFound = !(await BookLookup().fillMissingDescription(of: book))
                            searching = false
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(ink)
                    if notFound {
                        Text("None found online. You can add one from Full details.")
                            .font(.caption)
                            .foregroundStyle(ink.opacity(0.75))
                    }
                }
            }
        }
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
