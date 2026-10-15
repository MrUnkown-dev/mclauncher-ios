import SwiftUI

/// Account management: offline ("cracked") accounts plus Microsoft sign-in.
struct AccountsView: View {
    @EnvironmentObject private var model: LauncherModel
    @EnvironmentObject private var store: AccountStore
    @State private var newName = ""
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.accounts) { account in
                        accountRow(account)
                    }
                    .onDelete { indexSet in
                        for index in indexSet { store.remove(store.accounts[index]) }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Offline accounts work in singleplayer and on servers with online-mode disabled. Microsoft accounts work everywhere, including Realms and online servers.")
                }

                Section("Add offline account") {
                    HStack {
                        TextField("Username", text: $newName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") {
                            model.addOfflineAccount(newName)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Add Microsoft account") {
                    Button {
                        Task {
                            isSigningIn = true
                            await model.signInMicrosoft()
                            isSigningIn = false
                        }
                    } label: {
                        HStack {
                            if isSigningIn { ProgressView().controlSize(.small) }
                            Label(isSigningIn ? "Waiting for sign-in…" : "Sign in with Microsoft",
                                  systemImage: "person.badge.key.fill")
                        }
                    }
                    .disabled(isSigningIn)
                }
            }
            .navigationTitle("Accounts")
        }
    }

    private func accountRow(_ account: Account) -> some View {
        Button {
            store.select(account)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(account.type == .microsoft ? Color.blue.opacity(0.25) : Color.gray.opacity(0.25))
                    Image(systemName: account.type == .microsoft ? "checkmark.seal.fill" : "wifi.slash")
                        .foregroundStyle(account.type == .microsoft ? .blue : .gray)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.username).font(.subheadline.bold())
                    Text("\(account.type.displayName) · \(account.uuid.prefix(8))…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if store.selectedAccount?.id == account.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
