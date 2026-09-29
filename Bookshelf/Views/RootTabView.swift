import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AccountStore.self) private var account

    var body: some View {
        TabView {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "sparkle.magnifyingglass") }
            CurrentlyReadingView()
                .tabItem { Label("Reading", systemImage: "book") }
            FavoritesShelfView()
                .tabItem { Label("Favourites", systemImage: "star") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .task {
            SampleData.seedSimulatorIfEmpty(context)
            LibraryFixes.runPending(in: context)
            await DescriptionBackfill.run(in: context)
        }
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
