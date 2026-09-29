import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class LoanTests: XCTestCase {
    // The container must outlive the test: a context doesn't keep it alive.
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    private func newBook() -> Book {
        let book = Book(title: "Circe")
        context.insert(book)
        return book
    }

    func testLendAndReturn() {
        let book = newBook()
        XCTAssertFalse(book.isLent)

        book.lend(to: "  Priya  ", contactID: "abc", on: day(1))
        XCTAssertTrue(book.isLent)
        XCTAssertEqual(book.currentLoan?.borrowerName, "Priya")
        XCTAssertEqual(book.currentLoan?.contactID, "abc")
        XCTAssertTrue(book.pastLoans.isEmpty)

        book.markReturned(on: day(10))
        XCTAssertFalse(book.isLent)
        XCTAssertEqual(book.pastLoans.map(\.borrowerName), ["Priya"])
        XCTAssertEqual(book.pastLoans.first?.returnedAt, day(10))
    }

    func testCannotLendABookThatIsAlreadyOut() {
        let book = newBook()
        book.lend(to: "Priya")
        book.lend(to: "Arjun")
        XCTAssertEqual(book.currentLoan?.borrowerName, "Priya")
        XCTAssertEqual(book.loans.count, 1)
    }

    func testBlankNamesAreIgnored() {
        let book = newBook()
        book.lend(to: "   ")
        XCTAssertFalse(book.isLent)
    }

    func testHistoryIsNewestFirst() {
        let book = newBook()
        book.lend(to: "First", on: day(1)); book.markReturned(on: day(2))
        book.lend(to: "Second", on: day(5)); book.markReturned(on: day(6))
        book.lend(to: "Now", on: day(9))
        XCTAssertEqual(book.pastLoans.map(\.borrowerName), ["Second", "First"])
        XCTAssertEqual(book.currentLoan?.borrowerName, "Now")
    }

    func testDeletingABookDeletesItsLoans() throws {
        let book = newBook()
        book.lend(to: "Priya")
        try context.save()

        context.deleteBook(book)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<Loan>()).isEmpty)
    }

    func testLentBooksGroupByFriend() {
        func book(_ title: String) -> Book {
            let book = Book(title: title)
            context.insert(book)
            return book
        }
        let circe = book("Circe"), dune = book("Dune"), sapiens = book("Sapiens"), home = book("At home")
        dune.lend(to: "Priya", on: day(5))
        circe.lend(to: "priya ", on: day(1))     // same friend, typed differently
        sapiens.lend(to: "Arjun", on: day(3))
        home.lend(to: "Arjun", on: day(2)); home.markReturned(on: day(4))   // back home

        let groups = LentBooksView.groups(from: [circe, dune, sapiens, home])

        XCTAssertEqual(groups.map(\.name), ["Arjun", "Priya"], "Newest spelling of the name")
        XCTAssertEqual(groups[0].books.map(\.title), ["Sapiens"], "Returned books aren't listed")
        XCTAssertEqual(groups[1].books.map(\.title), ["Circe", "Dune"], "Longest away first")
    }

    func testLentCountInStats() {
        let a = newBook(), b = newBook()
        _ = newBook()
        a.lend(to: "Priya")
        b.lend(to: "Arjun"); b.markReturned()
        XCTAssertEqual(LibraryStats(books: [a, b]).lentCount, 1)
    }
}
