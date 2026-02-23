import Foundation

/// Backend configuration — API Gateway + Cognito endpoints.
/// Values are injected at build time via xcconfig (same pattern as the old API key).
enum BackendConfig {
    // MARK: - API Endpoints

    /// API Gateway base URL (from CDK output `ApiUrl`)
    static let apiBaseURL: String = {
        let host = Bundle.main.infoDictionary?["MacPhotoApiHost"] as? String ?? ""
        return host.isEmpty ? "https://PLACEHOLDER.execute-api.us-east-1.amazonaws.com" : "https://\(host)"
    }()

    /// Chat Lambda Function URL for SSE streaming (from CDK output `ChatStreamUrl`)
    static let chatStreamURL: String = {
        let host = Bundle.main.infoDictionary?["MacPhotoChatHost"] as? String ?? ""
        return host.isEmpty ? "https://PLACEHOLDER.lambda-url.us-east-1.on.aws" : "https://\(host)"
    }()

    // MARK: - Cognito

    /// Cognito User Pool ID (from CDK output `UserPoolId`)
    static let cognitoUserPoolId: String = {
        Bundle.main.infoDictionary?["CognitoUserPoolId"] as? String ?? ""
    }()

    /// Cognito User Pool Client ID (from CDK output `UserPoolClientId`)
    static let cognitoClientId: String = {
        Bundle.main.infoDictionary?["CognitoClientId"] as? String ?? ""
    }()

    /// Cognito region
    static let cognitoRegion = "us-east-1"

    /// Cognito hosted UI domain (for OAuth2 code flow)
    static var cognitoDomainURL: String {
        "https://macphoto-auth.auth.\(cognitoRegion).amazoncognito.com"
    }

    /// Cognito OAuth2 token endpoint
    static var cognitoTokenURL: String {
        "\(cognitoDomainURL)/oauth2/token"
    }

    // MARK: - Status

    static var isConfigured: Bool {
        !cognitoUserPoolId.isEmpty
            && !cognitoClientId.isEmpty
            && !apiBaseURL.contains("PLACEHOLDER")
    }
}
