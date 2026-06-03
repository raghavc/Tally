//
//  SettingsView.swift
//  Tally
//
//  App settings, consent management, keyboard setup, and account info.
//

import SwiftUI

struct SettingsView: View {
    @Environment(ConsentManager.self) private var consentManager
    @Environment(AuthManager.self) private var authManager

    @State private var bufferedCount: Int = 0
    @State private var isUploading = false
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false
    @State private var showTermsOfService = false
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Collection Preferences
                collectionSection

                // MARK: - Keyboard Setup
                keyboardSection

                // MARK: - Account
                accountSection

                // MARK: - Debug
                debugSection

                // MARK: - Legal
                legalSection

                // MARK: - About
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear { refreshBufferedCount() }
            .alert("Log Out?", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    authManager.logout()
                    consentManager.revokeAllConsent()
                }
            } message: {
                Text("This will disable data collection and sign you out. You can sign back in anytime.")
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                privacyPolicySheet
            }
            .sheet(isPresented: $showTerms) {
                termsSheet
            }
            .sheet(isPresented: $showTermsOfService) {
                termsOfServiceSheet
            }
        }
    }

    // MARK: - Collection Preferences

    private var collectionSection: some View {
        Section {
            @Bindable var consent = consentManager

            Toggle(isOn: $consent.collectText) {
                Label("Typed Text", systemImage: "keyboard")
            }
            .tint(.green)

            Toggle(isOn: $consent.collectInputContext) {
                Label("Input Context", systemImage: "character.textbox")
            }
            .tint(.green)

            Toggle(isOn: $consent.collectTypingMetadata) {
                Label("Typing Metadata", systemImage: "gauge.with.dots.needle.33percent")
            }
            .tint(.green)
        } header: {
            Text("Collection Preferences")
        } footer: {
            Text("Changes take effect immediately. The keyboard extension reads these preferences in real-time.")
        }
    }

    // MARK: - Keyboard Setup

    private var keyboardSection: some View {
        Section("Keyboard") {
            NavigationLink {
                KeyboardSetupView()
            } label: {
                HStack {
                    Label("Keyboard Setup", systemImage: "keyboard.badge.ellipsis")
                    Spacer()
                    if isKeyboardInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Setup Required")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            if let userId = authManager.userId {
                LabeledContent("User ID") {
                    Text(userId.prefix(8) + "...")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if let token = authManager.authToken {
                LabeledContent("Auth Token") {
                    Text(String(repeating: "•", count: 16))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                showLogoutConfirmation = true
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - Debug

    private var debugSection: some View {
        Section("Debug") {
            LabeledContent("API Base URL") {
                Text("localhost:8000")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Buffered Batches") {
                Text("\(bufferedCount)")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(bufferedCount > 0 ? .blue : .secondary)
            }

            Button {
                Task { await triggerManualUpload() }
            } label: {
                HStack {
                    Label("Trigger Upload Now", systemImage: "icloud.and.arrow.up")
                    Spacer()
                    if isUploading {
                        ProgressView()
                    }
                }
            }
            .disabled(isUploading)
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Section("Legal") {
            Button {
                showTermsOfService = true
            } label: {
                Label("Terms of Service", systemImage: "doc.plaintext.fill")
            }

            Button {
                showPrivacyPolicy = true
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }

            Button {
                showTerms = true
            } label: {
                Label("Data License Agreement", systemImage: "doc.text.fill")
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Build") {
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Text("Made with ♥ by Black Beans Inc.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var isKeyboardInstalled: Bool {
        let modes = UITextInputMode.activeInputModes
        return modes.contains { mode in
            guard let identifier = mode.value(forKey: "identifier") as? String else { return false }
            return identifier.contains("com.BlackBeansInc.Tally.TallyKeyboard")
        }
    }

    private func refreshBufferedCount() {
        let db = BufferDatabase()
        bufferedCount = db.countUnuploaded()
    }

    private func triggerManualUpload() async {
        isUploading = true
        defer {
            isUploading = false
            refreshBufferedCount()
        }

        let service = UploadService()
        await service.performUpload()
    }

    // MARK: - Sheets

    private var termsOfServiceSheet: some View {
        NavigationStack {
            ScrollView {
                Text(termsOfServiceText)
                    .font(.body)
                    .padding()
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTermsOfService = false }
                }
            }
        }
    }

    private var privacyPolicySheet: some View {
        NavigationStack {
            ScrollView {
                Text(privacyPolicyText)
                    .font(.body)
                    .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showPrivacyPolicy = false }
                }
            }
        }
    }

    private var termsSheet: some View {
        NavigationStack {
            ScrollView {
                Text(dataLicenseTermsText)
                    .font(.body)
                    .padding()
            }
            .navigationTitle("Data License Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTerms = false }
                }
            }
        }
    }

    // MARK: - Policy Text

    private var termsOfServiceText: String {
        """
        TERMS OF SERVICE — Tally
        Last Updated: June 2026

        1. ACCEPTANCE OF TERMS
        By creating an account and using Tally, you agree to these Terms of Service, our Privacy Policy, and our Data License Agreement. If you do not agree, do not use the app.

        2. ELIGIBILITY
        You must be at least 18 years old and legally able to enter into a binding contract to use Tally. You are responsible for ensuring your use complies with the laws of your jurisdiction.

        3. THE SERVICE
        Tally provides a custom keyboard and companion app that, with your explicit per-category consent, collects text you type and pays you on a per-token basis. Collection only occurs while it is enabled and never in secure fields.

        4. YOUR RESPONSIBILITIES
        You agree not to: (a) type or contribute content you do not have the right to share, (b) submit unlawful, infringing, or others' personal/confidential information for compensation, or (c) attempt to defraud the payout system through automated or fabricated input. We may withhold payment for activity that violates these terms.

        5. COMPENSATION & PAYOUTS
        Earnings accrue at the per-token rate shown in the app at the time of collection and are paid via Stripe Connect. You are responsible for any taxes on amounts you receive. Rates may change with 30 days notice.

        6. CONSENT & WITHDRAWAL
        Your participation is voluntary. You may pause collection, change category consent, export, or delete your data at any time from within the app, without penalty.

        7. TERMINATION
        You may stop using Tally and delete your data at any time. We may suspend or terminate accounts that violate these terms or applicable law.

        8. DISCLAIMERS & LIABILITY
        The service is provided "as is." To the maximum extent permitted by law, Black Beans Inc. is not liable for indirect or consequential damages arising from your use of the app.

        9. CHANGES
        We may update these terms and will notify you of material changes at least 30 days in advance via in-app notification.

        10. CONTACT
        Questions: legal@blackbeansinc.com
        """
    }

    private var privacyPolicyText: String {
        """
        PRIVACY POLICY — Tally
        Last Updated: June 2026

        1. DATA WE COLLECT
        When you enable data collection, Tally's keyboard extension may collect: (a) the text you type in non-secure input fields, (b) coarse input context describing the TYPE of field you are typing in (for example "email", "url", or "number") — never the app you are using or its contents, and (c) typing speed metrics such as words-per-minute and backspace rate. Each category is independently toggleable.

        2. DATA WE NEVER COLLECT
        Tally NEVER collects text from secure input fields (passwords, credit card numbers, etc.). The keyboard checks every field for the isSecureTextEntry flag before any capture occurs.

        3. HOW YOUR DATA IS USED
        Your anonymized typing data is aggregated and licensed to artificial intelligence research laboratories as training data for language models. Your data is never sold to advertisers or used for targeted advertising.

        4. HOW YOU ARE COMPENSATED
        You are paid per token of text contributed at the current rate displayed in the app. Payouts are processed via Stripe Connect to your linked bank account.

        5. DATA STORAGE & SECURITY
        Data is buffered locally on your device in an encrypted App Group container and transmitted to our servers over TLS 1.3. Server-side data is stored in encrypted object storage with access controls.

        6. YOUR RIGHTS (GDPR/CCPA)
        You may at any time: pause collection, export all your data in machine-readable format, or permanently delete all your data from our servers. These controls are available in the Data Controls section of the app.

        7. DATA RETENTION
        Your data is retained for the duration of active AI training contracts. Upon deletion request, all data is purged within 30 days from all systems including backups.

        8. THIRD-PARTY SHARING
        Data is shared only with vetted AI research partners under strict data processing agreements. We do not share data with advertisers, data brokers, or social media platforms.

        9. CHANGES TO THIS POLICY
        We will notify you of material changes via in-app notification at least 30 days before they take effect. Continued use after notification constitutes acceptance.

        10. CONTACT
        For privacy inquiries: privacy@blackbeansinc.com
        """
    }

    private var dataLicenseTermsText: String {
        """
        DATA LICENSE TERMS — Tally
        Last Updated: June 2026

        By enabling data collection in Tally, you grant Black Beans Inc. a non-exclusive, worldwide, perpetual license to use, process, aggregate, and sublicense your contributed typing data for the purpose of training artificial intelligence and machine learning models.

        COMPENSATION: You will be compensated at the rate displayed in the app for each token of text contributed. Rates may change with 30 days notice.

        REVOCATION: You may revoke this license at any time by deleting your data through the app. Upon deletion, no new use of your data will occur, though data already incorporated into trained models cannot be individually extracted.

        ANONYMIZATION: All data is stripped of personally identifiable information before being shared with AI research partners. Your user ID is replaced with a random identifier.

        LIABILITY: Black Beans Inc. is not liable for the content of text you type. You represent that you have the right to contribute the text you type and that it does not infringe on third-party rights.
        """
    }
}
