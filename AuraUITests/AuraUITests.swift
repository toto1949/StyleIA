import XCTest

final class AuraUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAuthenticationModeAndValidation() throws {
        let app = launchAuthentication()

        XCTAssertTrue(app.buttons["auth.apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["auth.email"].exists)
        XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        XCTAssertFalse(app.buttons["auth.submit"].isEnabled)

        app.buttons["auth.mode.signUp"].tap()
        XCTAssertTrue(app.textFields["auth.fullName"].waitForExistence(timeout: 2))
        // Switch back before typing so iOS's generated-new-password overlay
        // cannot swallow synthetic SecureField input in the simulator.
        app.buttons["auth.mode.signIn"].tap()
        XCTAssertFalse(app.textFields["auth.fullName"].waitForExistence(timeout: 1))

        app.textFields["auth.email"].tap()
        app.textFields["auth.email"].typeText("qa@example.com")
        app.secureTextFields["auth.password"].tap()
        app.secureTextFields["auth.password"].typeText("Password123!")
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: app.buttons["auth.submit"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 2), .completed)
    }

    @MainActor
    func testAuthenticationAtLargestAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset-session",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["auth.apple"].waitForExistence(timeout: 5))
        let submit = app.buttons["auth.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 2))
        if !submit.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(submit.isHittable)
    }

    @MainActor
    func testAuthenticatedCatalogUsesNeutralSceneNamesAndExposesSupport() throws {
        let app = launchAuthenticated()

        app.buttons["tab.explore"].tap()
        XCTAssertTrue(app.staticTexts["Explore Scenes"].waitForExistence(timeout: 3))

        let paddock = app.buttons["scene.f1-paddock"]
        for _ in 0..<6 where !paddock.exists {
            app.swipeUp()
        }
        XCTAssertTrue(paddock.exists)
        XCTAssertTrue(app.staticTexts["Grand Prix Paddock"].exists)
        XCTAssertFalse(app.staticTexts["F1 Paddock"].exists)

        app.buttons["tab.profile"].tap()
        let support = app.descendants(matching: .any)["profile.support"]
        for _ in 0..<8 where !support.exists {
            app.swipeUp()
        }
        XCTAssertTrue(support.exists)
    }

    @MainActor
    func testFriendCompanionShowsRequiredPermissionAttestation() throws {
        let app = launchAuthenticated(companionEnabled: true)

        app.buttons["tab.newScene"].tap()
        let scene = app.buttons["scene.times-square"]
        XCTAssertTrue(scene.waitForExistence(timeout: 3))
        scene.tap()

        let continueButton = app.buttons["scene.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        continueButton.tap()

        let companion = app.switches["companion.enabled"]
        for _ in 0..<8 where !companion.exists {
            app.swipeUp()
        }
        XCTAssertTrue(companion.exists)

        let permission = app.descendants(matching: .any)["companion.permission"]
        for _ in 0..<4 where !permission.exists {
            app.swipeUp()
        }
        XCTAssertTrue(permission.waitForExistence(timeout: 3))
        XCTAssertEqual(permission.value as? String, "0")
        XCTAssertTrue(app.staticTexts["I have this person's permission to use their photo for AI generation."].exists)
    }

    /// Produces reviewable source captures for the App Store marketing set and
    /// verifies that the StoreKit-configured prices render before export.
    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset-session",
            "-ui-testing-authenticated",
            "-ui-testing-screenshots",
            "-SCENEME_UI_TEST_AUTHENTICATED", "YES"
        ]
        app.launchEnvironment["SCENEME_UI_TEST_AUTHENTICATED"] = "1"
        app.launchEnvironment["SCENEME_SCREENSHOT_MODE"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["tab.explore"].waitForExistence(timeout: 8))
        settle()
        attachScreenshot(named: "01-home")

        app.buttons["tab.explore"].tap()
        XCTAssertTrue(app.staticTexts["Explore Scenes"].waitForExistence(timeout: 5))
        settle()
        attachScreenshot(named: "02-explore")

        app.buttons["tab.newScene"].tap()
        XCTAssertTrue(app.staticTexts["Pick a Scene"].waitForExistence(timeout: 5))
        settle()
        attachScreenshot(named: "05-scene-picker")

        let scene = app.buttons["scene.times-square"]
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        scene.tap()
        let continueButton = app.buttons["scene.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["TIME OF DAY"].waitForExistence(timeout: 5))

        let premium = app.buttons["quality.premium"]
        for _ in 0..<8 {
            let clearsStickyButton = premium.exists
                && premium.isHittable
                && premium.frame.maxY < app.frame.maxY - 170
            if clearsStickyButton { break }
            app.swipeUp()
        }
        XCTAssertTrue(premium.isHittable)
        XCTAssertLessThan(premium.frame.maxY, app.frame.maxY - 170)
        settle()
        attachScreenshot(named: "03-scene-options")

        premium.tap()

        let proPrice = app.staticTexts["$119.99"].firstMatch
        XCTAssertTrue(proPrice.waitForExistence(timeout: 12), "StoreKit test products did not load.")
        XCTAssertTrue(app.staticTexts["SAVE 33%"].waitForExistence(timeout: 3))
        settle()
        attachScreenshot(named: "04-paywall")
    }

    @MainActor
    private func launchAuthentication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-session"]
        app.launch()
        return app
    }

    @MainActor
    private func launchAuthenticated(companionEnabled: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset-session",
            "-ui-testing-authenticated",
            "-SCENEME_UI_TEST_AUTHENTICATED", "YES"
        ]
        app.launchEnvironment["SCENEME_UI_TEST_AUTHENTICATED"] = "1"
        if companionEnabled {
            app.launchEnvironment["SCENEME_UI_TEST_COMPANION_ENABLED"] = "1"
        }
        app.launch()
        return app
    }

    @MainActor
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
