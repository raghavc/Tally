//
//  EarningsView.swift
//  Tally
//
//  Rich earnings dashboard showing balance, stats, payout history.
//

import SwiftUI

struct EarningsView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var earnings: EarningsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private func formatCurrency(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 4
        return fmt.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                statsGrid
                payoutButton
                payoutHistorySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Earnings")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await loadEarnings() }
        .task { await loadEarnings() }
    }

    // MARK: - Hero Balance Card

    private var heroCard: some View {
        VStack(spacing: 12) {
            Text("Current Balance")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            if isLoading && earnings == nil {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                    .frame(height: 50)
            } else {
                Text(formatCurrency(earnings?.balance ?? 0))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: earnings?.balance ?? 0))
            }

            if let earnings, earnings.balance > 0 {
                Text("Available for payout")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(
            LinearGradient(
                colors: [
                    Color(hue: 0.76, saturation: 0.7, brightness: 0.65),
                    Color(hue: 0.84, saturation: 0.6, brightness: 0.50)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .purple.opacity(0.2), radius: 12, y: 6)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            statCell(
                title: "Tokens",
                value: earnings.map { formatCount($0.tokenCount) } ?? "—",
                icon: "text.word.spacing",
                color: .blue
            )
            statCell(
                title: "Lifetime",
                value: earnings.map { formatCurrency($0.lifetimeEarnings) } ?? "—",
                icon: "chart.line.uptrend.xyaxis",
                color: .green
            )
            statCell(
                title: "Rate",
                value: earnings.map { "$\(String(format: "%.4f", $0.payRate))/tok" } ?? "$0.0003/tok",
                icon: "gauge.open.with.lines.needle.33percent",
                color: .orange
            )
        }
    }

    private func statCell(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Payout Button

    private var payoutButton: some View {
        NavigationLink {
            PayoutView(currentBalance: earnings?.balance ?? 0)
        } label: {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                Text("Request Payout")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.green)
        }
        .disabled(earnings == nil || (earnings?.balance ?? 0) <= 0)
        .opacity(earnings == nil || (earnings?.balance ?? 0) <= 0 ? 0.5 : 1)
    }

    // MARK: - Payout History

    private var payoutHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payout History")
                .font(.headline)
                .padding(.leading, 4)

            if let payouts = earnings?.payoutHistory, !payouts.isEmpty {
                ForEach(payouts) { payout in
                    payoutRow(payout)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No payouts yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
    }

    private func payoutRow(_ payout: PayoutRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatCurrency(payout.amount))
                    .font(.subheadline.weight(.semibold))
                if let requestedAt = payout.requestedAt {
                    Text(requestedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge(payout.status)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusBadge(_ status: String) -> some View {
        let (color, icon): (Color, String) = {
            switch status.lowercased() {
            case "completed": return (.green, "checkmark.circle.fill")
            case "pending": return (.yellow, "clock.fill")
            case "failed": return (.red, "xmark.circle.fill")
            default: return (.gray, "questionmark.circle.fill")
            }
        }()

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(status.capitalized)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Data Loading

    private func loadEarnings() async {
        guard let token = authManager.authToken else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            earnings = try await APIClient.shared.getEarnings(token: token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    NavigationStack {
        EarningsView()
            .environment(AuthManager())
    }
}
