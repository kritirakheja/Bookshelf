import SwiftUI
import SwiftData

@main
struct BookshelfApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [Book.self, BookCategory.self])
    }
}
