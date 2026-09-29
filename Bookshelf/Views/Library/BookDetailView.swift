import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Bindable var book: Book
    @State private var editing = false
    @State private var pickingCategories = false
    @State private var showingShelfFull = false
    @State private var searchingCover = false
    @State private var coverNotFound = false
    @Query(filter: #Predicate<Book> { $0.favoriteRank != nil }) private var shelf: [Book]

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    CoverView(book: book, width: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.title2.weight(.semibold))
                        Text(book.authorLine)
                            .foregroundStyle(.secondary)
                        if let year = book.publishedYear {
                            Text("Published \(String(year))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let pages = book.pageCount {
                            Text("\(pages) pages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let isbn = book.isbn {
                            Text("ISBN \(isbn)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if book.coverImage == nil {
                            if searchingCover {
                                ProgressView().padding(.top, 4)
                            } else {
                                Button("Find cover online", systemImage: "magnifyingglass") {
                                    findCover()
                                }
                                .font(.footnote)
                                .buttonStyle(.bordered)
                                .padding(.top, 4)
                                if coverNotFound {
                                    Text("No cover found online.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Status", selection: Binding(get: { book.status }, set: { book.setStatus($0) })) {
                    ForEach(ReadingStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let dateStarted = book.dateStarted, book.status != .unread {
                    LabeledContent("Started", value: dateStarted.formatted(date: .abbreviated, time: .omitted))
                }
                if book.status == .read {
                    if let dateRead = book.dateRead {
                        DatePicker(
                            "Finished",
                            selection: Binding(get: { dateRead }, set: { book.dateRead = $0 }),
                            in: ...Date.now,
                            displayedComponents: .date
                        )
                    } else {
                        LabeledContent("Finished") {
                            Button("Add finish date") { book.dateRead = Calendar.current.startOfDay(for: .now) }
                        }
                    }
                }
                LabeledContent("Rating") {
                    StarRating(rating: $book.rating)
                }
            }

            Section("Categories") {
                Button {
                    pickingCategories = true
                } label: {
                    if book.categories.isEmpty {
                        Label("Add categories", systemImage: "plus")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(book.sortedCategories) { category in
                                    Text(category.name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }

            Section("Favourites") {
                if let rank = book.favoriteRank {
                    LabeledContent("On your shelf", value: "#\(rank)")
                    TextField("Why do you recommend it?", text: Binding(
                        get: { book.recommendationNote ?? "" },
                        set: { book.recommendationNote = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    Button("Remove from favourites", role: .destructive) {
                        FavoritesShelf.remove(book, library: shelf)
                    }
                } else {
                    Button("Add to favourites", systemImage: "star") {
                        showingShelfFull = FavoritesShelf.add(book, library: shelf) == .shelfFull
                    }
                }
            }

            Section("Notes") {
                TextField("Your thoughts on this book", text: $book.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            BookFormView(book: book)
        }
        .sheet(isPresented: $pickingCategories) {
            CategoryPickerView(book: book)
        }
        .alert("Your shelf is full", isPresented: $showingShelfFull) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can have up to \(FavoritesShelf.capacity) favourites. Remove one from the Favourites tab first.")
        }
    }

    private func findCover() {
        searchingCover = true
        Task {
            let found = await OpenLibraryClient().fillMissingCover(of: book)
            coverNotFound = !found
            searchingCover = false
        }
    }
}

#Preview {
    let container = SampleData.previewContainer
    let book = try! container.mainContext.fetch(FetchDescriptor<Book>()).first!
    return NavigationStack { BookDetailView(book: book) }
        .modelContainer(container)
}
