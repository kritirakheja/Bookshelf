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
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, Bookstore.self, DeletedBookstore.self,
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

    // MARK: Borrowing

    func testBorrowAndGiveBack() {
        let book = newBook()
        XCTAssertTrue(book.isOwned)

        book.borrow(from: " Meera ", on: day(1))
        XCTAssertTrue(book.isBorrowed)
        XCTAssertFalse(book.isOwned)
        XCTAssertEqual(book.borrowing?.borrowerName, "Meera")
        XCTAssertNil(book.currentLoan, "Borrowing isn't lending")
        XCTAssertTrue(book.pastLoans.isEmpty)

        book.giveBack(on: day(9))
        XCTAssertFalse(book.isBorrowed)
        XCTAssertTrue(book.isGivenBack)
        XCTAssertFalse(book.isOwned, "Still not mine after giving it back")
        XCTAssertEqual(book.borrowing?.returnedAt, day(9))
    }

    func testCannotLendABorrowedBook() {
        let book = newBook()
        book.borrow(from: "Meera")
        book.lend(to: "Priya")
        XCTAssertFalse(book.isLent)
    }

    func testCannotMarkALentBookAsBorrowed() {
        let book = newBook()
        book.lend(to: "Priya")
        book.borrow(from: "Meera")
        XCTAssertFalse(book.isBorrowed)
    }

    func testStatsCountOwnedBooksAndBorrowedSeparately() {
        let mine = newBook(), borrowed = newBook(), givenBack = newBook()
        mine.setStatus(.read)
        borrowed.borrow(from: "Meera")
        borrowed.setStatus(.read)
        givenBack.borrow(from: "Arjun"); givenBack.giveBack()

        let stats = LibraryStats(books: [mine, borrowed, givenBack])
        XCTAssertEqual(stats.total, 1, "Books = books I own")
        XCTAssertEqual(stats.borrowedCount, 1, "Given-back books aren't with me any more")
        XCTAssertEqual(stats.readCount, 2, "Borrowed books still count as read")
        XCTAssertEqual(stats.unreadCount, 0, "A given-back book isn't waiting to be read")
    }

    func testBorrowedBooksGroupByOwner() {
        let a = newBook(), b = newBook(), c = newBook(), lent = newBook()
        a.borrow(from: "Meera", on: day(3))
        b.borrow(from: "meera", on: day(1))
        c.borrow(from: "Arjun"); c.giveBack()
        lent.lend(to: "Priya")

        let groups = LentBooksView.groups(from: [a, b, c, lent], direction: .borrowed)
        XCTAssertEqual(groups.map(\.name), ["Meera"])
        XCTAssertEqual(groups[0].books.count, 2)
        XCTAssertEqual(LentBooksView.groups(from: [a, b, c, lent], direction: .lent).map(\.name), ["Priya"])
    }

    func testLentCountInStats() {
        let a = newBook(), b = newBook()
        _ = newBook()
        a.lend(to: "Priya")
        b.lend(to: "Arjun"); b.markReturned()
        XCTAssertEqual(LibraryStats(books: [a, b]).lentCount, 1)
    }
}
