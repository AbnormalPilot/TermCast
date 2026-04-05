// apps/ios/TermCastiOSUITests/OnboardingUITests.swift
import XCTest

final class OnboardingUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitest-reset-credentials"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testLaunchShowsQRScanScreen() throws {
        // With no credentials, app starts in onboarding — QR scan screen must appear
        let scanLabel = app.staticTexts["Scan the QR code shown on your Mac"]
        XCTAssertTrue(scanLabel.waitForExistence(timeout: 5),
                      "QR scan prompt should be visible on first launch without credentials")
    }

    func testCameraOrFallbackIsVisible() throws {
        // Either camera preview or "Camera unavailable" fallback must be visible
        // (simulator has no camera → fallback fires)
        let cameraFallback = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Camera'")
        ).firstMatch
        let scanPrompt = app.staticTexts["Scan the QR code shown on your Mac"]

        let visible = cameraFallback.waitForExistence(timeout: 5) || scanPrompt.exists
        XCTAssertTrue(visible, "Either scan prompt or camera fallback should be visible on launch")
    }

    func testAppDoesNotCrashOnLaunch() throws {
        // Simply verify the app reaches foreground without crashing
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
