//
//  TallyApp.swift
//  Tally
//
//  Main app entry point. Manages consent state, auth, and background upload scheduling.
//

import SwiftUI
import BackgroundTasks

@main
struct TallyApp: App {
    @State private var consentManager = ConsentManager()
    @State private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if consentManager.hasCompletedOnboarding {
                    DashboardView()
                } else {
                    OnboardingView()
                }
            }
            .environment(consentManager)
            .environment(authManager)
            .onAppear {
                registerBackgroundTasks()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Trigger an immediate upload when the app comes to foreground
                Task {
                    let service = UploadService()
                    await service.performUpload()
                }
            } else if newPhase == .background {
                UploadService.scheduleNextUpload()
            }
        }
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: UploadService.taskIdentifier,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundUpload(task: appRefreshTask)
        }
    }

    nonisolated private func handleBackgroundUpload(task: BGAppRefreshTask) {
        // Schedule the next upload before we start (in case this one fails)
        UploadService.scheduleNextUpload()

        let uploadTask = Task {
            let service = UploadService()
            await service.performUpload()
        }

        task.expirationHandler = {
            uploadTask.cancel()
        }

        Task {
            await uploadTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
