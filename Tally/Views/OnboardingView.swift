//
//  OnboardingView.swift
//  Tally
//
//  Created by Raghav Chalageri on 6/2/26.
//

import SwiftUI

/// Multi-step onboarding flow that educates the user about Tally,
/// collects consent, and gets them started.
struct OnboardingView: View {

    @Environment(ConsentManager.self) private var consentManager
    @Environment(AuthManager.self) private var authManager

    @State private var currentPage = 0
    @State private var hasAcceptedTerms = false
    @State private var isCreatingAccount = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let totalPages = 6
    private let accentGradient = LinearGradient(
        colors: [Color(hue: 0.76, saturation: 0.65, brightness: 0.95),
                 Color(hue: 0.85, saturation: 0.55, brightness: 0.90)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    Color(hue: 0.72 + Double(currentPage) * 0.03, saturation: 0.15, brightness: 0.12),
                    Color(hue: 0.80 + Double(currentPage) * 0.02, saturation: 0.20, brightness: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)

            VStack(spacing: 0) {
                // Page indicator
                pageIndicator
                    .padding(.top, 16)

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    whatWeCollectPage.tag(1)
                    whatWeNeverCollectPage.tag(2)
                    howYouGetPaidPage.tag(3)
                    yourControlsPage.tag(4)
                    privacyTermsPage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: currentPage)

                // Bottom button
                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.35), value: currentPage)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        Group {
            if currentPage < totalPages - 1 {
                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    HStack {
                        Text("Continue")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentGradient, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                }
            } else {
                Button {
                    Task { await finishOnboarding() }
                } label: {
                    HStack {
                        if isCreatingAccount {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Get Started")
                            .fontWeight(.bold)
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        canFinish
                            ? AnyShapeStyle(accentGradient)
                            : AnyShapeStyle(Color.gray.opacity(0.3)),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(canFinish ? .white : .gray)
                }
                .disabled(!canFinish || isCreatingAccount)
            }
        }
    }

    private var canFinish: Bool {
        hasAcceptedTerms && consentManager.collectText
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accentGradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: .purple.opacity(0.4), radius: 30)

                Image(systemName: "keyboard.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating)
            }

            Text("Welcome to Tally")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Earn real money from your everyday typing.\nYour keystrokes have value — we help you\ncapture it safely and transparently.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Page 2: What We Collect

    private var whatWeCollectPage: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("What We Collect")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 16) {
                collectItem(
                    icon: "character.cursor.ibeam",
                    color: .blue,
                    title: "Typed Text",
                    subtitle: "The words you type — anonymized and batched"
                )
                collectItem(
                    icon: "character.textbox",
                    color: .indigo,
                    title: "Input Context",
                    subtitle: "The kind of field — e.g. email, search, or URL"
                )
                collectItem(
                    icon: "gauge.medium",
                    color: .purple,
                    title: "Typing Metadata",
                    subtitle: "Speed, rhythm, and session patterns"
                )
            }
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func collectItem(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Page 3: What We Never Collect

    private var whatWeNeverCollectPage: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "shield.checkered")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse, options: .repeating)
            }

            Text("What We Never Collect")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 14) {
                neverItem(icon: "key.fill", text: "Passwords & Secure Fields")
                neverItem(icon: "banknote.fill", text: "Banking & Financial Information")
                neverItem(icon: "creditcard.fill", text: "Credit Card Numbers")
                neverItem(icon: "heart.text.clipboard.fill", text: "Health or Biometric Data")
            }
            .padding(.horizontal, 20)

            Text("Secure text fields are automatically detected\nand completely skipped.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func neverItem(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)

            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)

            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Page 4: How You Get Paid

    private var howYouGetPaidPage: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.5), Color.mint.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }

            Text("How You Get Paid")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 16) {
                payItem(icon: "text.word.spacing", title: "Per-Token Model", detail: "You earn for every token of text you contribute")
                payItem(icon: "dollarsign", title: "Current Rate", detail: "$0.0003 per token")
                payItem(icon: "arrow.right.arrow.left", title: "Stripe Payouts", detail: "Direct to your bank via Stripe Connect")
            }
            .padding(.horizontal, 20)

            // Example earnings card
            VStack(spacing: 8) {
                Text("Example Earnings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))

                HStack(alignment: .firstTextBaseline) {
                    Text("10,000 tokens")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.green)
                    Text("$3.00")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.green.opacity(0.15), Color.mint.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func payItem(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Page 5: Your Controls

    private var yourControlsPage: some View {
        @Bindable var cm = consentManager

        return VStack(spacing: 28) {
            Spacer()

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 44))
                .foregroundStyle(accentGradient)

            Text("Your Controls")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Choose exactly what we collect.\nYou can change these any time in Settings.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                consentToggle(
                    icon: "power",
                    title: "Enable Collection",
                    subtitle: "Master switch for all data collection",
                    isOn: $cm.isCollectionActive,
                    tint: .green
                )

                consentToggle(
                    icon: "character.cursor.ibeam",
                    title: "Typed Text",
                    subtitle: "The words you type",
                    isOn: $cm.collectText,
                    tint: .blue
                )

                consentToggle(
                    icon: "character.textbox",
                    title: "Input Context",
                    subtitle: "The type of field (email, URL…) — never the app",
                    isOn: $cm.collectInputContext,
                    tint: .indigo
                )

                consentToggle(
                    icon: "gauge.medium",
                    title: "Typing Metadata",
                    subtitle: "Speed and rhythm data",
                    isOn: $cm.collectTypingMetadata,
                    tint: .purple
                )
            }
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func consentToggle(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        tint: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Page 6: Privacy & Terms

    private var privacyTermsPage: some View {
        VStack(spacing: 16) {
            Text("Privacy & Terms")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Terms of Service")
                    termsOfServiceText

                    Divider().overlay(Color.white.opacity(0.1))

                    sectionHeader("Privacy Policy")
                    privacyPolicyText

                    Divider().overlay(Color.white.opacity(0.1))

                    sectionHeader("Data License Agreement")
                    dataLicenseText
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            // Acceptance toggle
            HStack(spacing: 12) {
                Toggle(isOn: $hasAcceptedTerms) {
                    Text("I have read and agree to the Terms of Service, Privacy Policy, and Data License Agreement")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .tint(.green)
            }
            .padding(.horizontal, 24)

            if !consentManager.collectText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Enable \"Typed Text\" collection on the previous page to continue.")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.8))
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private var termsOfServiceText: some View {
        Text("""
        These Terms of Service govern your use of the Tally keyboard and companion app, \
        operated by Black Beans Inc. By creating an account you confirm that you are at least \
        18 years old and agree to these terms, the Privacy Policy, and the Data License \
        Agreement below.

        **The Service**: Tally lets you earn compensation, on a per-token basis, for text you \
        choose to contribute through our keyboard. Collection happens only while you have it \
        enabled and never in secure fields such as passwords or payment forms.

        **Your Responsibilities**: You agree not to contribute content you do not have the right \
        to share, others' confidential information, or fabricated/automated input intended to \
        defraud the payout system. We may withhold compensation for activity that violates \
        these terms.

        **Compensation**: Earnings accrue at the per-token rate shown in the app at the time of \
        collection and are paid via Stripe Connect. You are responsible for any applicable taxes.

        **Voluntary Participation**: Your participation is entirely voluntary. You may pause \
        collection, change your consent, export, or delete your data at any time, without \
        penalty.

        **Termination & Changes**: You may stop using Tally at any time. We may suspend accounts \
        that violate these terms, and will give at least 30 days notice of material changes.

        **Contact**: legal@tallykeys.com
        """)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .lineSpacing(3)
    }

    private var privacyPolicyText: some View {
        Text("""
        Tally ("we," "us," or "our") is committed to protecting your privacy. This policy \
        explains how we collect, use, and safeguard your data when you use the Tally keyboard \
        extension and companion app.

        **Data Collection**: We collect typed text, coarse input context (the type of field \
        you are typing in, such as "email" or "url" — never the app you are using or its \
        contents), and typing metadata (keystroke speed, session length) only when collection \
        is enabled and you have granted explicit consent for each data category. Secure text \
        fields (passwords, credit cards) are automatically detected and never recorded.

        **Data Processing**: Your data is batched on-device, encrypted in transit via TLS 1.3, \
        and transmitted to our secure servers. We process your data to generate anonymized, \
        aggregated linguistic datasets that are licensed to AI research labs and language-model \
        developers.

        **Third-Party Sharing**: Anonymized and aggregated datasets may be shared with \
        third-party AI labs under strict data-use agreements. We never sell raw, identifiable \
        keystroke data. Third parties receive only tokenized, de-identified batches.

        **Data Retention**: Raw keystroke batches are retained for a maximum of 90 days after \
        upload, after which they are permanently deleted. Aggregated, anonymized datasets may \
        be retained indefinitely.

        **Your Rights (GDPR / CCPA)**: You have the right to access, export, correct, and \
        delete your personal data at any time through the Data Controls section of the app. \
        You may revoke consent and stop collection instantly. California residents may opt out \
        of the "sale" of personal information; EU residents may exercise rights under GDPR \
        Articles 15–22.

        **Data Security**: All data is encrypted at rest (AES-256) and in transit (TLS 1.3). \
        Access to production systems is restricted to authorized personnel with multi-factor \
        authentication.

        **Changes to This Policy**: We will notify you of material changes via an in-app \
        prompt at least 30 days before they take effect.

        **Contact**: privacy@tallykeys.com
        """)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .lineSpacing(3)
    }

    private var dataLicenseText: some View {
        Text("""
        By using Tally, you grant Black Beans Inc. a non-exclusive, worldwide, royalty-bearing \
        license to collect, process, anonymize, and sublicense your contributed typing data for \
        the purpose of training and improving artificial intelligence and natural-language \
        processing systems. You retain the right to revoke this license at any time by deleting \
        your data through the app, which will remove all identifiable data from our systems \
        within 30 days. Compensation is provided at the prevailing per-token rate displayed in \
        the app at the time of collection.
        """)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .lineSpacing(3)
    }

    // MARK: - Finish Onboarding

    private func finishOnboarding() async {
        isCreatingAccount = true
        defer { isCreatingAccount = false }

        do {
            let userId = UUID().uuidString
            let response = try await APIClient.shared.authenticate(userId: userId)
            authManager.login(token: response.token, userId: userId)
            consentManager.hasAcceptedTerms = true
            // Respect the per-category choices the user made on the "Your Controls"
            // page — those toggles already wrote through to consentManager. We only
            // flip the master switch on (collectText is guaranteed by `canFinish`).
            consentManager.isCollectionActive = true
            consentManager.hasCompletedOnboarding = true
        } catch {
            errorMessage = "Failed to create account: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    OnboardingView()
        .environment(ConsentManager())
        .environment(AuthManager())
}
