import Foundation
import SwiftData

enum SampleData {
    /// Seeds a handful of books so the simulator and previews have something to show.
    @MainActor
    static func insert(into context: ModelContext) {
        func category(_ name: String) -> BookCategory {
            let category = BookCategory(name: name)
            context.insert(category)
            return category
        }
        let classics = category("Classics")
        let fantasy = category("Fantasy")
        let sciFi = category("Science Fiction")
        let nonFiction = category("Non-fiction")
        let romance = category("Romance")

        let books: [(Book, [BookCategory], status: ReadingStatus, rank: Int?, note: String?)] = [
            (Book(title: "Pride and Prejudice", authors: ["Jane Austen"], isbn: "9780141439518", pageCount: 480, publishedYear: 1813),
             [classics, romance], .read, 1, "The wittiest book about first impressions ever written."),
            (Book(title: "The Hobbit", authors: ["J. R. R. Tolkien"], pageCount: 310, publishedYear: 1937),
             [fantasy, classics], .read, 2, "A cosy adventure that still feels like home."),
            (Book(title: "Dune", authors: ["Frank Herbert"], pageCount: 617, publishedYear: 1965),
             [sciFi, classics], .read, 3, nil),
            (Book(title: "Sapiens", authors: ["Yuval Noah Harari"], pageCount: 443, publishedYear: 2011),
             [nonFiction], .reading, nil, nil),
            (Book(title: "The Left Hand of Darkness", authors: ["Ursula K. Le Guin"], pageCount: 304, publishedYear: 1969),
             [sciFi], .reading, nil, nil),
            (Book(title: "Circe", authors: ["Madeline Miller"], pageCount: 393, publishedYear: 2018),
             [fantasy], .read, nil, nil),
            (Book(title: "Thinking, Fast and Slow", authors: ["Daniel Kahneman"], pageCount: 499, publishedYear: 2011),
             [nonFiction], .unread, nil, nil),
            (Book(title: "Persuasion", authors: ["Jane Austen"], pageCount: 272, publishedYear: 1817),
             [classics, romance], .unread, nil, nil),
        ]

        for (index, entry) in books.enumerated() {
            let (book, categories, status, rank, note) = entry
            context.insert(book)
            book.categories = categories
            book.setStatus(status)
            book.favoriteRank = rank
            book.recommendationNote = note
            // Stagger dates so "Recently added" sorting is visible.
            book.dateAdded = Date.now.addingTimeInterval(TimeInterval(-86_400 * index))
        }

        // One book out with a friend, one borrowed and returned before.
        let circe = books.first { $0.0.title == "Circe" }!.0
        circe.lend(to: "Priya Sharma", on: Date.now.addingTimeInterval(-86_400 * 12))
        let hobbit = books.first { $0.0.title == "The Hobbit" }!.0
        hobbit.lend(to: "Arjun", on: Date.now.addingTimeInterval(-86_400 * 90))
        hobbit.markReturned(on: Date.now.addingTimeInterval(-86_400 * 60))
        // And one that's a friend's copy.
        let sapiens = books.first { $0.0.title == "Sapiens" }!.0
        sapiens.borrow(from: "Meera", on: Date.now.addingTimeInterval(-86_400 * 20))
    }

    /// Seeds sample data on first launch in the simulator only. Never runs on a real phone.
    @MainActor
    static func seedSimulatorIfEmpty(_ context: ModelContext) {
        #if DEBUG && targetEnvironment(simulator)
        let count = (try? context.fetchCount(FetchDescriptor<Book>())) ?? 0
        if count == 0 { insert(into: context) }
        #endif
    }

    @MainActor
    static let previewContainer: ModelContainer = {
        let container = try! ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        insert(into: container.mainContext)
        return container
    }()
}
