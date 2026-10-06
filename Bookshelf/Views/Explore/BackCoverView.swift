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
                    .font(Font.inter(.title3, .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !book.authors.isEmpty {
                    Text("by \(book.authorLine)")
                        .font(Font.inter(.subheadline).italic())
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

    /// The book as a solid object: front, back and the spine between them, so that
    /// turning it shows its thickness rather than a card spinning.
    private func bookInHand(width: CGFloat) -> some View {
        #if DEBUG
        // For simulator screenshots part-way through the turn: `-previewFlipAngle 60`.
        let held = UserDefaults.standard.string(forKey: "previewFlipAngle").flatMap(Double.init)
        let angle: Double = held ?? restingAngle
        #else
        let angle: Double = restingAngle
        #endif
        let thickness = Self.thickness(pages: book.pageCount)
        return ZStack {
            CoverView(book: book, width: width)
                .overlay(alignment: .leading) { Hinge(edge: .leading) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .modifier(BookFace(angle: angle, side: .front, depth: thickness / 2, flat: reduceMotion))
            SpineFace(book: book, color: color, thickness: thickness, height: width * 1.5)
                .modifier(BookFace(angle: angle, side: .spine, depth: width / 2, flat: reduceMotion))
            BackCoverFace(book: book, color: color, width: width)
                .overlay(alignment: .trailing) { Hinge(edge: .trailing) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .modifier(BookFace(angle: angle, side: .back, depth: thickness / 2, flat: reduceMotion))
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
        .contentShape(Rectangle())
        .onTapGesture { turn(to: !showingBack) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(showingBack ? "Shows the front cover" : "Shows the back cover")
    }

    /// Held at a slight angle rather than dead flat, so the spine still shows.
    private var restingAngle: Double {
        if reduceMotion { return showingBack ? 180 : 0 }
        return showingBack ? 174 : 8
    }

    /// Thicker books for more pages, within sensible limits.
    static func thickness(pages: Int?) -> CGFloat {
        min(max(CGFloat(pages ?? 300) / 9, 22), 56)
    }

    private func turn(to back: Bool) {
        withAnimation(.spring(duration: 0.7, bounce: 0.2)) { showingBack = back }
    }
}

/// One face of the turning book, placed in 3D: each face turns about the book's
/// centre, which is `depth` behind it, and is only drawn while it faces you.
private struct BookFace: ViewModifier, Animatable {
    enum Side {
        case front, spine, back

        /// How far round the book this face sits from the front.
        var offset: Double {
            switch self {
            case .front: 0
            case .spine: -90
            case .back: -180
            }
        }
    }

    /// 0 = front towards you, 180 = back towards you.
    var angle: Double
    let side: Side
    let depth: CGFloat
    /// Reduce Motion: fade between the covers instead of turning.
    let flat: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        if flat {
            switch side {
            case .front: content.opacity(1 - angle / 180)
            case .back: content.opacity(angle / 180)
            case .spine: content.hidden()
            }
        } else {
            let local = angle + side.offset
            content
                .opacity(cos(local * .pi / 180) > 0.01 ? 1 : 0)
                .rotation3DEffect(.degrees(local), axis: (x: 0, y: 1, z: 0), anchor: .center,
                                  anchorZ: -depth, perspective: 0.4)
        }
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
            .allowsHitTesting(false)
    }
}

/// The book's spine: a darker shade of the cover, with the title running down it.
private struct SpineFace: View {
    let book: Book
    let color: CoverColor.RGB
    let thickness: CGFloat
    let height: CGFloat

    private var shade: CoverColor.RGB { .init(r: color.r * 0.82, g: color.g * 0.82, b: color.b * 0.82) }

    var body: some View {
        ZStack {
            Color(red: shade.r, green: shade.g, blue: shade.b)
            // Rounded like a real spine: lighter down the middle.
            LinearGradient(colors: [.black.opacity(0.18), .white.opacity(0.10), .black.opacity(0.18)],
                           startPoint: .leading, endPoint: .trailing)
            Text(book.title)
                .font(.custom("Inter-SemiBold", size: min(thickness * 0.42, 15)))
                .foregroundStyle(CoverColor.prefersLightText(on: shade) ? Color.white : Color.black)
                .lineLimit(1)
                .frame(width: height - 40)
                .rotationEffect(.degrees(90))
        }
        .frame(width: thickness, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
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
                    .font(.inter(.caption2))
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
            .font(Font.inter(style))
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
                    .font(Font.inter(.callout).italic())
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
                    .font(.inter(.footnote, .semibold))
                    .buttonStyle(.bordered)
                    .tint(ink)
                    if notFound {
                        Text("None found online. You can add one from Full details.")
                            .font(.inter(.caption))
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
