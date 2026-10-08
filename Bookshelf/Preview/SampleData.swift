import UIKit
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
        // Two saved bookstores (Bangalore).
        let blossom = Bookstore(name: "Blossom Book House", latitude: 12.9756, longitude: 77.6050)
        blossom.address = "Church Street, Bengaluru"
        blossom.city = "Bengaluru"
        blossom.note = "Three floors of second-hand books"
        context.insert(blossom)
        let atta = Bookstore(name: "Atta Galatta", latitude: 12.9352, longitude: 77.6245)
        atta.address = "Koramangala, Bengaluru"
        atta.city = "Bengaluru"
        context.insert(atta)

        // And one that's a friend's copy.
        let sapiens = books.first { $0.0.title == "Sapiens" }!.0
        sapiens.borrow(from: "Meera", on: Date.now.addingTimeInterval(-86_400 * 20))
    }

    /// A throwaway library for the UI walkthrough: the sample books plus drawn covers,
    /// descriptions, ratings and finish dates across three years, all in memory.
    @MainActor
    static func walkthroughContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        insert(into: context)
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: .now)
        let colours: [String: UIColor] = [
            "Pride and Prejudice": .systemPink, "The Hobbit": .systemGreen, "Dune": .systemOrange,
            "Sapiens": .white, "Circe": .systemYellow, "Persuasion": .systemBlue,
        ]
        for book in books {
            if let colour = colours[book.title] { book.coverImage = drawnCover(book.title, colour) }
            if book.title != "Persuasion" {
                book.summary = "\(book.title) is one of those books people press into your hands. "
                    + String(repeating: "It follows its characters through choices that seem small and turn out not to be. ", count: book.title == "Dune" ? 14 : 3)
            }
        }
        func finish(_ title: String, year: Int, rating: Int?) {
            guard let book = books.first(where: { $0.title == title }) else { return }
            book.dateRead = calendar.date(from: DateComponents(year: year, month: 3, day: 9))
            book.rating = rating
        }
        finish("Pride and Prejudice", year: thisYear, rating: 5)
        finish("The Hobbit", year: thisYear - 1, rating: 4)
        finish("Circe", year: thisYear - 2, rating: nil)
        books.first { $0.title == "Dune" }?.dateRead = nil
        // A week of reading in one of the books in progress.
        if let sapiens = books.first(where: { $0.title == "Sapiens" }) {
            let today = calendar.startOfDay(for: .now)
            for (back, page) in [(6, 40), (5, 95), (3, 130), (2, 190), (1, 215)] {
                sapiens.logProgress(page: page, on: calendar.date(byAdding: .day, value: -back, to: today)!)
            }
        }
        return container
    }

    private static func drawnCover(_ title: String, _ colour: UIColor) -> Data? {
        let size = CGSize(width: 400, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.withAlphaComponent(0.75).setFill()
            context.fill(CGRect(x: 0, y: 380, width: 400, height: 90))
            (title as NSString).draw(in: CGRect(x: 30, y: 400, width: 340, height: 60), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 30), .foregroundColor: UIColor.white,
            ])
        }.jpegData(compressionQuality: 0.9)
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
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        insert(into: container.mainContext)
        return container
    }()
}
