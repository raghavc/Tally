import Foundation

@Observable
final class AuthManager {

    // MARK: - Shared UserDefaults

    private let defaults = UserDefaults(suiteName: "group.com.BlackBeansInc.Tally")!

    // MARK: - Keys

    private enum Key {
        static let authToken = "auth_token"
        static let userId = "user_id"
    }

    // MARK: - Properties

    var authToken: String? {
        get { defaults.string(forKey: Key.authToken) }
        set { defaults.set(newValue, forKey: Key.authToken) }
    }

    var userId: String? {
        get { defaults.string(forKey: Key.userId) }
        set { defaults.set(newValue, forKey: Key.userId) }
    }

    var isAuthenticated: Bool {
        authToken != nil
    }

    // MARK: - Methods

    func login(token: String, userId: String) {
        self.authToken = token
        self.userId = userId
    }

    func logout() {
        authToken = nil
        userId = nil
    }
}
