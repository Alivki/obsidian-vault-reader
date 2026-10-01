import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(Prefs.confirmExternalLinks) private var confirmExternalLinks = true
    @AppStorage(Prefs.loadRemoteImages) private var loadRemoteImages = false
    @State private var confirmSignOut = false
    @State private var confirmRedownload = false
    @State private var cacheSize: Int64?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Shad.muted)
                            Text(initials).font(.headline).foregroundStyle(Shad.foreground)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.user?.name ?? model.user?.login ?? "GitHub Account").font(.headline)
                            Text(model.user.map { "@\($0.login) · read-only" } ?? "Connected via GitHub App")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    LabeledContent("Repository", value: AppConfig.repoFullName)
                    LabeledContent("Branch", value: model.sync.index.branch ?? "—")
                    LabeledContent("Commit") {
                        Text(model.sync.index.commitSha.map { String($0.prefix(7)) } ?? "—").monospaced()
                    }
                    LabeledContent("Last Updated", value: model.sync.index.lastSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    LabeledContent("Notes", value: "\(model.vault.noteCount)")
                    LabeledContent("Attachments", value: "\(model.vault.files.count - model.vault.noteCount)")
                    LabeledContent("Storage Used", value: cacheSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")
                    Button("Update Now") {
                        Task { await model.refresh(force: true); updateCacheSize() }
                    }
                    .disabled(model.sync.isSyncing)
                    Button("Re-download All Notes") { confirmRedownload = true }
                        .disabled(model.sync.isSyncing)
                } header: {
                    Text("Sync")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }

                Section {
                    Toggle("Confirm External Links", isOn: $confirmExternalLinks)
                    Toggle("Load Remote Images", isOn: $loadRemoteImages)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Images hosted outside your vault can reveal your IP address to the server that hosts them.")
                }

                Section {
                    Button("Manage Access on GitHub") { openURL(AppConfig.tokenManagementURL) }
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Signing out removes your token and all saved notes from this device. To revoke every token the app has ever received, revoke the GitHub App on GitHub.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .task { updateCacheSize() }
        .confirmationDialog("Sign out and delete saved notes?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                dismiss()
                model.signOutAndDeleteData()
            }
        } message: {
            Text("Your token and all saved notes will be removed from this device.")
        }
        .confirmationDialog("Re-download all notes?", isPresented: $confirmRedownload, titleVisibility: .visible) {
            Button("Re-download") {
                Task { await model.redownloadEverything(); updateCacheSize() }
            }
        } message: {
            Text("Saved notes are cleared and fetched again from GitHub.")
        }
    }

    private var initials: String {
        let source = model.user?.name ?? model.user?.login ?? "?"
        return String(source.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    private func updateCacheSize() {
        let directory = model.sync.store.filesDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        cacheSize = files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
