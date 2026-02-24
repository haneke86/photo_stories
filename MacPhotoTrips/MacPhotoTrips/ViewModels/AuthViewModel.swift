import Foundation
import Combine

/// Coordinates Sign in with Apple (via Cognito hosted UI) with AuthService.
@MainActor
final class AuthViewModel: ObservableObject {
    let authService: AuthService
    private var cancellable: AnyCancellable?

    init(authService: AuthService) {
        self.authService = authService
        // Forward objectWillChange from AuthService so SwiftUI re-renders
        cancellable = authService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    @MainActor
    convenience init() {
        self.init(authService: AuthService())
    }

    var isAuthenticated: Bool { authService.isAuthenticated }
    var isLoading: Bool { authService.isLoading }
    var errorMessage: String? { authService.errorMessage }

    func signIn() async {
        await authService.signIn()
    }

    func signOut() {
        authService.signOut()
    }
}
