import Foundation
import AuthenticationServices
import Security

/// Manages Sign in with Apple via Cognito hosted UI (OAuth2 authorization code flow).
/// Stores Cognito tokens in Keychain, auto-refreshes before expiry.
@MainActor
final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var idToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    // Retain the session so it doesn't get deallocated mid-flow
    private var authSession: ASWebAuthenticationSession?
    private let sessionCoordinator = AuthSessionCoordinator()

    // Keychain keys
    private let idTokenKey = "com.macphoto.idToken"
    private let refreshTokenKey = "com.macphoto.refreshToken"
    private let tokenExpiryKey = "com.macphoto.tokenExpiry"

    private let callbackScheme = "macphoto"
    private let callbackRedirectURI = "macphoto://auth/callback"

    init() {
        cleanupIfReinstall()
        loadStoredTokens()
    }

    /// Detect fresh install or reinstall by checking UserDefaults.
    /// UserDefaults is cleared on app deletion, Keychain is not.
    /// If UserDefaults flag is missing but Keychain has tokens → reinstall → clear tokens.
    private func cleanupIfReinstall() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            clearKeychain()
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }

    /// The current valid JWT for API calls. Auto-refreshes if expired.
    var currentToken: String? {
        get async {
            if let expiry = tokenExpiry, expiry.timeIntervalSinceNow < 300 {
                await refreshTokenIfNeeded()
            }
            return idToken
        }
    }

    // MARK: - Sign In (Cognito Hosted UI → Apple)

    func signIn() async {
        isLoading = true
        errorMessage = nil

        do {
            print("[Auth] Opening auth session: \(authorizeURL)")
            let callbackURL = try await openAuthSession()
            print("[Auth] Callback received: \(callbackURL)")
            let code = try extractCode(from: callbackURL)
            let tokens = try await exchangeCodeForTokens(code)

            self.idToken = tokens.idToken
            self.refreshToken = tokens.refreshToken
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))

            saveTokensToKeychain()
            isAuthenticated = true
        } catch {
            print("[Auth] Sign-in error: \(error)")
            if let asError = error as? ASWebAuthenticationSessionError,
               asError.code == .canceledLogin {
                // User cancelled — not an error
            } else {
                errorMessage = "Sign in failed: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    /// Sign out — clear tokens from Keychain.
    func signOut() {
        idToken = nil
        refreshToken = nil
        tokenExpiry = nil
        clearKeychain()
        isAuthenticated = false
    }

    // MARK: - ASWebAuthenticationSession

    private var authorizeURL: URL {
        var components = URLComponents(string: "\(BackendConfig.cognitoDomainURL)/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: BackendConfig.cognitoClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "redirect_uri", value: callbackRedirectURI),
            URLQueryItem(name: "identity_provider", value: "SignInWithApple"),
        ]
        return components.url!
    }

    private func openAuthSession() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.authSession = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.invalidResponse)
                }
            }
            authSession?.prefersEphemeralWebBrowserSession = true
            authSession?.presentationContextProvider = sessionCoordinator
            authSession?.start()
        }
    }

    private func extractCode(from url: URL) throws -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = components?.queryItems ?? []

        // Check if Cognito/Apple returned an error
        if let error = params.first(where: { $0.name == "error" })?.value {
            let desc = params.first(where: { $0.name == "error_description" })?.value ?? error
            print("[Auth] Callback error: \(error) — \(desc)")
            throw AuthError.cognitoError(0, desc)
        }

        guard let code = params.first(where: { $0.name == "code" })?.value else {
            print("[Auth] Callback URL missing code: \(url)")
            throw AuthError.invalidResponse
        }
        return code
    }

    // MARK: - Token Exchange

    private struct TokenResponse {
        let idToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    private func exchangeCodeForTokens(_ code: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: BackendConfig.cognitoTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=authorization_code",
            "client_id=\(BackendConfig.cognitoClientId)",
            "code=\(code)",
            "redirect_uri=\(callbackRedirectURI)",
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.cognitoError(statusCode, errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let idToken = json?["id_token"] as? String,
              let refreshToken = json?["refresh_token"] as? String,
              let expiresIn = json?["expires_in"] as? Int else {
            throw AuthError.invalidResponse
        }

        return TokenResponse(idToken: idToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    // MARK: - Token Refresh

    private func refreshTokenIfNeeded() async {
        guard let refreshToken else {
            signOut()
            return
        }

        do {
            var request = URLRequest(url: URL(string: BackendConfig.cognitoTokenURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let params = [
                "grant_type=refresh_token",
                "client_id=\(BackendConfig.cognitoClientId)",
                "refresh_token=\(refreshToken)",
            ].joined(separator: "&")
            request.httpBody = params.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                signOut()
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let newIdToken = json?["id_token"] as? String,
                  let expiresIn = json?["expires_in"] as? Int else {
                signOut()
                return
            }

            self.idToken = newIdToken
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            saveTokensToKeychain()
        } catch {
            signOut()
        }
    }

    // MARK: - Keychain

    private func loadStoredTokens() {
        idToken = readKeychain(key: idTokenKey)
        refreshToken = readKeychain(key: refreshTokenKey)

        if let expiryString = readKeychain(key: tokenExpiryKey),
           let interval = TimeInterval(expiryString) {
            tokenExpiry = Date(timeIntervalSince1970: interval)
        }

        isAuthenticated = idToken != nil && refreshToken != nil
    }

    private func saveTokensToKeychain() {
        writeKeychain(key: idTokenKey, value: idToken ?? "")
        writeKeychain(key: refreshTokenKey, value: refreshToken ?? "")
        if let expiry = tokenExpiry {
            writeKeychain(key: tokenExpiryKey, value: String(expiry.timeIntervalSince1970))
        }
    }

    private func clearKeychain() {
        deleteKeychain(key: idTokenKey)
        deleteKeychain(key: refreshTokenKey)
        deleteKeychain(key: tokenExpiryKey)
    }

    private func writeKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Presentation Context

private class AuthSessionCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case cognitoError(Int, String)
    case invalidResponse
    case noToken

    var errorDescription: String? {
        switch self {
        case .cognitoError(let code, let body): return "Auth error \(code): \(body)"
        case .invalidResponse: return "Invalid auth response"
        case .noToken: return "No authentication token"
        }
    }
}
