//
//  PayoutView.swift
//  Tally
//
//  Created by Raghav Chalageri on 6/2/26.
//

import SwiftUI

/// Payout request screen: shows balance, amount input, Stripe Connect, and submit action.
struct PayoutView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let currentBalance: Double

    @State private var amountText: String = ""
    @State private var isRequesting = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showStripeAlert = false

    private var amount: Double {
        Double(amountText) ?? currentBalance
    }

    private var isValidAmount: Bool {
        amount > 0 && amount <= currentBalance
    }

    // Currency formatter
    private func formatCurrency(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        return fmt.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Balance header
                balanceHeader

                // Amount input
                amountInput

                // Stripe Connect
                stripeSection

                // Submit button
                submitButton

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Request Payout")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            amountText = String(format: "%.2f", currentBalance)
        }
        .alert("Stripe Connect", isPresented: $showStripeAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            // TODO: Replace with actual Stripe Connect onboarding WebView
            Text("Stripe Connect onboarding would open here. This feature is coming soon.")
        }
        .alert("Payout Requested!", isPresented: $showSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your payout of \(formatCurrency(amount)) has been submitted. You'll receive it in your Stripe account within 1–3 business days.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Balance Header

    private var balanceHeader: some View {
        VStack(spacing: 8) {
            Text("Available Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formatCurrency(currentBalance))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Amount Input

    private var amountInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payout Amount")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text("$")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("0.00", text: $amountText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            if !amountText.isEmpty && !isValidAmount {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(amount > currentBalance
                         ? "Amount exceeds available balance"
                         : "Enter a valid amount")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            Button("Use full balance") {
                amountText = String(format: "%.2f", currentBalance)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.purple)
        }
    }

    // MARK: - Stripe Section

    private var stripeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                Text("Stripe Connect")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Connect your Stripe account to receive payouts directly to your bank.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                showStripeAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Set Up Stripe Account")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.purple)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            Task { await requestPayout() }
        } label: {
            HStack {
                if isRequesting {
                    ProgressView()
                        .tint(.white)
                }
                Text("Request Payout")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isValidAmount && !isRequesting
                    ? AnyShapeStyle(LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    : AnyShapeStyle(Color.gray.opacity(0.3)),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .foregroundStyle(isValidAmount ? .white : .gray)
        }
        .disabled(!isValidAmount || isRequesting)
    }

    // MARK: - Request Payout

    private func requestPayout() async {
        guard let token = authManager.authToken else {
            errorMessage = "Not authenticated."
            showError = true
            return
        }

        isRequesting = true
        defer { isRequesting = false }

        do {
            let _ = try await APIClient.shared.requestPayout(amount: amount, token: token)
            showSuccess = true
        } catch {
            errorMessage = "Payout request failed: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    NavigationStack {
        PayoutView(currentBalance: 12.50)
            .environment(AuthManager())
    }
}
