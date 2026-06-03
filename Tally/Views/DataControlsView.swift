//
//  DataControlsView.swift
//  Tally
//
//  GDPR/CCPA compliant data controls
//

import SwiftUI

struct DataControlsView: View {
    @Environment(ConsentManager.self) private var consentManager
    @Environment(AuthManager.self) private var authManager

    @State private var bufferedCount: Int = 0
    @State private var contributedTokens: Int = 0
    @State private var isExporting = false
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var showExportSheet = false
    @State private var exportJSON: String = ""
    @State private var showSuccessMessage = false
    @State private var successMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Collection Status Card
                    collectionStatusCard

                    // MARK: - Contributed + Buffered
                    contributedCard
                    bufferedDataCard

                    // MARK: - Data Actions
                    dataActionsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Data Controls")
            .onAppear {
                refreshBufferedCount()
                Task { await refreshContributed() }
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    Task { await performDelete() }
                }
            } message: {
                Text("This will permanently delete all your data from our servers and clear your local buffer. This action cannot be undone.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showExportSheet) {
                exportView
            }
            .overlay {
                if showSuccessMessage {
                    successBanner
                }
            }
        }
    }

    // MARK: - Collection Status Card

    private var collectionStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: consentManager.isCollectionActive ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(consentManager.isCollectionActive ? .green : .orange)
                    .symbolEffect(.pulse, isActive: consentManager.isCollectionActive)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Collection Status")
                        .font(.headline)
                    Text(consentManager.isCollectionActive ? "Active — keyboard is collecting data" : "Paused — no data is being collected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !consentManager.isCollectionActive {
                    Text("PAUSED")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            @Bindable var consent = consentManager
            Toggle("Enable Data Collection", isOn: $consent.isCollectionActive)
                .tint(.green)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Contributed Card

    private var contributedCard: some View {
        HStack {
            Image(systemName: "text.word.spacing")
                .font(.title2)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tokens Contributed")
                    .font(.headline)
                Text("Total text you've contributed so far")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(contributedTokens)")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(.purple)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Buffered Data Card

    private var bufferedDataCard: some View {
        HStack {
            Image(systemName: "tray.full.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pending Upload")
                    .font(.headline)
                Text(bufferedCount == 0
                     ? "All caught up — nothing waiting"
                     : "\(bufferedCount) batches waiting to upload")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(bufferedCount)")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(bufferedCount == 0 ? Color.secondary : Color.blue)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Data Actions

    private var dataActionsSection: some View {
        VStack(spacing: 12) {
            Text("Your Data Rights")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Export
            Button {
                Task { await performExport() }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export My Data")
                            .font(.subheadline.bold())
                        Text("Download all your data as JSON")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

            // Delete
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete All My Data")
                            .font(.subheadline.bold())
                        Text("Permanently erase from servers & device")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    Spacer()
                    if isDeleting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "chevron.right")
                            .opacity(0.6)
                    }
                }
                .padding()
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.red.gradient)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
    }

    // MARK: - Export View

    private var exportView: some View {
        NavigationStack {
            ScrollView {
                Text(exportJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Exported Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showExportSheet = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: exportJSON) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Success Banner

    private var successBanner: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text(successMessage)
                    .font(.subheadline.bold())
            }
            .padding()
            .background(.green.gradient)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.5), value: showSuccessMessage)
    }

    // MARK: - Actions

    private func refreshBufferedCount() {
        let db = BufferDatabase()
        bufferedCount = db.countUnuploaded()
    }

    private func refreshContributed() async {
        guard let token = authManager.authToken else { return }
        if let earnings = try? await APIClient.shared.getEarnings(token: token) {
            contributedTokens = earnings.tokenCount
        }
    }

    private func performExport() async {
        guard let token = authManager.authToken else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await APIClient.shared.exportData(token: token)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(data)
            exportJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
            showExportSheet = true
        } catch {
            errorMessage = "Failed to export data: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func performDelete() async {
        guard let token = authManager.authToken else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            _ = try await APIClient.shared.deleteData(token: token)
            BufferDatabase().deleteAll()
            refreshBufferedCount()
            contributedTokens = 0

            successMessage = "All data deleted successfully"
            showSuccessMessage = true
            try? await Task.sleep(for: .seconds(3))
            showSuccessMessage = false
        } catch {
            errorMessage = "Failed to delete data: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}
