import SwiftUI
import SwiftData

extension ModelContext {
    /// Deletes a book everywhere: closes its gap on the favourites shelf, and leaves a
    /// marker so sync removes it from the backup and other devices too.
    func deleteBook(_ book: Book) {
        if book.isFavorite {
            FavoritesShelf.remove(book, library: (try? fetch(FetchDescriptor<Book>())) ?? [])
        }
        if let remoteID = book.remoteID {
            insert(DeletedBook(remoteID: remoteID))
        }
        delete(book)
    }

    /// Removes a saved bookstore, leaving a marker so the removal syncs.
    func deleteBookstore(_ store: Bookstore) {
        if store.syncedFingerprint != nil {
            insert(DeletedBookstore(remoteID: store.id))
        }
        delete(store)
    }
}

extension View {
    /// Asks before deleting `book` (set it to start); the book is deleted after `beforeDelete`.
    func confirmDeletingBook(_ book: Binding<Book?>, beforeDelete: @escaping () async -> Void = {}) -> some View {
        modifier(DeleteBookConfirmation(book: book, beforeDelete: beforeDelete))
    }
}

private struct DeleteBookConfirmation: ViewModifier {
    @Binding var book: Book?
    let beforeDelete: () async -> Void
    @Environment(\.modelContext) private var context
    @Environment(AccountStore.self) private var account

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete “\(book?.title ?? "")”?",
            isPresented: Binding(get: { book != nil }, set: { if !$0 { book = nil } }),
            titleVisibility: .visible,
            presenting: book
        ) { book in
            Button("Delete book", role: .destructive) {
                Task {
                    await beforeDelete()
                    withAnimation { context.deleteBook(book) }
                }
            }
        } message: { _ in
            Text(account.isSignedIn
                 ? "It will be removed from your library, your backup and your other devices. This can't be undone."
                 : "It will be removed from your library. This can't be undone.")
        }
    }
}
