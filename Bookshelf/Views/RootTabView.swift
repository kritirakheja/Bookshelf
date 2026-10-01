import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AccountStore.self) private var account
    /// Reopens on the tab you were last on.
    @AppStorage("selectedTab") private var selectedTab = "explore"
    #if DEBUG
    /// For simulator screenshots: launch with `-previewBook "<title>"` to open that book's page.
    @State private var previewBook: Book?
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "sparkle.magnifyingglass") }
                .tag("explore")
            CurrentlyReadingView()
                .tabItem { Label("Reading", systemImage: "book") }
                .tag("reading")
            FavoritesShelfView()
                .tabItem { Label("Favourites", systemImage: "star") }
                .tag("favourites")
            BookstoresView()
                .tabItem { Label("Bookstores", systemImage: "map") }
                .tag("bookstores")
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag("profile")
        }
        .task {
            SampleData.seedSimulatorIfEmpty(context)
            LibraryFixes.runPending(in: context)
            #if DEBUG
            if let title = UserDefaults.standard.string(forKey: "previewBook") {
                previewBook = try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.title == title })).first
            }
            #endif
            await DescriptionBackfill.run(in: context)
        }
        #if DEBUG
        .fullScreenCover(item: $previewBook) { book in
            NavigationStack { BookDetailView(book: book) }
        }
        #endif
        // Sync when the app opens and when you leave it, so the backup is never far behind.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active || phase == .background {
                Task { await account.sync() }
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
