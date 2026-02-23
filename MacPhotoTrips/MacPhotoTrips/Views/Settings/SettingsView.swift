import SwiftUI

/// Settings tab — account management, data clearing, and app info.
struct SettingsView: View {
    @ObservedObject var authVM: AuthViewModel
    @ObservedObject var settingsVM: SettingsViewModel

    @State private var showSignOutAlert = false
    @State private var showDeleteAlert = false
    @State private var showClearStoriesAlert = false
    @State private var showClearChatAlert = false
    @State private var showStoriesClearedToast = false
    @State private var showChatClearedToast = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            DesignTokens.bg.ignoresSafeArea()

            Form {
                // MARK: - Account

                Section {
                    Button(role: .none) {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(settingsVM.isDeleting)
                } header: {
                    Text("Account")
                }

                // MARK: - Data

                Section {
                    Button {
                        showClearStoriesAlert = true
                    } label: {
                        Label("Clear Story Cache", systemImage: "book.pages")
                    }

                    Button {
                        showClearChatAlert = true
                    } label: {
                        Label("Clear Chat History", systemImage: "bubble.left.and.text.bubble.right")
                    }
                } header: {
                    Text("Data")
                }

                // MARK: - About

                Section {
                    LabeledContent {
                        Text(appVersion)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } label: {
                        Label("Version", systemImage: "info.circle")
                    }

                    Link(destination: URL(string: "https://macphoto.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                } header: {
                    Text("About")
                }
            }
            .scrollContentBackground(.hidden)
            .tint(DesignTokens.teal)
            .navigationTitle("Settings")

            // Deletion overlay
            if settingsVM.isDeleting {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(DesignTokens.teal)
                    Text("Deleting account...")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)

        // MARK: - Alerts

        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                authVM.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }

        .alert("Delete Account", isPresented: $showDeleteAlert) {
            Button("Also Delete Local Data", role: .destructive) {
                Task { await settingsVM.deleteAccount(alsoDeleteLocalData: true) }
            }
            Button("Keep Local Data", role: .destructive) {
                Task { await settingsVM.deleteAccount(alsoDeleteLocalData: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will be permanently deleted within 30 days. You can choose to also delete stories and chat history from this device.")
        }

        .alert("Clear Story Cache", isPresented: $showClearStoriesAlert) {
            Button("Clear", role: .destructive) {
                settingsVM.clearStoryCache()
                showStoriesClearedToast = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all cached stories. They can be regenerated.")
        }

        .alert("Clear Chat History", isPresented: $showClearChatAlert) {
            Button("Clear", role: .destructive) {
                settingsVM.clearChatHistory()
                showChatClearedToast = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete your entire chat history.")
        }

        .alert("Error", isPresented: Binding(
            get: { settingsVM.errorMessage != nil },
            set: { if !$0 { settingsVM.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settingsVM.errorMessage ?? "")
        }

        // Toast overlays for confirmations
        .overlay(alignment: .bottom) {
            if showStoriesClearedToast {
                toastView(text: "Story cache cleared")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showStoriesClearedToast = false }
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if showChatClearedToast {
                toastView(text: "Chat history cleared")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showChatClearedToast = false }
                        }
                    }
            }
        }
    }

    // MARK: - Toast Helper

    private func toastView(text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(DesignTokens.teal.opacity(0.9))
            .clipShape(Capsule())
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
