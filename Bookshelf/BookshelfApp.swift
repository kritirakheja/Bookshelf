import SwiftUI
import SwiftData

@main
struct BookshelfApp: App {
    private let container: ModelContainer
    @State private var account: AccountStore

    init() {
        let container = try! ModelContainer(for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, Bookstore.self, DeletedBookstore.self)
        self.container = container
        _account = State(initialValue: AccountStore(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(account)
        }
        .modelContainer(container)
    }
}
