import SwiftUI
import SwiftData

@main
struct BookshelfApp: App {
    private let container: ModelContainer
    @State private var account: AccountStore

    init() {
        var uiTesting = false
        #if DEBUG
        uiTesting = PreviewArgs.uiTesting
        #endif
        let container = uiTesting
            ? SampleData.walkthroughContainer()
            : try! ModelContainer(for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, Bookstore.self, DeletedBookstore.self)
        self.container = container
        Theme.applyBarFonts()
        _account = State(initialValue: AccountStore(container: container, connected: !uiTesting))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(account)
                .tint(Theme.accent)
                .font(.inter(.body))
        }
        .modelContainer(container)
    }
}
