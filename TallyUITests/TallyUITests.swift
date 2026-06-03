//
//  TallyUITests.swift
//  TallyUITests
//
//  Created by Raghav Chalageri on 6/2/26.
//

import XCTest

final class TallyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Walks the full onboarding flow, accepts the legal agreements, finishes
    /// (which calls the auth API), and screenshots every screen + the dashboard.
    @MainActor
    func testOnboardingWalkthrough() throws {
        let app = XCUIApplication()
        app.launch()

        snap(app, "00-initial")

        // Advance through the onboarding pages via the Continue button.
        for i in 0..<6 {
            let cont = app.buttons["Continue"]
            guard cont.waitForExistence(timeout: 3), cont.isHittable else { break }
            cont.tap()
            usleep(900_000)
            snap(app, "page-\(i + 2)")
        }

        // Legal page: flip the acceptance switch (last switch on screen).
        let switches = app.switches
        if switches.count > 0 {
            let accept = switches.element(boundBy: switches.count - 1)
            if accept.waitForExistence(timeout: 3) { accept.tap() }
        }
        snap(app, "legal-accepted")

        // Finish onboarding (this hits POST /auth/token).
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 3) {
            getStarted.tap()
            // Allow time for the network round-trip and transition.
            sleep(4)
            snap(app, "after-get-started")
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
