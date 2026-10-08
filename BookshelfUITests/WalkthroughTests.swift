import XCTest

/// Uses the app the way a person would, flow by flow, on a throwaway sample library
/// (`-uiTesting YES`). Each step saves a screenshot, and anything that can't be found
/// is written to `log.txt` instead of stopping the run, so one pass shows everything.
///
///     xcodebuild test -scheme BookshelfWalkthrough -destination '…' TEST_RUNNER_SNAP_DIR=/some/folder
final class WalkthroughTests: XCTestCase {
    private var app: XCUIApplication!
    private var step = 0
    private var flow = ""

    private var folder: URL {
        let path = ProcessInfo.processInfo.environment["SNAP_DIR"] ?? NSTemporaryDirectory() + "walkthrough"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    override func setUp() {
        continueAfterFailure = true
        let dark = ProcessInfo.processInfo.environment["WALK_DARK"] == "1"
        XCUIDevice.shared.appearance = dark ? .dark : .light
        flow = name.replacingOccurrences(of: "-[WalkthroughTests test", with: "").replacingOccurrences(of: "]", with: "") + (dark ? "-dark" : "")
        step = 0
    }

    // MARK: Helpers

    private func launch(tab: String) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-selectedTab", tab]
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 10)
    }

    private func note(_ text: String) {
        let line = "[\(flow)] \(text)\n"
        let url = folder.appendingPathComponent("log.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func snap(_ what: String) {
        step += 1
        Thread.sleep(forTimeInterval: 0.6)
        let file = String(format: "%@-%02d-%@.png", flow, step, what.replacingOccurrences(of: " ", with: "_"))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent(file))
    }

    /// Anything tappable or readable whose label is, or starts with, `label`.
    private func find(_ label: String, in root: XCUIElement? = nil) -> XCUIElement {
        let root = root ?? app!
        let exact = NSPredicate(format: "label ==[c] %@", label)
        let starts = NSPredicate(format: "label BEGINSWITH[c] %@", label)
        for predicate in [exact, starts] {
            for query in [root.buttons, root.staticTexts, root.switches, root.otherElements, root.images, root.textFields, root.cells] {
                let match = query.matching(predicate).firstMatch
                if match.exists { return match }
            }
        }
        return root.buttons[label]
    }

    @discardableResult
    private func tap(_ label: String, wait: TimeInterval = 4) -> Bool {
        var element = find(label)
        if !element.exists {
            _ = app.buttons[label].waitForExistence(timeout: wait)
            element = find(label)
        }
        guard element.exists else {
            note("MISSING: could not find “\(label)” to tap")
            return false
        }
        if !element.isHittable {
            // Off screen: scroll a little and try again.
            for _ in 0..<5 where !element.isHittable { app.swipeUp(velocity: .slow) }
            if !element.isHittable { note("NOT HITTABLE: “\(label)” exists but can't be tapped (covered or off screen)") }
        }
        element.tap()
        return true
    }

    private func type(_ text: String, into field: String) {
        let element = app.textFields[field].exists ? app.textFields[field] : app.textViews[field]
        guard element.waitForExistence(timeout: 3) else {
            note("MISSING: no field “\(field)”")
            return
        }
        element.tap()
        element.typeText(text)
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.exists { button.tap() } else { note("NO BACK BUTTON") }
    }

    private func tab(_ name: String) {
        if !tap(name) { note("MISSING TAB \(name)") }
    }

    // MARK: Flows

    func test1Explore() {
        launch(tab: "explore")
        snap("explore")
        app.swipeUp()
        snap("explore scrolled")
        app.swipeDown()
        tap("Classics")
        snap("category grid")
        back()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Pers")
            snap("search results")
            tap("Persuasion")
            snap("3D book front or back")
            Thread.sleep(forTimeInterval: 1.5)
            snap("3D book after turn")
            tap("Persuasion")
            snap("3D book tapped")
            tap("Full details")
            snap("details from 3D")
            back()
            tap("Start reading")
            if !app.staticTexts["Moved to Reading"].waitForExistence(timeout: 2) { note("NO CONFIRMATION after Start reading") }
            snap("after start reading")
        } else {
            note("MISSING: search field on Explore")
        }
        tab("Reading")
        snap("reading tab after start")
    }

    func test2Reading() {
        launch(tab: "reading")
        snap("reading")
        let row = find("The Left Hand of Darkness")
        if row.exists {
            row.swipeLeft()
            snap("row swiped left")
            app.swipeDown()
            tap("Finished")
            snap("finished button tapped")
        } else {
            note("MISSING: reading row")
        }
        launch(tab: "reading")
        snap("reading with progress")
        if tap("Update progress") {
            snap("progress sheet")
            let field = app.textFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("110")
                snap("page typed")
            } else {
                note("MISSING: page field in progress sheet")
            }
            tap("Save")
            snap("row after logging")
        }
        tap("Sapiens")
        app.swipeUp()
        snap("progress block with week chart")
        if tap("Update progress") {
            let field = app.textFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("9")   // 2159: past the end
                tap("Save")
                snap("finished prompt")
                tap("Not yet")
            }
        }
        launch(tab: "reading")
        tap("The Left Hand of Darkness")
        snap("details of reading book")
        tap("Read")
        snap("marked read")
        tap("Finished")
        snap("finish date menu")
        tap("Pick the day")
        snap("day picker")
        tap("Cancel")
        app.swipeUp()
        snap("details scrolled under bar")
    }

    func test3Details() {
        launch(tab: "profile")
        tap("All books")
        snap("all books")
        tap("Pride and Prejudice")
        snap("details top")
        app.swipeUp()
        snap("details middle")
        let toggle = app.switches.firstMatch
        if toggle.exists {
            toggle.tap()
            snap("favourite toggled")
            toggle.tap()
        } else {
            note("MISSING: favourite switch")
        }
        if tap("Lend…") {
            snap("lend menu")
            tap("Lend to a friend")
            snap("lend dialog")
            tap("Type a name")
            snap("name alert")
            let field = app.alerts.textFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.typeText("Neha")
                tap("Save")
            } else {
                note("MISSING: name field in lend alert")
            }
            snap("after lending")
            tap("Mark returned")
            snap("after return")
        }
        let notes = app.textFields["Your thoughts on this book…"].exists ? app.textFields["Your thoughts on this book…"] : app.textViews.firstMatch
        if notes.exists {
            notes.tap()
            notes.typeText("Loved it")
            snap("typing notes with keyboard")
            if app.keyboards.buttons["Done"].exists || app.toolbars.buttons["Done"].exists {
                (app.toolbars.buttons["Done"].exists ? app.toolbars.buttons["Done"] : app.keyboards.buttons["Done"]).tap()
            } else {
                note("NO DONE BUTTON on keyboard for notes")
                app.swipeDown()
            }
        } else {
            note("MISSING: notes field")
        }
        app.swipeUp()
        snap("details bottom")
        app.swipeDown()
        app.swipeDown()
        app.navigationBars.buttons["Edit"].firstMatch.tap()
        snap("edit sheet")
        app.swipeUp()
        snap("edit sheet categories")
        tap("Cancel")
        app.swipeUp()
        app.swipeUp()
        tap("Remove book")
        snap("remove confirmation")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else { app.tap() }
    }

    func test4AddBook() {
        launch(tab: "explore")
        tap("Add book")
        snap("add sheet")
        tap("Enter details manually")
        snap("empty form")
        type("Persuasion", into: "Title")
        type("Jane Austen", into: "Authors (comma separated)")
        snap("form filled")
        app.swipeUp()
        snap("form lower")
        tap("Save")
        snap("after saving a duplicate title")
        tap("Cancel")
        snap("after cancel")
        tap("Cancel")
        launch(tab: "explore")
        tap("Add book")
        tap("Search by title or author")
        snap("search screen")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Circe Madeline Miller")
            Thread.sleep(forTimeInterval: 5)
            snap("online results")
        }
        back()
        let isbn = app.textFields["e.g. 9780141439518"]
        if isbn.waitForExistence(timeout: 3) {
            isbn.tap()
            isbn.typeText("9780141439518")
            snap("isbn typed")
            tap("Find")
            snap("owned isbn")
        } else {
            note("MISSING: ISBN field")
        }
    }

    func test5Favourites() {
        launch(tab: "favourites")
        snap("favourites")
        app.swipeUp()
        snap("favourites lower")
        app.swipeDown()
        if tap("Set a goal") {
            snap("goal editor")
            let stepper = app.steppers.firstMatch
            if stepper.exists { stepper.buttons.element(boundBy: 1).tap() } else { note("MISSING: goal stepper") }
            tap("Save")
            snap("goal set")
            tap("Change goal")
            snap("change goal")
            tap("Cancel")
        }
        for label in ["Rearrange", "Edit"] where app.buttons[label].exists {
            app.buttons[label].tap()
            snap("rearranging")
            tap("Done")
            break
        }
        let year = Calendar.current.component(.year, from: Date())
        if tap(String(year)) {
            snap("year page")
            back()
        }
        tap("Pride and Prejudice")
        snap("favourite opened")
    }

    func test6Profile() {
        launch(tab: "profile")
        snap("profile")
        tap("All books")
        if tap("Options") {
            snap("options menu")
            for label in ["List"] { tap(label) }
            snap("list layout")
            tap("Options")
            for label in ["Covers", "Shelves"] where find(label).exists { tap(label); break }
        }
        let search = app.searchFields.firstMatch
        if search.exists {
            search.tap()
            search.typeText("zzz")
            snap("all books no results")
        }
        launch(tab: "profile")
        tap("Read")
        snap("read list")
        back()
        tap("Lent out")
        snap("lent out")
        tap("Returned")
        snap("after returned")
        back()
        tap("Borrowed")
        snap("borrowed")
        back()
        tap("Categories")
        snap("categories")
        tap("New category")
        snap("new category alert")
        let field = app.alerts.textFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            tap("Add")
            snap("after adding empty name")
        }
        if app.alerts.firstMatch.exists { tap("Cancel") }
        let row = find("Romance")
        if row.exists {
            row.swipeLeft()
            snap("category swiped")
            tap("Delete")
            snap("after category delete tapped")
        }
    }

    func test7Bookstores() {
        launch(tab: "bookstores")
        snap("bookstores")
        tap("Blossom Book House")
        snap("store detail")
        app.swipeUp()
        snap("store detail lower")
        tap("Done")
    }
}
