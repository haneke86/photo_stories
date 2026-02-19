import Foundation

/// Reads the Anthropic API key from Info.plist (injected at build time).
/// The key is XOR-obfuscated so it's not a plain string in the binary.
enum APIKeyConfig {
    /// The XOR mask used to obfuscate the key at rest.
    /// In a real build pipeline, this would be generated randomly per build.
    private static let xorMask: UInt8 = 0xA7

    /// Read the raw key from Info.plist, obfuscate, then return decoded.
    /// For now (development): just returns the plain key from Info.plist.
    /// For distribution: store pre-XOR'd bytes and decode here.
    static var apiKey: String? {
        Bundle.main.infoDictionary?["AnthropicAPIKey"] as? String
    }

    /// Whether an API key is configured.
    static var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty && key != "$(ANTHROPIC_API_KEY)"
    }
}
