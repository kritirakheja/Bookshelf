import SwiftUI
import SwiftData

// MARK: - Status as bookmark ribbons

/// Unread · Reading · Read as ribbons hanging from the top of the card; the current
/// one hangs longer. Dates sit underneath.
struct BookmarkRibbons: View {
    @Bindable var book: Book

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(ReadingStatus.allCases) { status in
                    let selected = book.status == status
                    Button {
                        withAnimation(.spring(duration: 0.35)) { book.setStatus(status) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: status.systemImage)
                                .font(.system(size: 15, weight: .semibold))
                            Text(status.rawValue)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(selected ? .white : .secondary)
                        .frame(width: 78, height: selected ? 84 : 62, alignment: .center)
                        .padding(.bottom, 10)
                        .background(
                            RibbonShape().fill(selected ? AnyShapeStyle(status.tint.gradient) : AnyShapeStyle(Theme.rule.opacity(0.45)))
                        )
                        .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 4, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            dates
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var dates: some View {
        HStack(spacing: 14) {
            if let started = book.dateStarted, book.status != .unread {
                Label("Started \(started.formatted(date: .abbreviated, time: .omitted))", systemImage: "play")
            }
            if book.status == .read {
                if book.dateReadYearOnly, let year = book.finishDateText {
                    Button {
                        book.dateReadYearOnly = false
                    } label: {
                        Label("Finished in \(year) · set exact date", systemImage: "flag.checkered")
                    }
                } else if let finished = book.dateRead {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.checkered")
                        DatePicker("Finished", selection: Binding(get: { finished }, set: { book.dateRead = $0 }),
                                   in: ...Date.now, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                } else {
                    Button("Add finish date", systemImage: "flag.checkered") {
                        book.dateRead = Calendar.current.startOfDay(for: .now)
                    }
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// A bookmark ribbon: a strip with a notch cut into its bottom end.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = min(14, rect.height * 0.2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Staff pick

/// Favourites as a bookshop "staff pick" card, pinned to the shelf.
struct StaffPickCard: View {
    @Bindable var book: Book
    let shelf: [Book]
    @Binding var showingShelfFull: Bool
    @AppStorage("profileName") private var name = ""

    private var picker: String {
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "My pick" : "\(first)'s pick"
    }

    var body: some View {
        if let rank = book.favoriteRank {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(picker) · #\(rank)")
                        .font(Theme.handwriting(20))
                    Spacer()
                    Image(systemName: "star.fill").foregroundStyle(.orange)
                }
                TextField("Why would you recommend it?", text: Binding(
                    get: { book.recommendationNote ?? "" },
                    set: { book.recommendationNote = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .font(Theme.handwriting(17))
                .lineLimit(2...6)
                Button("Take off my favourites shelf") {
                    withAnimation { FavoritesShelf.remove(book, library: shelf) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.primary)
            .padding(18)
            .padding(.top, 6)
            .background(Theme.stickyNote, in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.15), radius: 5, x: 2, y: 4)
            .overlay(alignment: .top) {
                // The pin holding the card up.
                Circle()
                    .fill(Color.red.gradient)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 1, y: 1)
                    .offset(y: -6)
            }
            .rotationEffect(.degrees(-1.5))
            .padding(.horizontal, 30)
        } else {
            Button {
                withAnimation {
                    showingShelfFull = FavoritesShelf.add(book, library: shelf) == .shelfFull
                }
            } label: {
                Label("Recommend it: add to my Favourites", systemImage: "star")
                    .font(Theme.handwriting(17))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                        .foregroundStyle(Theme.brown.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.brown)
            .padding(.horizontal, 30)
        }
    }
}

// MARK: - Back-cover blurb

/// "About this book" set like a back-cover blurb, with a large first letter.
struct BlurbCard: View {
    @Bindable var book: Book
    @State private var expanded = false
    @State private var searching = false
    @State private var notFound = false

    private var isLong: Bool { (book.summary?.count ?? 0) > 320 }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                ShelfHeading(text: "About this book")
                if let summary = book.summary {
                    blurb(summary)
                        .lineSpacing(3)
                        .lineLimit(expanded || !isLong ? nil : 7)
                        .textSelection(.enabled)
                    if isLong {
                        Button(expanded ? "Less" : "Read more") {
                            withAnimation { expanded.toggle() }
                        }
                        .font(.footnote.weight(.semibold))
                        .tint(Theme.brown)
                    }
                } else if searching {
                    HStack {
                        Text("Looking for a description…").foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Button("Find description", systemImage: "text.magnifyingglass") {
                        searching = true
                        Task {
                            notFound = !(await BookLookup().fillMissingDescription(of: book))
                            searching = false
                        }
                    }
                    if notFound {
                        Text("No description found online. You can add one with Edit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension BlurbCard {
    /// The text with a large first letter, unless it opens with a quote mark or digit.
    private func blurb(_ summary: String) -> Text {
        guard let first = summary.first, first.isLetter else {
            return Text(summary).font(Theme.serif(.callout))
        }
        return Text(String(first)).font(.system(size: 34, weight: .bold, design: .serif)).foregroundColor(Theme.brown)
            + Text(summary.dropFirst()).font(Theme.serif(.callout))
    }
}

// MARK: - Margin notes

/// Your notes, written on lined paper.
struct MarginNotes: View {
    @Bindable var book: Book

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeading(text: "Margin notes")
                TextField("Your thoughts on this book…", text: $book.notes, axis: .vertical)
                    .font(Theme.handwriting(17))
                    .lineLimit(3...12)
                    .lineSpacing(9)
                    .background(alignment: .top) { LinedPaper() }
            }
        }
    }
}

private struct LinedPaper: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                var y: CGFloat = 26
                while y < max(proxy.size.height, 90) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += 31
                }
            }
            .stroke(Theme.rule.opacity(0.5), lineWidth: 0.6)
        }
    }
}
