import XCTest

final class EGOFocusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(reset: Bool, uiTesting: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args: [String] = []
        if uiTesting { args.append("-uiTesting") }
        if reset { args.append("-resetStore") }
        app.launchArguments = args + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Create → edit → complete → relaunch (persistence) → reopen → delete.
    func testTaskLifecycleAndPersistence() throws {
        var app = launch(reset: true)
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].waitForExistence(timeout: 10))

        // Create
        app.buttons["addTaskButton"].tap()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("UI Lifecycle Task")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(element(app, containing: "UI Lifecycle Task").waitForExistence(timeout: 5))
        attachScreenshot("01-created")

        // Edit
        element(app, containing: "UI Lifecycle Task").tap()
        let editTitle = app.textFields["editor.title"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 5))
        editTitle.tap()
        editTitle.typeText(" Edited")
        let notes = app.textFields["editor.notes"]
        if notes.exists { notes.tap(); notes.typeText("Some notes") }
        app.buttons["editor.save"].tap()
        XCTAssertTrue(element(app, containing: "Edited").waitForExistence(timeout: 5))

        // Complete
        let completeButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "إكمال")).firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()
        let reopenButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "إعادة فتح")).firstMatch
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 5), "Completed task shows a reopen control")
        attachScreenshot("02-completed")

        // Relaunch without reset: data must persist
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(element(app, containing: "Edited").waitForExistence(timeout: 10), "Task persisted after relaunch")
        let reopenAfter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "إعادة فتح")).firstMatch
        XCTAssertTrue(reopenAfter.exists, "Completion state persisted after relaunch")

        // Reopen
        reopenAfter.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "إكمال")).firstMatch.waitForExistence(timeout: 5))

        // Delete
        element(app, containing: "Edited").tap()
        let delete = app.buttons["editor.delete"]
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !delete.exists { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["حذف نهائياً"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: element(app, containing: "Edited"))
        waitForExpectations(timeout: 5)
    }

    func testQuickAddFromHome() throws {
        let app = launch(reset: true)
        let field = app.textFields["home.quickAdd"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Quick Task\n")
        XCTAssertTrue(element(app, containing: "Quick Task").waitForExistence(timeout: 5))
    }

    func testTabsNavigate() throws {
        let app = launch(reset: true, extra: ["-demoData"])
        XCTAssertTrue(app.tabBars.buttons["التقويم"].waitForExistence(timeout: 10))
        attachScreenshot("10-home")

        app.tabBars.buttons["التقويم"].tap()
        XCTAssertTrue(app.staticTexts["calendar.monthTitle"].waitForExistence(timeout: 5))
        let before = app.staticTexts["calendar.monthTitle"].label
        app.buttons["الشهر التالي"].tap()
        XCTAssertNotEqual(app.staticTexts["calendar.monthTitle"].label, before, "Month navigation works")
        app.buttons["calendar.today"].tap()
        XCTAssertEqual(app.staticTexts["calendar.monthTitle"].label, before)
        attachScreenshot("11-calendar")

        app.tabBars.buttons["التقارير"].tap()
        XCTAssertTrue(app.otherElements["reports.completion"].waitForExistence(timeout: 5)
                      || app.staticTexts["نسبة الإنجاز"].waitForExistence(timeout: 5))
        attachScreenshot("12-reports")

        app.tabBars.buttons["الإعدادات"].tap()
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.staticTexts["EGO FOCUS"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["EGO FOCUS"].waitForExistence(timeout: 5), "About section with app name")
        attachScreenshot("13-settings")
    }

    func testAssistantPreviewBeforeSaving() throws {
        let app = launch(reset: true)
        let assistant = app.buttons["home.assistant"]
        XCTAssertTrue(assistant.waitForExistence(timeout: 10))
        assistant.tap()

        let example = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "مراجعة الفواتير")).firstMatch
        XCTAssertTrue(example.waitForExistence(timeout: 5))
        example.tap()

        let previewTitle = app.textFields["assistant.previewTitle"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5), "A preview is shown before saving")
        XCTAssertEqual(previewTitle.value as? String, "مراجعة الفواتير")
        attachScreenshot("20-assistant-preview")

        // Nothing is saved until the user confirms.
        let save = app.buttons["assistant.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(element(app, containing: "مراجعة الفواتير").waitForExistence(timeout: 5))
    }

    func testAmbiguousCommandRequiresConfirmation() throws {
        let app = launch(reset: true)
        app.buttons["home.assistant"].tap()
        let example = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "مستلزمات المكتب")).firstMatch
        XCTAssertTrue(example.waitForExistence(timeout: 5))
        example.tap()
        let save = app.buttons["assistant.save"]
        XCTAssertTrue(app.textFields["assistant.previewTitle"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "No time was given → save is blocked until the user confirms")
        let confirm = app.switches["assistant.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        if confirm.switches.firstMatch.exists { confirm.switches.firstMatch.tap() } else { confirm.tap() }
        XCTAssertTrue(save.isEnabled)
    }

    /// Grants notification permission through the system alert, then checks that
    /// creating a task schedules a local notification.
    func testNotificationsAreScheduled() throws {
        let app = launch(reset: true, uiTesting: false)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "السماح"])).firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        app.buttons["addTaskButton"].tap()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Reminder Task")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(element(app, containing: "Reminder Task").waitForExistence(timeout: 5))

        app.tabBars.buttons["الإعدادات"].tap()
        let count = app.staticTexts["settings.scheduledCountValue"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let scheduled = NSPredicate(format: "label != %@", "0")
        expectation(for: scheduled, evaluatedWith: count)
        waitForExpectations(timeout: 8)
        attachScreenshot("30-notifications")
    }

    func testDarkAppearanceSetting() throws {
        let app = launch(reset: true, extra: ["-egofocus_appearance", "dark", "-demoData"])
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].waitForExistence(timeout: 10))
        attachScreenshot("40-dark-home")
        app.tabBars.buttons["الإعدادات"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appearance"].waitForExistence(timeout: 5)
                      || app.buttons["داكن"].waitForExistence(timeout: 5))
        app.buttons["فاتح"].tap()
        attachScreenshot("41-light-settings")
    }
}
