//
//  UploadService.swift
//  Tally
//
//  Handles background upload of buffered keyboard data.
//  Reads unuploaded batches from the shared App Group database,
//  chunks them into API-sized payloads, and marks them as uploaded on success.
//

import Foundation
import BackgroundTasks

final class UploadService: Sendable {

    static let taskIdentifier = "com.BlackBeansInc.Tally.upload"

    // MARK: - BGTaskScheduler

    /// Schedules the next background upload ~15 minutes from now.
    static func scheduleNextUpload() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[UploadService] Failed to schedule next upload: \(error)")
        }
    }

    // MARK: - Upload Logic

    /// Performs a single upload pass: fetch unuploaded → chunk → POST → mark uploaded → clean up.
    ///
    /// `nonisolated` so the blocking SQLite reads/writes and network work run off the
    /// main actor (the app builds with default `MainActor` isolation). Auth lives on the
    /// main actor, so we hop there once up front just to read the credentials.
    nonisolated func performUpload() async {
        let credentials: (token: String, userId: String)? = await MainActor.run {
            let authManager = AuthManager()
            guard authManager.isAuthenticated,
                  let token = authManager.authToken,
                  let userId = authManager.userId else {
                return nil
            }
            return (token, userId)
        }

        guard let (token, userId) = credentials else {
            print("[UploadService] Not authenticated — skipping upload.")
            return
        }

        let db = BufferDatabase()
        let maxBatchesPerRequest = 50

        let unuploaded = db.fetchUnuploaded()

        guard !unuploaded.isEmpty else {
            print("[UploadService] No unuploaded batches.")
            return
        }

        // Chunk into groups of maxBatchesPerRequest
        let chunks = stride(from: 0, to: unuploaded.count, by: maxBatchesPerRequest).map {
            Array(unuploaded[$0..<min($0 + maxBatchesPerRequest, unuploaded.count)])
        }

        for chunk in chunks {
            do {
                let _ = try await APIClient.shared.postIngest(
                    batches: chunk,
                    userId: userId,
                    token: token
                )

                // Mark as uploaded on success
                let ids = chunk.compactMap(\.id)
                db.markUploaded(ids: ids)
            } catch {
                // On failure, leave batches in DB for the next attempt
                print("[UploadService] Chunk upload failed: \(error)")
            }
        }

        // Clean up already-uploaded rows to save space
        db.deleteUploaded()
    }
}
