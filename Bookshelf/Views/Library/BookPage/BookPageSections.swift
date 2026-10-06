import SwiftUI
import SwiftData

// MARK: - Status, dates and rating

/// Unread · Reading · Read, with the dates and star rating underneath, on one card.
struct ReadingCard: View {
    @Bindable var book: Book

    var body: some View {
        PaperCard {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(ReadingStatus.allCases) { status in
                        statusButton(status)
                    }
                }
                dates
                StarRating(rating: $book.rating)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statusButton(_ status: ReadingStatus) -> some View {
        let selected = book.status == status
        return Button {
            withAnimation(.snappy) { book.setStatus(status) }
        } label: {
            Label(status.rawValue, systemImage: status.systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? Theme.paper : Color.secondary)
                .background(selected ? Theme.accent : Theme.rule.opacity(0.35), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var dates: some View {
        if book.status != .unread {
            HStack(spacing: 14) {
                if let started = book.dateStarted {
                    Text("Started \(started.formatted(date: .abbreviated, time: .omitted))")
                }
                if book.status == .read {
                    if book.dateReadYearOnly, let year = book.finishDateText {
                        Button("Finished in \(year) · set exact date") {
                            book.dateReadYearOnly = false
                        }
                    } else if let finished = book.dateRead {
                        HStack(spacing: 6) {
                            Text("Finished")
                            DatePicker("Finished", selection: Binding(get: { finished }, set: { book.dateRead = $0 }),
                                       in: ...Date.now, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        }
                    } else {
                        Button("Add finish date") {
                            book.dateRead = Calendar.current.startOfDay(for: .now)
                        }
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Favourite

/// The book's place on the favourites shelf and why you recommend it, or a button
/// to put it there.
struct FavouriteCard: View {
    @Bindable var book: Book
    let shelf: [Book]
    @Binding var showingShelfFull: Bool

    var body: some View {
        if let rank = book.favoriteRank {
            PaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ShelfHeading(text: "Favourite · #\(rank)")
                        Spacer()
                        Button("Remove") {
                            withAnimation { FavoritesShelf.remove(book, library: shelf) }
                        }
                        .font(.footnote)
                    }
                    TextField("Why would you recommend it?", text: Binding(
                        get: { book.recommendationNote ?? "" },
                        set: { book.recommendationNote = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .font(Theme.serif(.callout).italic())
                    .lineLimit(1...6)
                }
            }
        } else {
            Button {
                withAnimation {
                    showingShelfFull = FavoritesShelf.add(book, library: shelf) == .shelfFull
                }
            } label: {
                Label("Add to Favourites", systemImage: "star")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 18)
        }
    }
}

// MARK: - About

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
                    Text(summary)
                        .font(Theme.serif(.callout))
                        .lineSpacing(3)
                        .lineLimit(expanded || !isLong ? nil : 7)
                        .textSelection(.enabled)
                    if isLong {
                        Button(expanded ? "Less" : "Read more") {
                            withAnimation { expanded.toggle() }
                        }
                        .font(.footnote.weight(.semibold))
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

// MARK: - Notes

struct NotesCard: View {
    @Bindable var book: Book

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeading(text: "Notes")
                TextField("Your thoughts on this book…", text: $book.notes, axis: .vertical)
                    .lineLimit(3...12)
            }
        }
    }
}
