import SwiftUI

/// Email + password sign-up and log-in.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case logIn = "Log in"
        case signUp = "Sign up"
        var id: Self { self }
    }

    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?
    @State private var isError = false

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !working
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .onSubmit(submit)
                } footer: {
                    if mode == .signUp {
                        Text("At least 6 characters.")
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if working {
                                ProgressView()
                            } else {
                                Text(mode.rawValue).bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(isError ? .red : .secondary)
                    } else {
                        Text("Your library is backed up to your account and kept in sync on every device you log in on.")
                    }
                }
            }
            .navigationTitle(mode == .signUp ? "Create account" : "Welcome back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: mode) { message = nil }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        working = true
        message = nil
        Task {
            defer { working = false }
            do {
                let trimmed = email.trimmingCharacters(in: .whitespaces)
                switch mode {
                case .logIn:
                    try await account.logIn(email: trimmed, password: password)
                    dismiss()
                case .signUp:
                    switch try await account.signUp(email: trimmed, password: password) {
                    case .signedIn:
                        dismiss()
                    case .needsEmailConfirmation:
                        isError = false
                        message = "Check your email and tap the confirmation link, then log in here."
                        mode = .logIn
                    }
                }
            } catch {
                isError = true
                message = error.localizedDescription
            }
        }
    }
}
