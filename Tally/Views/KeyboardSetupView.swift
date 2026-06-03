//
//  KeyboardSetupView.swift
//  Tally
//
//  Created by Raghav Chalageri on 6/2/26.
//

import SwiftUI
import UIKit

/// Step-by-step guide to install and enable the Tally keyboard extension.
struct KeyboardSetupView: View {

    @State private var isKeyboardInstalled = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header
                headerSection

                // Steps
                stepCard(
                    number: 1,
                    icon: "gear",
                    title: "Open Settings",
                    description: "Tap the button below to jump to your device's keyboard settings.",
                    actionLabel: "Open Settings",
                    action: openSettings,
                    status: nil
                )

                stepCard(
                    number: 2,
                    icon: "keyboard",
                    title: "Add Tally Keyboard",
                    description: "Navigate to Keyboards → Add New Keyboard, then select \"Tally\" from the third-party list.",
                    actionLabel: nil,
                    action: nil,
                    status: isKeyboardInstalled ? .done : .pending
                )

                stepCard(
                    number: 3,
                    icon: "lock.shield",
                    title: "Enable Full Access",
                    description: "Tap \"Tally\" in your keyboard list, then toggle on \"Allow Full Access\". This is required so we can securely buffer your typing data.",
                    actionLabel: nil,
                    action: nil,
                    status: nil
                )

                // Full Access warning
                fullAccessWarning

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Keyboard Setup")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { checkKeyboardInstalled() }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "keyboard.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            }

            Text("Set Up Your Keyboard")
                .font(.title2.weight(.bold))

            Text("Follow these steps to start earning from your typing data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private func stepCard(
        number: Int,
        icon: String,
        title: String,
        description: String,
        actionLabel: String?,
        action: (() -> Void)?,
        status: StepStatus?
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // Step number badge
                ZStack {
                    Circle()
                        .fill(statusColor(status))
                        .frame(width: 36, height: 36)

                    if status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.purple)

                Text(title)
                    .font(.headline)

                Spacer()

                if let status {
                    Text(status == .done ? "Done" : "Pending")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status == .done ? .green : .orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(status == .done ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        )
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionLabel, let action {
                Button(action: action) {
                    HStack {
                        Image(systemName: "arrow.up.forward.app")
                        Text(actionLabel)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var fullAccessWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Why Full Access?")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Full Access allows the Tally keyboard to write collected text to a secure, on-device shared container (App Group). Without it, the keyboard cannot store any data. We never access contacts, location, or other personal data through Full Access.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private enum StepStatus {
        case done, pending
    }

    private func statusColor(_ status: StepStatus?) -> Color {
        switch status {
        case .done: return .green
        case .pending: return .orange
        case nil: return .purple
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Best-effort check: inspects active input modes for our keyboard bundle ID.
    private func checkKeyboardInstalled() {
        let modes = UITextInputMode.activeInputModes
        isKeyboardInstalled = modes.contains { mode in
            guard let id = mode.value(forKey: "identifier") as? String else { return false }
            return id.contains("com.BlackBeansInc.Tally")
        }
    }
}

#Preview {
    NavigationStack {
        KeyboardSetupView()
    }
}
