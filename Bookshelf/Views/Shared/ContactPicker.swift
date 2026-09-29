import UIKit
import Contacts
import ContactsUI

/// Shows the system contact picker and returns the chosen person's name.
///
/// The picker runs outside the app, so Bookshelf never gets access to the rest of the
/// address book and iOS doesn't ask for Contacts permission. It's presented the UIKit way
/// because hosting it inside a SwiftUI sheet shows a blank screen.
@MainActor
enum ContactPicker {
    struct Picked {
        let name: String
        let contactID: String
    }

    private static var activeDelegate: Delegate?

    static func present(onPick: @escaping (Picked) -> Void) {
        guard let presenter = topViewController() else { return }
        let delegate = Delegate { picked in
            onPick(picked)
            activeDelegate = nil
        } onCancel: {
            activeDelegate = nil
        }
        activeDelegate = delegate   // the picker only holds its delegate weakly

        let picker = CNContactPickerViewController()
        picker.delegate = delegate
        presenter.present(picker, animated: true)
    }

    nonisolated static func displayName(for contact: CNContact) -> String? {
        let name = CNContactFormatter.string(from: contact, style: .fullName)
            ?? (contact.organizationName.isEmpty ? nil : contact.organizationName)
        return name?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private final class Delegate: NSObject, CNContactPickerDelegate {
        let onPick: (Picked) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (Picked) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            if let name = ContactPicker.displayName(for: contact) {
                onPick(Picked(name: name, contactID: contact.identifier))
            } else {
                onCancel()
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
