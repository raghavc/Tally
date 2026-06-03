import Foundation

@Observable
final class ConsentManager {

    // MARK: - Shared UserDefaults

    private let defaults = UserDefaults(suiteName: "group.com.BlackBeansInc.Tally")!

    // MARK: - Keys

    private enum Key {
        static let collectionActive = "collection_active"
        static let collectText = "collect_text"
        static let collectInputContext = "collect_input_context"
        static let collectTypingMetadata = "collect_typing_metadata"
        static let hasCompletedOnboarding = "has_completed_onboarding"
        static let hasAcceptedTerms = "has_accepted_terms"
    }

    // MARK: - Properties

    var isCollectionActive: Bool {
        get { defaults.bool(forKey: Key.collectionActive) }
        set { defaults.set(newValue, forKey: Key.collectionActive) }
    }

    var collectText: Bool {
        get { defaults.bool(forKey: Key.collectText) }
        set { defaults.set(newValue, forKey: Key.collectText) }
    }

    /// Consent to record coarse, non-identifying context about the *type* of field
    /// being typed in (e.g. "email", "url", "number") — never the host app or its contents.
    var collectInputContext: Bool {
        get { defaults.bool(forKey: Key.collectInputContext) }
        set { defaults.set(newValue, forKey: Key.collectInputContext) }
    }

    var collectTypingMetadata: Bool {
        get { defaults.bool(forKey: Key.collectTypingMetadata) }
        set { defaults.set(newValue, forKey: Key.collectTypingMetadata) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    var hasAcceptedTerms: Bool {
        get { defaults.bool(forKey: Key.hasAcceptedTerms) }
        set { defaults.set(newValue, forKey: Key.hasAcceptedTerms) }
    }

    // MARK: - Convenience

    /// Revokes all consent flags and deactivates collection.
    func revokeAllConsent() {
        isCollectionActive = false
        collectText = false
        collectInputContext = false
        collectTypingMetadata = false
        hasCompletedOnboarding = false
        hasAcceptedTerms = false
    }
}
