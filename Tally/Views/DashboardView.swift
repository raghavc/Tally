//
//  DashboardView.swift
//  Tally
//
//  Created by Raghav Chalageri on 6/2/26.
//

import SwiftUI

/// Root dashboard shown after onboarding.
/// Three-tab layout: Earnings · Data · Settings.
struct DashboardView: View {

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Earnings", systemImage: "chart.bar.fill", value: 0) {
                NavigationStack {
                    EarningsView()
                }
            }

            Tab("Data", systemImage: "lock.shield.fill", value: 1) {
                NavigationStack {
                    DataControlsView()
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(Color(hue: 0.78, saturation: 0.7, brightness: 0.95))
    }
}

#Preview {
    DashboardView()
        .environment(ConsentManager())
        .environment(AuthManager())
}
