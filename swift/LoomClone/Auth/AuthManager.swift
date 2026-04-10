import Foundation
import AppKit

@Observable
final class AuthManager {
    private(set) var pendingSessionToken: String?
    private(set) var isSignedIn: Bool

    init() {
        let settings = AWSSettingsStorage.load()
        isSignedIn = !settings.apiKey.isEmpty
    }

    func signIn() {
        let settings = AWSSettingsStorage.load()
        guard !settings.apiBaseURL.isEmpty else { return }

        let sessionToken = UUID().uuidString
        pendingSessionToken = sessionToken

        let baseURL = settings.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/auth/device-login?session_token=\(sessionToken)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func handleCallback(url: URL) {
        guard url.scheme == "reclip",
              url.host == "auth",
              url.path == "/callback" || url.path == "callback" else {
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return
        }

        let apiKey = queryItems.first(where: { $0.name == "api_key" })?.value
        let sessionToken = queryItems.first(where: { $0.name == "session_token" })?.value

        guard let apiKey, !apiKey.isEmpty else { return }

        // Verify session token matches the pending one
        guard let sessionToken, sessionToken == pendingSessionToken else { return }

        var settings = AWSSettingsStorage.load()
        settings.apiKey = apiKey
        AWSSettingsStorage.save(settings)

        isSignedIn = true
        pendingSessionToken = nil
    }

    func signOut() {
        var settings = AWSSettingsStorage.load()
        settings.apiKey = ""
        AWSSettingsStorage.save(settings)
        isSignedIn = false
        pendingSessionToken = nil
    }
}
