import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context

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
        .task { SampleData.seedSimulatorIfEmpty(context) }
    }
}

#Preview {
    RootTabView()
        .modelContainer(SampleData.previewContainer)
}
