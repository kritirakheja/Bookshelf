import SwiftUI
import SwiftData
import PhotosUI
import Charts

struct ProfileView: View {
    enum Route: Hashable {
        case allBooks, read, categories
    }

    @Query private var books: [Book]
    @AppStorage("profileName") private var name = ""
    @State private var photo: UIImage? = ProfilePhotoStore.load()
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        let stats = LibraryStats(books: books)
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)

                Section {
                    statGrid(stats)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    NavigationLink(value: Route.allBooks) {
                        LabeledContent { Text("\(stats.total)") } label: { Label("All books", systemImage: "books.vertical") }
                    }
                    NavigationLink(value: Route.read) {
                        LabeledContent { Text("\(stats.readCount)") } label: { Label("Read", systemImage: "checkmark.circle") }
                    }
                    NavigationLink(value: Route.categories) {
                        Label("Categories", systemImage: "square.grid.2x2")
                    }
                }

                if !stats.finishedPerYear.isEmpty {
                    Section {
                        finishedChart(stats)
                    } header: {
                        Text("Books finished per year")
                    } footer: {
                        if stats.datedReadCount < stats.readCount {
                            Text("Based on the \(stats.datedReadCount) of \(stats.readCount) read books that have a finish date.")
                        }
                    }
                }

                if stats.ratingCounts.contains(where: { $0 > 0 }) {
                    Section("How you rate books") {
                        ratingsChart(stats)
                    }
                }

                if !stats.topAuthors.isEmpty {
                    Section("Most-read authors") {
                        ForEach(stats.topAuthors) { author in
                            LabeledContent(author.name, value: "\(author.count) books")
                        }
                    }
                }

                if !stats.topCategories.isEmpty {
                    Section("Top categories") {
                        ForEach(stats.topCategories) { category in
                            LabeledContent(category.name, value: "\(category.count) books")
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .allBooks:
                    LibraryView()
                case .read:
                    StatusBooksList(status: .read).navigationTitle("Read")
                case .categories:
                    CategoriesView()
                }
            }
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .navigationDestination(for: BookCategory.self) { CategoryBooksView(category: $0) }
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        photo = ProfilePhotoStore.save(data)
                    }
                    photoItem = nil
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())

                    Image(systemName: "camera.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.multicolor)
                        .background(Circle().fill(.background))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo == nil ? "Add profile picture" : "Change profile picture")
            .contextMenu {
                if photo != nil {
                    Button("Remove photo", systemImage: "trash", role: .destructive) {
                        ProfilePhotoStore.remove()
                        photo = nil
                    }
                }
            }

            TextField("Your name", text: $name)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .submitLabel(.done)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stats

    private func statGrid(_ stats: LibraryStats) -> some View {
        VStack(spacing: 10) {
            // Library at a glance: one card, four counts.
            HStack(spacing: 0) {
                countStat("\(stats.total)", "Books")
                Divider().frame(height: 32)
                countStat("\(stats.readCount)", "Read")
                Divider().frame(height: 32)
                countStat("\(stats.readingCount)", "Reading")
                Divider().frame(height: 32)
                countStat("\(stats.unreadCount)", "Unread")
            }
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                tile(stats.pagesRead.formatted(), "Pages read", "doc.text.fill")
                tile(stats.averageRating.map { String(format: "%.1f", $0) } ?? "–", "Avg rating", "star.fill")
                tile("\(stats.readThisYear)", "Read in \(String(Calendar.current.component(.year, from: .now)))", "calendar")
            }
        }
    }

    private func countStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func finishedChart(_ stats: LibraryStats) -> some View {
        Chart(stats.finishedPerYear) { entry in
            BarMark(x: .value("Year", String(entry.year)), y: .value("Books", entry.count))
                .foregroundStyle(.tint)
                .annotation(position: .top) {
                    Text("\(entry.count)").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartYAxis(.hidden)
        .frame(height: 160)
        .padding(.vertical, 8)
    }

    private func ratingsChart(_ stats: LibraryStats) -> some View {
        Chart((1...5).reversed(), id: \.self) { star in
            BarMark(x: .value("Books", stats.ratingCounts[star - 1]), y: .value("Stars", "\(star)★"))
                .foregroundStyle(.yellow.gradient)
                .annotation(position: .trailing) {
                    Text("\(stats.ratingCounts[star - 1])").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .frame(height: 150)
        .padding(.vertical, 8)
    }
}

#Preview {
    ProfileView()
        .modelContainer(SampleData.previewContainer)
}
