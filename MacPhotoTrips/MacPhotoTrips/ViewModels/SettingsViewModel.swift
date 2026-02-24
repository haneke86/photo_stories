import Foundation

/// Manages account deletion, cache clearing, and settings operations.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isDeleting = false
    @Published var errorMessage: String?
    @Published var usageInfo: UsageInfo?

    private let provider: BackendProvider
    private let authService: AuthService

    init(provider: BackendProvider, authService: AuthService) {
        self.provider = provider
        self.authService = authService
    }

    /// Fetch current usage quotas from the backend.
    func refreshUsage() async {
        usageInfo = try? await provider.fetchUsage()
    }

    /// Delete the user's account via the backend, sign out, and optionally clear local data.
    func deleteAccount(alsoDeleteLocalData: Bool) async {
        isDeleting = true
        errorMessage = nil

        do {
            try await provider.deleteAccount()

            if alsoDeleteLocalData {
                clearStoryCache()
                clearChatHistory()
                try? TimelineStore.delete()
                resetOnboarding()
            }

            authService.signOut()
        } catch {
            errorMessage = "Account deletion failed: \(error.localizedDescription)"
        }

        isDeleting = false
    }

    /// Delete all files in Documents/story_cache/.
    func clearStoryCache() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheDir = docs.appendingPathComponent("story_cache")
        try? FileManager.default.removeItem(at: cacheDir)
    }

    /// Delete Documents/chat_history.json.
    func clearChatHistory() {
        ChatHistoryStore.clear()
    }

    /// Reset onboarding flag (for debugging/testing).
    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }
}
