import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AccountStore.self) private var account
    /// Reopens on the tab you were last on.
    @AppStorage("selectedTab") private var selectedTab = "explore"
    #if DEBUG
    /// Screens opened by launch argument for simulator screenshots (see `PreviewArgs`).
    @State private var previewBook: Book?
    @State private var previewBackCover: Book?
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
            if let title = PreviewArgs.book {
                previewBook = try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.title == title })).first
            }
            if let title = PreviewArgs.backCover {
                previewBackCover = try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.title == title })).first
            }
            #endif
            #if DEBUG
            if PreviewArgs.uiTesting { return }
            #endif
            await DescriptionBackfill.run(in: context)
            // Not while tests run the app: it would go online for the whole library each time.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                await PageCountBackfill.run(in: context)
                await LibraryFixes.replaceWrongCovers(in: context)
                await CoverUpgrade.shared.run(in: context)
            }
        }
        #if DEBUG
        .fullScreenCover(item: $previewBook) { book in
            NavigationStack { BookDetailView(book: book) }
        }
        .fullScreenCover(item: $previewBackCover) { book in
            NavigationStack { BackCoverView(book: book) }
        }
        .fullScreenCover(isPresented: .constant(PreviewArgs.scanner)) {
            BarcodeScanScreen { _ in } onCancel: {}
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
