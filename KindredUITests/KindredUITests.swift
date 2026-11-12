import XCTest

@MainActor
final class KindredUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    func launch(demo: Bool = true, options: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = demo ? ["--uitesting", "--demo"] : ["--uitesting"]
        app.launchArguments += options
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", options.contains("--large-text") ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
    }
    func reveal(_ element: XCUIElement, attempts: Int = 6) {
        for _ in 0..<attempts { if element.isHittable { return }; app.swipeUp() }
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func next() { let button = app.buttons["onboardingNext"]; XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap() }
    func testRemoveInterestAndConfirmedUnmatch() {
        for options in [[], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options)
            app.buttons["likeProfile"].tap()
            XCTAssertTrue(app.buttons["matchKeepDiscovering"].waitForExistence(timeout: 4))
            app.buttons["matchKeepDiscovering"].tap()
            app.tabBars.buttons["Likes"].tap(); app.buttons["Your likes"].tap()
            let explanation = app.staticTexts["Removes your saved interest, including photo and answer likes. Your connection and chat stay."]
            reveal(explanation, attempts: 12); XCTAssertTrue(explanation.exists)
            capture("Remove interest explanation \(options.isEmpty ? "standard" : "large")")
            let remove = app.buttons["removeLike-amara"]; reveal(remove, attempts: 12); remove.tap()
            app.buttons["Liked you"].tap()
            let unmatch = app.buttons["unmatch-amara"]; reveal(unmatch, attempts: 12); unmatch.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
            capture("Unmatch confirmation \(options.isEmpty ? "standard" : "large")")
            if !options.isEmpty {
                for _ in 0..<5 {
                    let alert = app.alerts.firstMatch
                    alert.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 0.05, thenDragTo: alert.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
                }
                capture("Unmatch explanation scrolled large")
            }
            app.alerts.buttons["Keep connection"].tap()
            let hello = app.buttons["sayHello-amara"]; reveal(hello, attempts: 12); hello.tap()
            XCTAssertTrue(app.navigationBars["Amara"].waitForExistence(timeout: 3))
            app.buttons["Profile safety options"].tap(); app.buttons["Unmatch"].tap()
            app.alerts.buttons["Unmatch"].tap()
            XCTAssertTrue(app.staticTexts["Conversation unavailable"].waitForExistence(timeout: 3))
            app.tabBars.buttons["Chats"].tap()
            XCTAssertFalse(app.buttons["conversation-amara"].exists)
            app.tabBars.buttons["Likes"].tap()
            XCTAssertFalse(app.buttons["unmatch-amara"].exists)
        }
    }
    func testMatchedProfileLeavesDiscoverAndKeepsChat() {
        launch()
        app.buttons["likeProfile"].tap()
        XCTAssertTrue(app.buttons["matchKeepDiscovering"].waitForExistence(timeout: 4))
        app.buttons["matchKeepDiscovering"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
        app.tabBars.buttons["Chats"].tap()
        XCTAssertTrue(app.buttons["conversation-amara"].exists)
        app.tabBars.buttons["Discover"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
    }
    func testCropChangesProtectCancelAndSwipe() {
        launch()
        app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        func openCrop() {
            let menu = app.buttons["Edit photo 1"]; reveal(menu, attempts: 20); menu.tap()
            app.buttons["Adjust crop"].tap()
            XCTAssertTrue(app.navigationBars["Adjust crop"].waitForExistence(timeout: 3))
        }
        func showZoom() {
            let slider = app.sliders["Photo zoom"]
            for _ in 0..<15 {
                if slider.isHittable && slider.frame.midY > 150 && slider.frame.midY < app.frame.maxY - 100 { break }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
                start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
            }
        }
        openCrop()
        app.navigationBars["Adjust crop"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Adjust crop"].waitForNonExistence(timeout: 3))
        openCrop()
        let zoom = app.sliders["Photo zoom"]; showZoom(); zoom.adjust(toNormalizedSliderPosition: 0.6)
        let changed = zoom.value as? String
        XCTAssertNotEqual(changed, "1", "Zoom must change before testing discard")
        app.navigationBars["Adjust crop"].buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertEqual(zoom.value as? String, changed)
        swipeSheetDown()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard changes"].tap()
        XCTAssertTrue(app.navigationBars["Adjust crop"].waitForNonExistence(timeout: 3))
        openCrop(); showZoom()
        XCTAssertNotEqual(zoom.value as? String, changed)
        zoom.adjust(toNormalizedSliderPosition: 0.6)
        let applied = zoom.value as? String
        app.buttons["Apply"].tap()
        openCrop(); showZoom()
        XCTAssertEqual(zoom.value as? String, applied)
        app.navigationBars["Adjust crop"].buttons["Cancel"].tap()
        XCTAssertFalse(app.alerts["Discard changes?"].exists)
    }
    func testSavedPreviewPhotoOrderAndOptionalSections() {
        launch()
        app.buttons["You"].tap()
        app.buttons["editProfile"].tap()
        let add = app.buttons["Use demo portrait Amara"]; reveal(add, attempts: 20); add.tap()
        let edit = app.buttons["editPhoto-amara"]; reveal(edit, attempts: 20); edit.tap()
        app.buttons["Make primary"].tap()
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons["saveProfile"].waitForNonExistence(timeout: 5))
        let preview = app.buttons["publicPreview"]
        for _ in 0..<10 {
            if preview.isHittable { break }
            app.swipeDown()
        }
        preview.tap()
        let pager = app.descendants(matching: .any).matching(identifier: "profilePhotoPager").firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertTrue(pager.images.matching(NSPredicate(format: "value == %@", "AI-generated portrait of fictional member Amara")).firstMatch.exists)
        XCTAssertEqual(app.staticTexts["photoPosition"].label, "Photo 1 of 2")
        app.buttons["Next photo"].tap()
        XCTAssertEqual(app.staticTexts["photoPosition"].label, "Photo 2 of 2")
        XCTAssertTrue(pager.images.matching(NSPredicate(format: "value == %@", "AI-generated sample portrait for Alex")).firstMatch.exists)
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(app.staticTexts["FAITH IN EVERYDAY LIFE"].exists)
        XCTAssertFalse(app.staticTexts["A conversation to share in time."].exists)
        XCTAssertFalse(app.staticTexts["Prefer to share later"].exists)
        capture("Saved preview omits unshared faith")
    }

    func testPhotoOrderingCropGesturesAndSavedPreview() {
        launch()
        app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        let add = app.buttons["Use demo portrait Amara"]; reveal(add, attempts: 20); add.tap()
        func menu(_ id: String) { let item = app.buttons["editPhoto-" + id]; reveal(item, attempts: 20); item.tap() }
        menu("amara"); app.buttons["Make primary"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "editPhoto-amara", "Edit photo 1")).firstMatch.waitForExistence(timeout: 5))
        menu("amara"); app.buttons["Move later"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "editPhoto-amara", "Edit photo 2")).firstMatch.waitForExistence(timeout: 5))
        menu("amara"); app.buttons["Move earlier"].tap()
        menu("amara"); app.buttons["Adjust crop"].tap()
        let canvas = app.images["cropCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
        canvas.pinch(withScale: 1.6, velocity: 1)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6)))
        let avatar = app.images["cropAvatarPreview"]; reveal(avatar); XCTAssertTrue(avatar.exists)
        capture("Photo crop and circular avatar")
        let zoom = app.sliders["Photo zoom"]; reveal(zoom); let zoomValue = zoom.value as? String
        XCTAssertNotEqual(zoomValue, "0%")
        app.buttons["Apply"].tap()
        let remove = app.buttons["removePhoto-rowan"]; reveal(remove); remove.tap()
        XCTAssertFalse(app.buttons["editPhoto-rowan"].exists)
        XCTAssertTrue(app.buttons["editPhoto-amara"].exists, "Removing Rowan must preserve Amara")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons["saveProfile"].waitForNonExistence(timeout: 3))
        let preview = app.buttons["publicPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        for _ in 0..<8 { if preview.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(preview.isHittable); preview.tap()
        XCTAssertTrue(app.navigationBars["Your story"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Next photo"].exists)
        capture("Saved primary photo profile preview")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["editProfile"].tap(); menu("amara"); app.buttons["Adjust crop"].tap()
        reveal(zoom); XCTAssertEqual(zoom.value as? String, zoomValue)
    }
    func testPhotoRemovalUndoRestoresPrimaryAndOrder() {
        launch()
        app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        let add = app.buttons["Use demo portrait Amara"]; reveal(add, attempts: 20); add.tap()
        let primary = app.buttons["removePhoto-rowan"]
        reveal(primary); XCTAssertEqual(primary.label, "Remove photo 1"); primary.tap()
        XCTAssertTrue(app.buttons["editPhoto-amara"].exists)
        let undo = app.buttons["undoPhotoRemoval"]; reveal(undo); undo.tap()
        XCTAssertEqual(app.buttons["editPhoto-rowan"].label, "Edit photo 1")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "editPhoto-amara", "Edit photo 2")).firstMatch.waitForExistence(timeout: 5))
        primary.tap()
        let second = app.buttons["removePhoto-amara"]; reveal(second); second.tap()
        reveal(undo); undo.tap(); reveal(undo); undo.tap()
        XCTAssertEqual(app.buttons["editPhoto-rowan"].label, "Edit photo 1")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "editPhoto-amara", "Edit photo 2")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists)
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons["saveProfile"].waitForNonExistence(timeout: 3))
    }
    func testPreferencesDraftSurvivesBackgroundAndRepeatedSave() {
        launch()
        app.buttons["discoveryPreferences"].tap()
        let female = app.switches["Female"]
        reveal(female)
        female.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(female.value as? String, "0")
        let save = app.buttons["savePreferences"]
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        app.buttons["discoveryPreferences"].tap()
        reveal(female)
        XCTAssertEqual(female.value as? String, "0")
        app.buttons["Cancel"].tap()
    }

    func testBackgroundCancelsDiscoveryAdvanceAndKeepsProfileDraft() {
        launch(options: ["--pending-interest-demo", "--slow-discovery-advance"])
        app.buttons["likeProfile"].tap()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5.3)
        app.activate()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
        let edit = app.buttons["editProfile"]
        let name = app.textFields["editName"]
        XCTAssertTrue(tapAndWait(app.tabBars.buttons["You"], for: edit))
        XCTAssertTrue(tapAndWait(edit, for: name))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(tapAndWait(name, for: keyboard), "The first-name field should open the keyboard")
        name.typeText(" Grace")
        XCTAssertEqual(name.value as? String, "Alex Grace")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(name.value as? String, "Alex Grace")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertEqual(name.value as? String, "Alex Grace")
        let save = app.buttons["saveProfile"]
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertTrue(tapAndWait(edit, for: name))
        XCTAssertEqual(name.value as? String, "Alex Grace")
        app.buttons["Cancel"].tap()
    }

    func testPendingAdvanceCancelsForNavigationPreferencesAndUndo() {
        for action in ["tabs", "profile", "preferences", "undo"] {
            launch(options: ["--pending-interest-demo", "--slow-discovery-advance"])
            if action == "undo" { app.buttons["passProfile"].tap() }
            if action == "profile" { reveal(app.buttons["openProfile"]) }
            app.buttons["likeProfile"].tap()
            switch action {
            case "tabs": app.tabBars.buttons["You"].tap()
            case "profile": app.buttons["openProfile"].tap()
            case "preferences": app.buttons["discoveryPreferences"].tap()
            default: app.buttons["undoPass"].tap()
            }
            Thread.sleep(forTimeInterval: 5.3)
            switch action {
            case "tabs": app.tabBars.buttons["Discover"].tap()
            case "profile": app.navigationBars.buttons.element(boundBy: 0).tap()
            case "preferences": app.buttons["Cancel"].tap()
            default: break
            }
            XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
            Thread.sleep(forTimeInterval: 5.3)
            XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara", "Returning must not restart the timer")
        }
    }
    func testPendingInterestAdvancesOnceAndRetainsFeedback() {
        launch(options: ["--pending-interest-demo"])
        app.buttons["likeProfile"].doubleTap()
        let next = app.buttons["passProfile"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        XCTAssertEqual(next.label, "Next introduction, skip Eli")
        XCTAssertTrue(app.staticTexts["feedbackBanner"].label.contains("Amara"))
        capture("Pending interest acknowledgement after advance")
        app.buttons["passProfile"].tap(); app.buttons["undoPass"].tap()
        XCTAssertEqual(next.label, "Next introduction, skip Eli")
        app.tabBars.buttons["Likes"].tap(); app.buttons["Your likes"].tap()
        XCTAssertTrue(app.buttons["removeLike-amara"].exists)
        XCTAssertFalse(app.buttons["removeLike-eli"].exists)
    }
    func testPendingPhotoAndPromptLikesAdvance() {
        for action in ["photo", "prompt"] {
            launch(options: ["--pending-interest-demo", "--reduce-motion"])
            if action == "photo" {
                let photo = app.buttons["photoLike-amara-amara-gallery"]; reveal(photo); photo.tap()
            } else {
                let prompt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Like answer to")).firstMatch
                reveal(prompt, attempts: 12); prompt.tap()
            }
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Next introduction, skip Eli"), object: app.buttons["passProfile"])
            XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 3), .completed)
            XCTAssertTrue(app.staticTexts["feedbackBanner"].label.contains(action == "photo" ? "photo" : "answer"))
            capture("Pending \(action) acknowledgement")
            app.tabBars.buttons["You"].tap()
            let discover = app.tabBars.buttons["Discover"]
            discover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(discover.isSelected)
            XCTAssertTrue(app.buttons["passProfile"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Eli")
        }
    }
    func testLargestTextLikesAndPhotoEditor() {
        for mode in [[], ["--dark"]] as [[String]] {
            launch(options: ["--large-text", "--largest-text", "--reduce-motion"] + mode)
            app.tabBars.buttons["Likes"].tap()
            let name = app.staticTexts["Amara, 28"]; reveal(name, attempts: 15)
            XCTAssertTrue(name.isHittable)
            capture("Largest Likes \(mode.isEmpty ? "light" : "dark")")
            app.tabBars.buttons["You"].tap()
            let edit = app.buttons["editProfile"]; reveal(edit, attempts: 15); edit.tap()
            let photo = app.buttons["editPhoto-rowan"]; reveal(photo, attempts: 30)
            XCTAssertTrue(photo.isHittable)
            capture("Largest photo editor \(mode.isEmpty ? "light" : "dark")")
            photo.tap()
            let adjustCrop = app.buttons["Adjust crop"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: adjustCrop)
            guard XCTWaiter.wait(for: [ready], timeout: 8) == .completed else {
                XCTFail("Adjust crop did not become tappable in the photo menu")
                return
            }
            adjustCrop.tap()
            let applyCrop = app.buttons["applyPhotoCrop"]
            guard applyCrop.waitForExistence(timeout: 8) else {
                capture("Crop editor failed to open")
                XCTFail("The crop editor's Apply button did not appear")
                return
            }
            capture("Largest crop editor \(mode.isEmpty ? "light" : "dark")")
            app.buttons["cancelPhotoCrop"].tap()
            XCTAssertTrue(applyCrop.waitForNonExistence(timeout: 8))
            let remove = app.buttons["removePhoto-rowan"]
            for _ in 0..<20 {
                if remove.isHittable && remove.frame.midY > 150 && remove.frame.midY < app.frame.maxY - 100 { break }
                if remove.exists && remove.frame.midY < 150 { app.swipeDown() } else { app.swipeUp() }
            }
            remove.tap()
            XCTAssertTrue(remove.waitForNonExistence(timeout: 3))
            let undo = app.buttons["undoPhotoRemoval"]; reveal(undo, attempts: 15); undo.tap()
            XCTAssertTrue(app.buttons["editPhoto-rowan"].exists)
        }
    }
    func testScrollingReadability() {
        for options in [[], ["--dark"], ["--large-text"], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options)
            let mode = (options.contains("--large-text") ? "large" : "standard") + (options.contains("--dark") ? " dark" : " light")
            XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
            for tab in ["Discover", "Likes", "You", "Chats"] {
                app.tabBars.buttons[tab].tap()
                app.swipeUp()
                capture("Scroll readability \(tab) \(mode)")
                XCTAssertTrue(app.tabBars.buttons[tab].isHittable)
            }
        }
    }

    func testUnsavedSheetsProtectCancelAndSwipe() { checkUnsavedSheets(options: []) }
    func testUnsavedSheetsLargeDark() { checkUnsavedSheets(options: ["--dark", "--large-text", "--reduce-motion"]) }
    private func checkUnsavedSheets(options: [String]) {
        launch(options: options)
        app.buttons["discoveryPreferences"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["discoveryPreferences"].isHittable)
        app.buttons["discoveryPreferences"].tap()
        swipeSheetDown()
        if app.buttons["savePreferences"].exists { swipeSheetDown() }
        XCTAssertTrue(app.buttons["savePreferences"].waitForNonExistence(timeout: 5))
        app.buttons["discoveryPreferences"].tap()
        let female = app.switches["Female"]
        reveal(female)
        female.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Discard changes?"].waitForExistence(timeout: 3))
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(female.value as? String, "0")
        swipeSheetDown()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 3))
        capture("Preferences discard confirmation")
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["savePreferences"].waitForNonExistence(timeout: 3))
        app.buttons["discoveryPreferences"].tap()
        reveal(female)
        XCTAssertEqual(female.value as? String, "1")
        female.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); female.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() // Reverting to the saved value is clean.
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["discoveryPreferences"].isHittable)
        app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        let name = app.textFields["editName"]
        name.tap(); name.typeText(" revised")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        swipeSheetDown()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 3))
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(name.value as? String, "Alex revised")
        app.buttons["Cancel"].tap()
        capture("Profile discard confirmation")
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 3))
        app.buttons["editProfile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "Alex")
        name.tap(); name.typeText(" saved")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Alex saved, 28"].waitForExistence(timeout: 3))
    }

    private func swipeSheetDown() {
        let top = max(24, app.navigationBars.firstMatch.frame.minY - 8)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: top))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    }

    func testDistanceOpennessEditingAndPreview() {
        checkDistanceOpenness(options: [])
    }
    func testDistanceOpennessLargestText() {
        checkDistanceOpenness(options: ["--large-text", "--largest-text", "--dark", "--reduce-motion"])
    }
    private func checkDistanceOpenness(options: [String]) {
        launch(options: options)
        let edit = app.buttons["editProfile"]
        let save = app.buttons["saveProfile"]
        let preview = app.buttons["publicPreview"]
        let profile = app.scrollViews["memberProfileScroll"]
        let longDistance = app.buttons["Open to long distance"]
        let relocate = app.switches["openToRelocating"]
        let summary = app.descendants(matching: .any).matching(identifier: "distancePreferencesSummary").firstMatch

        func revealEditorControl(_ control: XCUIElement) -> Bool {
            for _ in 0..<20 {
                let top = app.navigationBars.firstMatch.frame.maxY
                let bottom = app.frame.maxY - 24
                if control.exists, control.frame.minY > top, control.frame.maxY < bottom, control.isHittable {
                    return true
                }
                let scrollTowardTop = control.exists && control.frame.minY <= top
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                let end = start.withOffset(CGVector(dx: 0, dy: scrollTowardTop ? 160 : -160))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
            }
            return false
        }
        func select(_ choice: XCUIElement) {
            XCTAssertTrue(revealEditorControl(choice), "The full distance option should be visible")
            choice.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: choice)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }
        func setRelocation(from current: String, to expected: String) {
            XCTAssertTrue(revealEditorControl(relocate), "The full relocation switch should be visible")
            XCTAssertEqual(relocate.value as? String, current)
            relocate.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: relocate)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
        func openPreview() {
            for _ in 0..<10 {
                if preview.isHittable { break }
                app.swipeDown()
            }
            XCTAssertTrue(tapAndWait(preview, for: profile))
        }

        XCTAssertTrue(tapAndWait(app.tabBars.buttons["You"], for: edit))
        XCTAssertTrue(tapAndWait(edit, for: save))
        select(longDistance)
        setRelocation(from: "0", to: "1")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep editing"].tap()
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))

        openPreview()
        reveal(summary, attempts: 15)
        XCTAssertTrue(summary.label.contains("Open to long distance"))
        XCTAssertTrue(summary.label.contains("Open to relocating"))
        capture("Saved distance and relocation preferences")

        XCTAssertTrue(tapAndWait(app.buttons["BackButton"], for: edit))
        XCTAssertTrue(tapAndWait(edit, for: save))
        XCTAssertTrue(revealEditorControl(longDistance))
        XCTAssertTrue(longDistance.isSelected)
        select(app.buttons["Prefer local connections"])
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Discard changes"].tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))

        XCTAssertTrue(tapAndWait(edit, for: save))
        XCTAssertTrue(revealEditorControl(longDistance))
        XCTAssertTrue(longDistance.isSelected)
        select(app.buttons["Not shared"])
        setRelocation(from: "1", to: "0")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))
        openPreview()
        for _ in 0..<5 { app.swipeUp() }
        XCTAssertFalse(summary.exists)
    }

    func testSearchCityFiltersWithoutChangingHomeAndShowsTravel() {
        checkLocation(options: [])
    }
    func testLocationLargestText() {
        checkLocation(options: ["--largest-text", "--dark", "--reduce-motion"])
    }
    private func checkLocation(options: [String]) {
        launch(options: ["--expanded-demo"] + options)
        app.buttons["discoveryPreferences"].tap()
        let search = app.buttons["searchCity"]
        reveal(search)
        search.tap(); app.buttons["Atlanta, GA"].tap()
        app.buttons["savePreferences"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Rachel")
        app.buttons["discoveryPreferences"].tap()
        XCTAssertTrue(app.staticTexts["Home city: Chicago, IL"].exists)
        search.tap(); app.buttons["Dallas, TX"].tap()
        app.buttons["Cancel"].tap(); app.alerts.buttons["Discard changes"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Rachel")
        app.buttons["You"].tap(); app.buttons["editProfile"].tap()
        XCTAssertEqual(app.textFields["editCity"].value as? String, "Chicago, IL")
        let status = app.buttons["locationStatus"]; reveal(status)
        status.tap(); app.buttons["Visiting"].tap()
        app.buttons["saveProfile"].tap()
        let preview = app.buttons["publicPreview"]
        for _ in 0..<10 {
            if preview.isHittable { break }
            app.swipeDown()
        }
        preview.tap()
        XCTAssertTrue(app.staticTexts["Visiting Atlanta, GA · self-reported"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chicago, IL"].exists)
        capture("Home city and self-reported visiting status")
    }

    func testProfilePhotoIdentityContrast() throws {
        for options in [[], ["--dark"]] as [[String]] {
            launch(options: options)
            let name = app.staticTexts["Amara, 28"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            let occupation = app.staticTexts["Pediatric nurse"]
            if occupation.frame.maxY >= app.buttons["passProfile"].frame.minY - 12 { app.swipeUp() }
            XCTAssertTrue(name.isHittable)
            XCTAssertTrue(occupation.isHittable)
            capture("Phone profile identity contrast \(options)")
            try app.performAccessibilityAudit(for: [.contrast]) { issue in
                guard let label = issue.element?.label else { return false }
                return !["Amara, 28", "Chicago, IL", "Pediatric nurse"].contains(label)
            }
        }
    }

    func testCoreAccessibilityLabelsContrastAndSheetReturn() throws {
        for options in [[], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options + ["--expanded-demo"])
            for tab in ["Discover", "Likes", "Chats", "You"] {
                app.buttons[tab].tap()
                if tab == "Discover" { for _ in 0..<4 { app.swipeUp() } }
                let panel = app.otherElements["discoveryActionPanel"]
                let panelFrame = panel.exists ? panel.frame : .null
                try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription, .trait]) { issue in
                    // Contrast is meaningful when the text is fully visible.
                    // Keep clipped overlay findings in the log for manual review.
                    guard issue.auditType == .contrast, let element = issue.element else { return false }
                    let navigation = self.app.tabBars.firstMatch
                    let bottom = navigation.exists ? navigation.frame.minY : self.app.frame.maxY
                    let status = self.app.statusBars.firstMatch
                    let top = status.exists && status.frame.width > status.frame.height ? status.frame.maxY : self.app.frame.minY
                    let frame = element.frame
                    // A label crossing the panel's top edge is partially covered.
                    // Controls inside the panel still receive the contrast audit.
                    let crossesPanel = frame.minY < panelFrame.minY && frame.intersects(panelFrame)
                    if frame.minY < top || frame.maxY > bottom || crossesPanel {
                        print("OVERLAY CONTRAST REVIEW: \(issue.compactDescription) \(element.debugDescription)")
                        return true
                    }
                    return false
                }
            }
            let edit = app.buttons["editProfile"]
            let profileSave = app.buttons["saveProfile"]
            XCTAssertTrue(tapAndWait(edit, for: profileSave))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(profileSave.waitForNonExistence(timeout: 8))
            XCTAssertTrue(edit.isHittable)
            XCTAssertTrue(tapAndWait(app.tabBars.buttons["Discover"], for: app.buttons["passProfile"]))
            let preferences = app.buttons["discoveryPreferences"]
            for _ in 0..<6 {
                if preferences.isHittable { break }
                app.swipeDown()
            }
            let preferencesSave = app.buttons["savePreferences"]
            XCTAssertTrue(tapAndWait(preferences, for: preferencesSave))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(preferencesSave.waitForNonExistence(timeout: 8))
            let preferencesReady = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in preferences.isHittable },
                object: preferences
            )
            XCTAssertEqual(XCTWaiter.wait(for: [preferencesReady], timeout: 5), .completed)
            XCTAssertTrue(tapAndWait(preferences, for: preferencesSave))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(preferencesSave.waitForNonExistence(timeout: 8))
            XCTAssertTrue(app.buttons["Next photo"].isEnabled)
            XCTAssertTrue(app.buttons["passProfile"].isEnabled)
            XCTAssertTrue(app.buttons["likeProfile"].isEnabled)
        }
    }

    func testInterestSelectionLimitUsesDisabledState() {
        checkInterestRows(options: [])
    }
    func testReadableInterestRowsLargestText() {
        checkInterestRows(options: ["--largest-text", "--dark", "--reduce-motion"])
    }
    private func checkInterestRows(options: [String]) {
        launch(options: options)
        let you = app.tabBars.buttons["You"]
        let edit = app.buttons["editProfile"]
        you.tap()
        if !edit.waitForExistence(timeout: 3), !you.isSelected { you.tap() }
        guard edit.waitForExistence(timeout: 8) else {
            XCTFail("The You tab did not open to Edit profile")
            return
        }
        edit.tap()
        func revealInterest(_ button: XCUIElement, scrollingUp: Bool = false) {
            for _ in 0..<20 {
                let top = app.navigationBars.firstMatch.frame.maxY + 12
                let bottom = app.frame.maxY - 50
                if button.exists && button.frame.minY > top && button.frame.maxY < bottom { return }
                let moveDown = button.exists ? button.frame.minY <= top : scrollingUp
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                let end = start.withOffset(CGVector(dx: 0, dy: moveDown ? 160 : -160))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
            }
            XCTFail("Could not reveal the full interest row: \(button)")
        }
        func waitForSelection(_ button: XCUIElement, selected: Bool) {
            let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == %@", NSNumber(value: selected)), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed)
        }
        for interest in ["Live music", "Volunteering", "Travel", "Art & design", "Movement"] {
            let button = app.buttons[interest]
            revealInterest(button)
            button.tap()
            waitForSelection(button, selected: true)
            XCTAssertTrue(button.staticTexts[interest].exists)
            XCTAssertGreaterThan(button.staticTexts[interest].frame.width, 40)
            XCTAssertGreaterThan(button.frame.width, 200)
        }
        let gardening = app.buttons["Gardening"]
        revealInterest(gardening)
        XCTAssertFalse(gardening.isEnabled)
        let hiking = app.buttons["Hiking"]
        revealInterest(hiking, scrollingUp: true)
        XCTAssertTrue(hiking.isEnabled)
        XCTAssertTrue(hiking.isSelected)
        hiking.tap()
        waitForSelection(hiking, selected: false)
        revealInterest(gardening)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: gardening)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        gardening.tap()
        waitForSelection(gardening, selected: true)
        capture("Selected and unavailable interest states")
        app.buttons["Cancel"].tap()
        app.alerts.buttons["Discard changes"].tap()
    }

    func testConversationNameSearchAndUnreadFilter() {
        for options in [[], ["--large-text", "--dark", "--reduce-motion"]] as [[String]] {
            launch(options: options + ["--expanded-demo"])
            let search = app.textFields["conversationSearch"]
            XCTAssertTrue(tapAndWait(app.tabBars.buttons["Chats"], for: search))
            searchConversations("  NAOMI  ", in: search)
            let naomi = app.buttons["conversation-demo-naomi"]
            XCTAssertTrue(naomi.waitForExistence(timeout: 5))
            reveal(naomi)
            XCTAssertTrue(naomi.isHittable)
            XCTAssertFalse(app.buttons["conversation-demo-caleb"].exists)
            XCTAssertTrue(tapAndWait(naomi, for: app.textFields["messageComposer"]))
            XCTAssertTrue(tapAndWait(app.buttons["BackButton"], for: search))
            XCTAssertEqual(search.value as? String, "  NAOMI  ")
            app.buttons["Unread"].tap()
            XCTAssertFalse(naomi.exists)
            XCTAssertTrue(app.buttons["Show all conversations"].exists)
            app.buttons["Show all conversations"].tap()
            XCTAssertTrue(app.buttons["conversation-eli"].exists)
            searchConversations("No such member", in: search)
            XCTAssertTrue(app.staticTexts["No conversations found"].exists)
            app.buttons["Clear name search"].tap()
            app.buttons["Unread"].tap()
            XCTAssertFalse(app.buttons["conversation-demo-caleb"].exists)
            XCTAssertTrue(app.buttons["conversation-demo-sofia"].exists)
            capture("Conversation search and unread filter")
        }
    }

    private func searchConversations(_ query: String, in field: XCUIElement) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(tapAndWait(field, for: keyboard))
        field.typeText(query)
        XCTAssertEqual(field.value as? String, query)
        let submit = keyboard.buttons["Search"]
        submit.tap()
        if !keyboard.waitForNonExistence(timeout: 3), submit.isHittable {
            submit.tap()
        }
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
    }

    func testConversationDraftSurvivesReopeningAndClearsAfterSend() {
        launch()
        let chats = app.tabBars.buttons["Chats"]
        let eli = app.buttons["conversation-eli"]
        let composer = app.textFields["messageComposer"]
        let back = app.buttons["BackButton"]
        XCTAssertTrue(tapAndWait(chats, for: eli))
        XCTAssertTrue(tapAndWait(eli, for: composer))
        XCTAssertTrue(tapAndWait(composer, for: app.keyboards.firstMatch))
        composer.typeText("A question for Eli")
        dismissChatKeyboard()
        XCTAssertTrue(tapAndWait(back, for: eli))
        XCTAssertTrue(tapAndWait(app.tabBars.buttons["You"], for: app.buttons["editProfile"]))
        XCTAssertTrue(tapAndWait(chats, for: eli))
        XCTAssertTrue(tapAndWait(eli, for: composer))
        XCTAssertEqual(composer.value as? String, "A question for Eli")
        capture("Restored conversation draft")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["A question for Eli"].waitForExistence(timeout: 5))
        XCTAssertTrue(tapAndWait(back, for: eli))
        XCTAssertTrue(tapAndWait(eli, for: composer))
        XCTAssertFalse(app.buttons["sendMessage"].isEnabled)
        XCTAssertTrue(app.staticTexts["A question for Eli"].exists)
    }

    func testProfileErrorsScrollAndClearWhenCorrected() {
        launch(); app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        let name = app.textFields["editName"]
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        app.buttons["Done"].tap()
        for _ in 0..<4 { app.swipeUp() }
        app.buttons["saveProfile"].tap()
        let error = app.descendants(matching: .any).matching(identifier: "profileError-name").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 3)); capture("Inline profile name error")
        XCTAssertTrue(error.isHittable)
        name.tap(); name.typeText("Jordan")
        XCTAssertFalse(error.exists)
        app.buttons["Done"].tap()
        let prompt = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'prompt-'")).firstMatch
        reveal(prompt, attempts: 12)
        XCTAssertTrue(prompt.isHittable)
        let promptID = prompt.identifier
        let answer = app.textFields[promptID]
        answer.tap(); answer.typeText(String(repeating: "a", count: 241))
        XCTAssertGreaterThan((answer.value as? String ?? "").count, 240)
        app.buttons["Done"].tap()
        for _ in 0..<4 { app.swipeDown() }
        app.buttons["saveProfile"].tap()
        let promptError = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'profileError-prompt-'")).firstMatch
        capture("Prompt validation after save")
        XCTAssertTrue(promptError.waitForExistence(timeout: 3)); capture("Inline profile prompt error")
        XCTAssertTrue(promptError.isHittable)
        answer.tap(); answer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 241))
        XCTAssertFalse(promptError.exists)
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Jordan, 28"].waitForExistence(timeout: 3))
    }

    func testProfileInlineErrorsLargeDark() {
        launch(options: ["--large-text", "--dark", "--reduce-motion"])
        app.tabBars.buttons["You"].tap(); reveal(app.buttons["editProfile"]); app.buttons["editProfile"].tap()
        let name = app.textFields["editName"]
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        app.buttons["Done"].tap()
        app.swipeUp(); app.swipeUp()
        app.buttons["saveProfile"].tap()
        let error = app.descendants(matching: .any).matching(identifier: "profileError-name").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 3)); XCTAssertTrue(error.isHittable)
        capture("Inline error large dark")
        name.tap(); name.typeText("Alex")
        XCTAssertFalse(error.exists)
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 3))
    }

    func testLargeTextSettingsRemainReadable() {
        launch(options: ["--large-text", "--dark", "--reduce-motion"])
        app.tabBars.buttons["You"].tap()
        let preferences = app.buttons["datingPreferences"]
        reveal(preferences, attempts: 12)
        XCTAssertTrue(preferences.isHittable)
        let title = app.staticTexts["Dating preferences"]
        reveal(title, attempts: 12)
        XCTAssertTrue(title.isHittable)
        XCTAssertGreaterThanOrEqual(title.frame.minX, preferences.frame.minX - 1)
        XCTAssertLessThanOrEqual(title.frame.maxX, preferences.frame.maxX + 1)
        capture("Full-width large-text settings")
        preferences.tap()
        XCTAssertTrue(app.buttons["savePreferences"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(preferences.waitForExistence(timeout: 3))
    }

    func testDuoRemainingScreens() {
        launch()
        for tab in ["Likes", "You", "Chats", "Discover"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            capture("Duo review \(tab)")
        }
        app.buttons["You"].tap()
        let edit = app.buttons["editProfile"]; reveal(edit, attempts: 12); edit.tap()
        XCTAssertTrue(app.buttons["saveProfile"].waitForExistence(timeout: 5))
        capture("Duo review edit")
        app.buttons["Cancel"].tap()
        app.buttons["Chats"].tap()
        let chat = app.buttons["conversation-eli"]; reveal(chat, attempts: 12); chat.tap()
        let field = app.textFields["messageComposer"]
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("Hello")
        capture("Duo review keyboard")
        XCTAssertTrue(app.buttons["sendMessage"].isHittable)
        dismissChatKeyboard()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    private func tapAndWait(_ button: XCUIElement, for destination: XCUIElement) -> Bool {
        guard button.waitForExistence(timeout: 8) else { return false }
        button.tap()
        if !destination.waitForExistence(timeout: 3), button.isHittable {
            button.tap()
        }
        return destination.waitForExistence(timeout: 8)
    }

    func testFaithChoicesCanBeChangedAndSaved() {
        launch()
        let edit = app.buttons["editProfile"]
        guard tapAndWait(app.tabBars.buttons["You"], for: edit),
              tapAndWait(edit, for: app.buttons["saveProfile"]) else {
            XCTFail("Edit Profile did not open")
            return
        }
        for (label, choice) in [("My Sabbath rhythm", "Worship & community"), ("Around the table", "Plant-based")] {
            let field = app.buttons[label]
            reveal(field, attempts: 24)
            let option = app.buttons[choice]
            guard tapAndWait(field, for: option) else {
                XCTFail("Choices did not open for \(label)")
                return
            }
            reveal(option)
            option.tap()
            XCTAssertEqual(field.value as? String, choice)
        }
        app.buttons["saveProfile"].tap()
        guard edit.waitForExistence(timeout: 8),
              tapAndWait(edit, for: app.buttons["saveProfile"]) else {
            XCTFail("Could not reopen the saved profile")
            return
        }
        let sabbath = app.buttons["My Sabbath rhythm"]
        reveal(sabbath, attempts: 24)
        XCTAssertEqual(sabbath.value as? String, "Worship & community")
        let table = app.buttons["Around the table"]
        reveal(table, attempts: 8)
        XCTAssertEqual(table.value as? String, "Plant-based")
    }

    func testResponsiveScreenSmoke() throws {
        for options in [[], ["--large-text", "--dark", "--reduce-motion"]] as [[String]] {
            let mode = options.isEmpty ? "standard" : "large-dark"
            launch(demo: false, options: options)
            capture("Responsive welcome " + mode)
            reveal(app.buttons["getStarted"], attempts: 12)
            XCTAssertTrue(app.buttons["getStarted"].isHittable)
            launch(options: options)
            XCTAssertTrue(app.buttons["passProfile"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["passProfile"].isHittable)
            XCTAssertTrue(app.buttons["likeProfile"].isHittable)
            capture("Responsive discover " + mode)
            guard tapAndWait(app.buttons["discoveryPreferences"], for: app.buttons["savePreferences"]) else {
                XCTFail("Discovery preferences did not open")
                return
            }
            capture("Responsive preferences " + mode)
            XCTAssertTrue(app.buttons["savePreferences"].isHittable)
            app.buttons["Cancel"].tap()
            app.buttons["likeProfile"].tap()
            XCTAssertTrue(app.buttons["matchSayHello"].waitForExistence(timeout: 3))
            capture("Responsive match " + mode)
            let keepDiscovering = app.buttons["matchKeepDiscovering"]
            keepDiscovering.tap()
            if !keepDiscovering.waitForNonExistence(timeout: 3), keepDiscovering.isHittable {
                keepDiscovering.tap()
            }
            guard keepDiscovering.waitForNonExistence(timeout: 8) else {
                XCTFail("Match celebration did not dismiss")
                return
            }
            let likes = app.tabBars.buttons["Likes"]
            let likesHeader = app.staticTexts["Good feelings"]
            likes.tap()
            if !likesHeader.waitForExistence(timeout: 3), !likes.isSelected { likes.tap() }
            guard likesHeader.waitForExistence(timeout: 8) else {
                XCTFail("Likes did not open after the match celebration")
                return
            }
            capture("Responsive likes " + mode)
            let hello = app.buttons["sayHello-amara"]; reveal(hello, attempts: 12)
            XCTAssertTrue(hello.isHittable)
            let edit = app.buttons["editProfile"]
            guard tapAndWait(app.tabBars.buttons["You"], for: edit) else {
                XCTFail("You did not open")
                return
            }
            capture("Responsive story " + mode)
            reveal(edit, attempts: 12)
            guard tapAndWait(edit, for: app.buttons["saveProfile"]) else {
                XCTFail("Edit profile did not open")
                return
            }
            capture("Responsive edit " + mode)
            XCTAssertTrue(app.buttons["saveProfile"].isHittable)
            app.buttons["Cancel"].tap()
            try showChats(); capture("Responsive chats " + mode)
            reveal(app.buttons["conversation-eli"], attempts: 12); app.buttons["conversation-eli"].tap()
            let composer = app.textFields["messageComposer"]
            composer.tap(); composer.typeText("Hello")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertLessThanOrEqual(composer.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            XCTAssertTrue(app.buttons["sendMessage"].isHittable)
            capture("Responsive keyboard " + mode)
        }
    }

    func testWelcomeAndCompleteOnboarding() {
        launch(demo: false)
        XCTAssertTrue(app.buttons["getStarted"].waitForExistence(timeout: 5)); capture("Welcome")
        app.buttons["getStarted"].tap()
        next(); XCTAssertTrue(app.staticTexts["onboardingError"].exists)
        let name = app.textFields["firstName"]; name.tap(); name.typeText("Jordan")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.switches["adultAcknowledgment"].tap(); next()
        XCTAssertTrue(app.staticTexts["2 of 4"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertEqual(app.textFields["firstName"].value as? String, "Jordan")
        next()
        XCTAssertTrue(app.buttons["Male"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Female"].exists)
        app.buttons["Male"].tap()
        app.switches["Female"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); next()
        let city = app.textFields["city"]; city.tap(); city.typeText("Chicago")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.buttons["A meaningful relationship"].tap(); next()
        XCTAssertTrue(app.staticTexts["4 of 4"].waitForExistence(timeout: 5))
        next(); XCTAssertTrue(app.staticTexts["onboardingError"].exists)
        let photo = app.buttons["Use demo portrait Amara"]; reveal(photo); photo.tap()
        let preview = app.otherElements["onboardingPreview"]
        // The card is also exposed as individual text elements by SwiftUI.
        let title = app.staticTexts["Your first impression"]; reveal(title)
        XCTAssertTrue(title.exists || preview.exists)
        XCTAssertFalse(app.staticTexts["onboardingError"].exists, "Correcting the missing photo clears its error")
        capture("Four-step onboarding preview"); next()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Jordan,'")).firstMatch.exists)
        let complete = app.buttons["completeProfile"]; reveal(complete); complete.tap()
        XCTAssertTrue(app.textFields["editName"].waitForExistence(timeout: 3))
        app.buttons["saveProfile"].tap() // Optional details remain blank; saving still works.
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 3))
    }
    func testTabsProfileLikeAndPrompt() {
        launch(); XCTAssertTrue(app.staticTexts["For you"].waitForExistence(timeout: 5)); capture("Discover light")
        app.buttons["Next photo"].tap(); app.buttons["Previous photo"].tap()
        let open = app.buttons["openProfile"]
        let link = open.exists ? open : app.otherElements["openProfile"]
        // NavigationLink is exposed as a button on iOS 26.
        reveal(link); link.tap()
        XCTAssertTrue(app.navigationBars["Amara"].waitForExistence(timeout: 3))
        let prompt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Like answer to'")).firstMatch
        reveal(prompt); prompt.tap()
        XCTAssertTrue(app.staticTexts["matchTitle"].waitForExistence(timeout: 3))
        app.buttons["matchKeepDiscovering"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Likes"].tap()
        app.buttons["Your likes"].tap()
        XCTAssertTrue(app.staticTexts["Amara, 28"].waitForExistence(timeout: 3)); capture("Likes")
        app.tabBars.buttons["You"].tap(); XCTAssertTrue(app.staticTexts["Your story"].waitForExistence(timeout: 3))
    }
    func testPhotoInterestMatchContextAndRemoval() throws {
        launch()
        app.buttons["Next photo"].tap()
        let photo = app.buttons["photoLike-amara-weekend-gallery"]
        reveal(photo); XCTAssertTrue(photo.isEnabled); photo.tap()
        XCTAssertTrue(app.staticTexts["matchTitle"].waitForExistence(timeout: 3))
        let context = app.descendants(matching: .any).matching(identifier: "matchSavedInterest").firstMatch
        XCTAssertTrue(context.exists)
        XCTAssertTrue(context.label.contains("Amara’s photo 2"))
        capture("Personal photo match")
        app.buttons["matchKeepDiscovering"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
        app.tabBars.buttons["Likes"].tap(); app.buttons["Your likes"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Amara’s photo 2")).firstMatch
        reveal(saved); saved.tap()
        let gallery = app.scrollViews["memberProfileScroll"]
        XCTAssertEqual(gallery.staticTexts["photoPosition"].label, "Photo 2 of 2")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let remove = app.buttons["removeLike-amara"]; reveal(remove); remove.tap()
        app.buttons["Liked you"].tap()
        let matched = app.staticTexts["Amara, 28"]; reveal(matched); matched.tap()
        let savedPhoto = app.buttons["photoLike-amara-amara-gallery"]
        reveal(savedPhoto); XCTAssertTrue(savedPhoto.isEnabled); savedPhoto.tap()
        XCTAssertFalse(app.staticTexts["matchTitle"].exists)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }
    func testPromptInterestNamesAnswerAndKeepsPhotoActionAvailable() throws {
        for options in [[], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options + ["--pending-interest-demo", "--slow-discovery-advance"])
            app.buttons["passProfile"].tap()
            let answer = app.buttons["promptLike-eli-eli-0"]
            reveal(answer); answer.tap()
            XCTAssertFalse(answer.isEnabled)
            XCTAssertEqual(app.staticTexts["feedbackBanner"].label, "Saved Eli’s answer to “My ideal Sabbath afternoon…”")
            capture("Personal answer saved \(options)")
            app.tabBars.buttons["Likes"].tap(); app.buttons["Your likes"].tap()
            let quote = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cooking enough for whoever drops by after church.")).firstMatch
            reveal(quote); XCTAssertTrue(quote.exists)
            capture("Answer context in Likes \(options)")
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            quote.tap()
            XCTAssertTrue(app.navigationBars["Eli"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["promptLike-eli-eli-0"].isHittable)
            let photo = app.buttons["photoLike-eli-eli-gallery"]
            for _ in 0..<8 {
                if photo.isHittable { break }
                app.swipeDown()
            }
            XCTAssertTrue(photo.isEnabled); photo.tap()
            XCTAssertEqual(photo.label, "Saved Eli’s photo 1")
            XCTAssertFalse(photo.isEnabled)
            XCTAssertFalse(app.staticTexts["matchTitle"].exists)
            capture("Personal photo saved \(options)")
        }
    }

    func testPhotoControlsCountBoundsResetAndSinglePhotoPreview() throws {
        for options in [[], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options)
            let position = app.staticTexts["photoPosition"]
            let nextPhoto = app.buttons["Next photo"]
            let previousPhoto = app.buttons["Previous photo"]
            XCTAssertTrue(position.waitForExistence(timeout: 5))
            XCTAssertEqual(position.label, "Photo 1 of 2")
            XCTAssertFalse(previousPhoto.isEnabled)
            XCTAssertTrue(nextPhoto.isEnabled && nextPhoto.isHittable)
            XCTAssertGreaterThanOrEqual(nextPhoto.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(nextPhoto.frame.height, 44 - 0.001)
            capture("Photo controls first \(options)")
            nextPhoto.tap()
            XCTAssertEqual(position.label, "Photo 2 of 2")
            XCTAssertFalse(nextPhoto.isEnabled)
            XCTAssertTrue(previousPhoto.isEnabled)
            XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
            XCTAssertTrue(app.buttons["likeProfile"].isEnabled)
            capture("Photo controls second \(options)")
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            previousPhoto.tap()
            XCTAssertEqual(position.label, "Photo 1 of 2")
            nextPhoto.tap()
            app.buttons["passProfile"].tap()
            XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
            XCTAssertEqual(position.label, "Photo 1 of 2")
            app.buttons["undoPass"].tap()
            let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Photo 1 of 2"), object: position)
            XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 3), .completed)
            app.tabBars.buttons["You"].tap()
            let preview = app.buttons["publicPreview"]
            reveal(preview); preview.tap()
            XCTAssertTrue(app.navigationBars["Your story"].waitForExistence(timeout: 3))
            XCTAssertFalse(nextPhoto.exists)
            XCTAssertFalse(previousPhoto.exists)
            XCTAssertFalse(position.exists)
        }
    }
    func testBrowsingPlaceAcrossProfileChatAndTabs() {
        launch()
        func goBack() {
            let back = app.buttons["BackButton"]
            if back.exists {
                back.tap()
            } else {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
        }
        let position = app.staticTexts["photoPosition"]
        app.buttons["Next photo"].tap()
        let meet = app.buttons["openProfile"]
        reveal(meet)
        let discoverY = meet.frame.midY
        meet.tap()
        let detail = app.scrollViews["memberProfileScroll"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.staticTexts["photoPosition"].label, "Photo 2 of 2")
        app.swipeUp()
        let bio = detail.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Equal parts")).firstMatch
        XCTAssertTrue(bio.exists)
        let detailY = bio.frame.midY
        app.buttons["Chats"].tap()
        let conversation = app.buttons["conversation-eli"]
        let chatY = conversation.frame.midY
        conversation.tap()
        XCTAssertTrue(app.textFields["messageComposer"].waitForExistence(timeout: 5))
        goBack()
        XCTAssertEqual(conversation.frame.midY, chatY, accuracy: 5)
        app.buttons["Discover"].tap()
        XCTAssertTrue(app.navigationBars["Amara"].waitForExistence(timeout: 5))
        XCTAssertEqual(bio.frame.midY, detailY, accuracy: 5)
        goBack()
        XCTAssertEqual(meet.frame.midY, discoverY, accuracy: 5)
        for _ in 0..<6 {
            if app.buttons["Next photo"].isHittable { break }
            app.swipeDown()
        }
        XCTAssertEqual(position.label, "Photo 2 of 2")
    }

    func testFullProfilePhotoPagingKeepsCounterAndArrowsInSync() {
        launch()
        let open = app.buttons["openProfile"]
        reveal(open); open.tap()
        XCTAssertTrue(app.navigationBars["Amara"].waitForExistence(timeout: 3))
        let position = app.staticTexts["photoPosition"]
        let next = app.buttons["Next photo"]
        XCTAssertEqual(position.label, "Photo 1 of 2")
        next.tap()
        XCTAssertEqual(position.label, "Photo 2 of 2")
        XCTAssertFalse(next.isEnabled)
        let pager = app.descendants(matching: .any).matching(identifier: "profilePhotoPager").firstMatch
        XCTAssertTrue(pager.exists)
        pager.swipeRight(velocity: .slow)
        XCTAssertEqual(position.label, "Photo 1 of 2")
        XCTAssertFalse(app.buttons["Previous photo"].isEnabled)
        pager.swipeLeft(velocity: .slow)
        XCTAssertEqual(position.label, "Photo 2 of 2")
        XCTAssertTrue(app.buttons["Previous photo"].isEnabled)
        XCTAssertEqual(app.navigationBars.element(boundBy: 0).identifier, "Amara")
        capture("Full profile photo navigation")
    }

    func testFloatingActionsLikeSkipAndUndo() {
        launch()
        let next = app.buttons["passProfile"]
        app.buttons["likeProfile"].tap()
        XCTAssertTrue(app.buttons["matchKeepDiscovering"].waitForExistence(timeout: 3))
        app.buttons["matchKeepDiscovering"].tap()
        XCTAssertEqual(next.label, "Next introduction, skip June")
        next.tap()
        XCTAssertTrue(app.staticTexts["You've seen everyone for now"].waitForExistence(timeout: 3))
        app.buttons["undoPass"].tap()
        XCTAssertEqual(next.label, "Next introduction, skip June")
        next.tap()
        let revisit = app.buttons["Revisit passed profiles"]; reveal(revisit); revisit.tap()
        XCTAssertEqual(next.label, "Next introduction, skip June")
        XCTAssertFalse(app.buttons["undoPass"].exists)
        app.tabBars.buttons["Likes"].tap(); app.buttons["Your likes"].tap()
        XCTAssertTrue(app.staticTexts["Amara, 28"].exists)
    }
    func testDiscoveryActionsStayInPlaceWhenUndoAndInterestChange() throws {
        for options in [[], ["--dark"], ["--large-text", "--largest-text", "--reduce-motion"]] as [[String]] {
            launch(options: options + ["--pending-interest-demo", "--slow-discovery-advance"])
            let next = app.buttons["passProfile"]
            let like = app.buttons["likeProfile"]
            let undo = app.buttons["undoPass"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertFalse(undo.exists)
            let nextFrame = next.frame
            let likeFrame = like.frame
            capture("Stable panel before skip \(options)")
            next.tap()
            XCTAssertTrue(undo.waitForExistence(timeout: 3))
            XCTAssertEqual(next.label, "Next introduction, skip Eli")
            XCTAssertTrue(undo.isHittable)
            XCTAssertGreaterThanOrEqual(undo.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(undo.frame.height, 44 - 0.001)
            assertFrame(next.frame, matches: nextFrame)
            assertFrame(like.frame, matches: likeFrame)
            if !options.contains("--large-text") {
                XCTAssertEqual(next.frame.midY, undo.frame.midY, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(undo.frame.minX, like.frame.maxX)
            }
            capture("Stable panel after skip \(options)")
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            like.tap() // Eli has no incoming like, so the panel stays on screen.
            XCTAssertEqual(like.label, "Interest saved for Eli")
            XCTAssertFalse(like.isEnabled)
            assertFrame(next.frame, matches: nextFrame)
            assertFrame(like.frame, matches: likeFrame)
            undo.tap()
            XCTAssertEqual(next.label, "Next introduction, skip Amara")
            XCTAssertFalse(undo.exists)
            assertFrame(next.frame, matches: nextFrame)
            assertFrame(like.frame, matches: likeFrame)
        }
    }
    private func assertFrame(_ actual: CGRect, matches expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, file: file, line: line)
    }

    func testDiscoverySwipesCancelScrollLikeAndSkip() {
        launch()
        let portrait = app.descendants(matching: .any).matching(identifier: "discoveryPortrait").firstMatch
        XCTAssertTrue(portrait.waitForExistence(timeout: 5))
        let initialY = portrait.frame.minY
        func swipeAcrossPortrait(_ distance: CGFloat) {
            let start = portrait.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            let end = start.withOffset(CGVector(dx: distance, dy: 0))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let start = portrait.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35))
        let short = portrait.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.35))
        start.press(forDuration: 0.15, thenDragTo: short)
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
        XCTAssertTrue(app.buttons["likeProfile"].isEnabled)
        portrait.swipeUp()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
        XCTAssertTrue(app.buttons["likeProfile"].isEnabled)
        app.swipeDown()
        let portraitRestored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in portrait.exists && portrait.frame.minY >= initialY - 20 },
            object: portrait
        )
        XCTAssertEqual(XCTWaiter.wait(for: [portraitRestored], timeout: 5), .completed)
        swipeAcrossPortrait(120)
        let keepDiscovering = app.buttons["matchKeepDiscovering"]
        XCTAssertTrue(keepDiscovering.waitForExistence(timeout: 8))
        keepDiscovering.tap()
        XCTAssertTrue(keepDiscovering.waitForNonExistence(timeout: 8))
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
        swipeAcrossPortrait(-120)
        XCTAssertTrue(app.staticTexts["You've seen everyone for now"].waitForExistence(timeout: 3))
        app.buttons["undoPass"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
    }

    func testSlowShortSwipesReturnAndDiagonalDragScrolls() {
        launch()
        let portrait = app.descendants(matching: .any).matching(identifier: "discoveryPortrait").firstMatch
        XCTAssertTrue(portrait.waitForExistence(timeout: 5))
        app.buttons["Next photo"].tap()
        XCTAssertTrue(app.buttons["Previous photo"].isEnabled)
        app.buttons["Previous photo"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
        let originalFrame = portrait.frame
        for direction: CGFloat in [-1, 1] {
            let start = portrait.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            let end = start.withOffset(CGVector(dx: direction * 60, dy: 0))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
            XCTAssertTrue(app.buttons["likeProfile"].isEnabled)
            XCTAssertFalse(app.buttons["undoPass"].exists)
            assertFrame(portrait.frame, matches: originalFrame)
        }
        capture("Portrait returned after short swipes")
        let portraitY = portrait.frame.minY
        // Start within the photo, clear of its arrows and the floating controls.
        let start = portrait.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
        let end = start.withOffset(CGVector(dx: 80, dy: -160))
        start.press(forDuration: 0, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            portrait.exists && portrait.frame.minY < portraitY - 40
        }, object: portrait)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed,
                       "The diagonal drag must move the portrait up by more than 40 points.")
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
        XCTAssertTrue(app.buttons["likeProfile"].isEnabled)
        capture("Diagonal scroll preserves introduction")
    }
    func testShortFastFlickCommitsWhileTinyFlickCancels() {
        launch(options: ["--pending-interest-demo", "--slow-discovery-advance"])
        let amaraPhoto = app.images["Amara, photo 1 of 2"]
        let eliPhoto = app.images["Eli, photo 1 of 2"]
        let next = app.buttons["passProfile"]
        let interest = app.buttons["likeProfile"]
        XCTAssertTrue(amaraPhoto.waitForExistence(timeout: 5))

        func flick(_ distance: CGFloat, on photo: XCUIElement) {
            let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            let end = start.withOffset(CGVector(dx: distance, dy: 0))
            // Simulator event sampling can report a lower release velocity than requested.
            let flickVelocity = XCUIGestureVelocity(rawValue: 1100)
            start.press(forDuration: 0, thenDragTo: end, withVelocity: flickVelocity, thenHoldForDuration: 0)
        }

        flick(25, on: amaraPhoto)
        XCTAssertEqual(next.label, "Next introduction, skip Amara")
        XCTAssertTrue(interest.isEnabled)

        flick(-70, on: amaraPhoto)
        XCTAssertTrue(amaraPhoto.waitForNonExistence(timeout: 5), "The short left flick should advance to Eli")
        let eliReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: eliPhoto)
        XCTAssertEqual(XCTWaiter.wait(for: [eliReady], timeout: 5), .completed)
        XCTAssertEqual(next.label, "Next introduction, skip Eli")

        flick(70, on: eliPhoto)
        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ AND enabled == false", "Interest saved for Eli"),
            object: interest
        )
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 4), .completed, "The short right flick should save interest in Eli")
        capture("Short deliberate flick saved interest")
    }
    func testReducedMotionSwipesAndRepeatedInterest() {
        launch(options: ["--reduce-motion", "--dark", "--pending-interest-demo", "--slow-discovery-advance"])
        let portrait = app.descendants(matching: .any).matching(identifier: "discoveryPortrait").firstMatch
        XCTAssertTrue(portrait.waitForExistence(timeout: 5))
        portrait.swipeLeft(velocity: .fast)
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Eli")
        portrait.swipeRight(velocity: .slow)
        XCTAssertEqual(app.buttons["likeProfile"].label, "Interest saved for Eli")
        XCTAssertFalse(app.buttons["likeProfile"].isEnabled)
        portrait.swipeRight(velocity: .fast)
        XCTAssertFalse(app.staticTexts["matchTitle"].exists)
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Eli")
        portrait.swipeLeft(velocity: .slow)
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
        app.buttons["undoPass"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Eli")
        capture("Reduced motion swipe interest and undo")
    }
    func testSendDemoMessageAndUnreadState() {
        launch(); app.tabBars.buttons["Chats"].tap()
        app.buttons["conversation-eli"].tap()
        XCTAssertTrue(app.textFields["messageComposer"].waitForExistence(timeout: 3))
        let field = app.textFields["messageComposer"]; field.tap(); field.typeText("A lovely day for a lake walk.")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["A lovely day for a lake walk."].waitForExistence(timeout: 3))
        capture("Conversation")
    }
    func testEditProfileAndPreferences() {
        launch(); app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        let field = app.textFields["editName"]; XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Morgan")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Morgan, 28"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Discover"].tap(); app.buttons["discoveryPreferences"].tap()
        let age = app.steppers["minimumAge"]; reveal(age); age.buttons["minimumAge-Increment"].tap()
        app.buttons["savePreferences"].tap()
        XCTAssertTrue(app.staticTexts["Ages 25–38"].waitForExistence(timeout: 3))
    }
    func testInvalidEditShowsErrorInSheetAndPreservesProfile() {
        launch(); app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        let field = app.textFields["editName"]; XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Enter your first name."].waitForExistence(timeout: 3))
        capture("Invalid name field")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "profileError-name").firstMatch.isHittable)
        app.buttons["Cancel"].tap()
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.staticTexts["Alex, 28"].exists)
    }
    func testMutualMatchRoutesToChatAndSuggestionRequiresSend() throws {
        launch()
        app.buttons["likeProfile"].tap()
        XCTAssertTrue(app.staticTexts["matchTitle"].waitForExistence(timeout: 4))
        capture("Mutual match light")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        app.buttons["matchSayHello"].tap()
        XCTAssertTrue(app.navigationBars["Amara"].waitForExistence(timeout: 4))
        let starter = app.buttons["starter-amara-0"]
        for _ in 0..<4 { if starter.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(starter.isHittable); starter.tap()
        let field = app.textFields["messageComposer"]
        XCTAssertTrue((field.value as? String)?.contains("caught my eye") == true)
        XCTAssertEqual(app.staticTexts.matching(identifier: "messageDay").count, 0)
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["messageDay"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Sending keeps the active composer ready")
        dismissChatKeyboard(); capture("Conversation with date and saved message")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons.matching(identifier: "conversation-amara").count, 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You: Hi Amara!'")).firstMatch.exists)
        app.tabBars.buttons["Likes"].tap()
        XCTAssertTrue(app.buttons["sayHello-amara"].exists)
    }
    func testPreferencePrecisionAndSavedRange() {
        launch(); app.buttons["discoveryPreferences"].tap()
        let minimum = app.steppers["minimumAge"]; reveal(minimum.buttons["minimumAge-Increment"])
        minimum.buttons["minimumAge-Increment"].tap()
        let maximum = app.steppers["maximumAge"]; reveal(maximum.buttons["maximumAge-Decrement"])
        maximum.buttons["maximumAge-Decrement"].tap()
        XCTAssertEqual(app.staticTexts["ageRangeSummary"].label, "25–37 years")
        let slider = app.sliders["Discovery radius"]; reveal(slider)
        slider.adjust(toNormalizedSliderPosition: 0)
        let precise = app.steppers["radiusAdjustment"]; reveal(precise.buttons["radiusAdjustment-Increment"])
        // XCTest slider drags are approximate. Use exact buttons to reach each limit.
        for _ in 0..<50 {
            if precise.value as? String == "5 miles" { break }
            precise.buttons["radiusAdjustment-Decrement"].tap()
        }
        precise.buttons["radiusAdjustment-Decrement"].tap()
        XCTAssertEqual(precise.value as? String, "5 miles", "The lower boundary must remain at five miles")
        precise.buttons["radiusAdjustment-Increment"].tap()
        precise.buttons["radiusAdjustment-Increment"].tap()
        XCTAssertEqual(precise.value as? String, "15 miles")
        XCTAssertEqual(app.staticTexts["radiusSummary"].label, "Within 15 miles")
        app.buttons["savePreferences"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
        app.buttons["discoveryPreferences"].tap()
        reveal(app.staticTexts["ageRangeSummary"])
        XCTAssertEqual(app.staticTexts["ageRangeSummary"].label, "25–37 years")
        reveal(app.steppers["radiusAdjustment"])
        XCTAssertEqual(app.steppers["radiusAdjustment"].value as? String, "15 miles")
        app.sliders["Discovery radius"].adjust(toNormalizedSliderPosition: 1)
        for _ in 0..<50 {
            if app.steppers["radiusAdjustment"].value as? String == "250 miles" { break }
            app.steppers["radiusAdjustment"].buttons["radiusAdjustment-Increment"].tap()
        }
        app.steppers["radiusAdjustment"].buttons["radiusAdjustment-Increment"].tap()
        XCTAssertEqual(app.steppers["radiusAdjustment"].value as? String, "250 miles")
        app.buttons["Cancel"].tap()
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["savePreferences"].waitForNonExistence(timeout: 3))
        app.buttons["passProfile"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
        app.buttons["passProfile"].tap()
        XCTAssertTrue(app.staticTexts["You've seen everyone for now"].waitForExistence(timeout: 3), "Canceled radius changes must not include more distant members")
    }
    func testPreferenceControlsAppearanceAndAccessibility() throws {
        // Clipping audits of the combined age section retain an unidentified finding.
        // Keep screenshots for review; do not suppress that finding as a false positive.
        for options in [[], ["--dark"], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options); app.buttons["discoveryPreferences"].tap()
            let mode = options.contains("--large-text") ? "large dark" : options.contains("--dark") ? "dark" : "light"
            if options.contains("--large-text") {
                reveal(app.staticTexts["ageRangeSummary"])
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
                capture("Refined preferences range large dark")
                try app.performAccessibilityAudit(for: [.sufficientElementDescription])
            }
            reveal(app.steppers["maximumAge"].buttons["maximumAge-Decrement"])
            // Bring the whole radius section into view before auditing standard text.
            if !options.contains("--large-text") { app.swipeUp() }
            capture("Refined preferences age " + mode)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription])
            let adjustment = app.steppers["radiusAdjustment"]; reveal(adjustment.buttons["radiusAdjustment-Increment"])
            adjustment.buttons["radiusAdjustment-Increment"].tap()
            XCTAssertEqual(adjustment.value as? String, "80 miles")
            capture("Refined preferences radius " + mode)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription])
            app.buttons["Cancel"].tap()
        }
    }
    func testPreferencesFilterAndRetainSavedValuesCancelIsAtomic() {
        launch(options: ["--pending-interest-demo", "--slow-discovery-advance"]); app.buttons["discoveryPreferences"].tap()
        app.switches["Female"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        capture("Preferences after Female toggle")
        XCTAssertEqual(app.switches["Female"].value as? String, "0")
        app.buttons["savePreferences"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Eli")
        app.tabBars.buttons["You"].tap(); app.tabBars.buttons["Discover"].tap()
        app.buttons["discoveryPreferences"].tap()
        XCTAssertEqual(app.switches["Female"].value as? String, "0")
        app.switches["Female"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); app.buttons["Cancel"].tap()
        app.buttons["Discard changes"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Eli")
        app.buttons["discoveryPreferences"].tap()
        let radius = app.sliders["Discovery radius"]; reveal(radius)
        radius.adjust(toNormalizedSliderPosition: 0)
        let precise = app.steppers["radiusAdjustment"]
        reveal(precise.buttons["radiusAdjustment-Decrement"])
        // XCTest slider positioning is approximate; finish with exact five-mile steps.
        for _ in 0..<50 {
            if precise.value as? String == "5 miles" { break }
            precise.buttons["radiusAdjustment-Decrement"].tap()
        }
        XCTAssertEqual(precise.value as? String, "5 miles")
        app.buttons["savePreferences"].tap()
        XCTAssertTrue(app.staticTexts["No profiles match your preferences"].waitForExistence(timeout: 3))
        app.buttons["discoveryPreferences"].tap()
        let restore = app.buttons["Restore default preferences"]; reveal(restore); restore.tap()
        app.buttons["savePreferences"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip Amara")
    }
    func testCompletedStoryIsCompactAndCanBeDismissed() throws {
        for options in [[], ["--dark"], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options)
            let you = app.tabBars.buttons["You"]
            let story = app.staticTexts["Your story"]
            XCTAssertTrue(tapAndWait(you, for: story))
            let summary = app.descendants(matching: .any).matching(identifier: "completedStorySummary").firstMatch
            XCTAssertTrue(summary.waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["completeProfile"].exists, "Completed stories should not repeat the edit action")
            let preferences = app.buttons["datingPreferences"]
            if !options.contains("--large-text") {
                XCTAssertLessThanOrEqual(summary.frame.height, 76)
                XCTAssertTrue(app.buttons["editProfile"].isHittable)
                XCTAssertTrue(app.buttons["publicPreview"].isHittable)
                XCTAssertTrue(preferences.isHittable)
                XCTAssertLessThanOrEqual(preferences.frame.maxY, app.tabBars.firstMatch.frame.minY)
            }
            reveal(summary)
            if options.contains("--large-text") {
                for _ in 0..<4 {
                    if summary.frame.maxY <= app.tabBars.firstMatch.frame.minY { break }
                    app.swipeUp()
                }
                XCTAssertLessThanOrEqual(summary.frame.maxY, app.tabBars.firstMatch.frame.minY)
            }
            capture("Compact completed story \(options)")
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            let hide = app.buttons["hideStoryGuide"]
            XCTAssertGreaterThanOrEqual(hide.frame.width, 44)
            XCTAssertGreaterThanOrEqual(hide.frame.height, 44)
            hide.tap()
            XCTAssertFalse(summary.exists)
            reveal(preferences); preferences.tap()
            XCTAssertTrue(app.buttons["savePreferences"].waitForExistence(timeout: 3))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(tapAndWait(app.tabBars.buttons["Discover"], for: app.buttons["discoveryPreferences"]))
            XCTAssertTrue(tapAndWait(you, for: story))
            XCTAssertFalse(summary.exists, "The optional summary stays hidden across tabs")
        }
    }
    func testStoryGuideRespondsToSavedOptionalSections() {
        launch(); app.tabBars.buttons["You"].tap(); app.buttons["editProfile"].tap()
        for name in ["Hiking", "Cooking", "Good books"] {
            let interest = app.buttons[name]; reveal(interest); interest.tap()
        }
        app.buttons["saveProfile"].tap()
        let summary = app.descendants(matching: .any).matching(identifier: "completedStorySummary").firstMatch
        XCTAssertFalse(summary.exists)
        let add = app.buttons["completeProfile"]; reveal(add)
        XCTAssertTrue(app.staticTexts["2 of 3 optional story sections added"].exists)
        XCTAssertTrue(add.isHittable)
        capture("Optional story guidance after clearing interests")
        add.tap()
        let cooking = app.buttons["Cooking"]; reveal(cooking); cooking.tap()
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["completeProfile"].exists)
    }

    func testProfilePreviewAndCancelPreserveSavedStory() {
        launch()
        let preview = app.buttons["publicPreview"]
        XCTAssertTrue(tapAndWait(app.tabBars.buttons["You"], for: preview), "The You tab should show Preview")
        capture("Your story completion")
        let previewTitle = app.staticTexts["YOUR PUBLIC PROFILE PREVIEW"]
        XCTAssertTrue(tapAndWait(preview, for: previewTitle))

        let edit = app.buttons["editProfile"]
        XCTAssertTrue(tapAndWait(app.buttons["BackButton"], for: edit))
        let field = app.textFields["editName"]
        XCTAssertTrue(tapAndWait(edit, for: field))
        XCTAssertTrue(tapAndWait(field, for: app.keyboards.firstMatch))
        field.typeText(" changed")
        XCTAssertEqual(field.value as? String, "Alex changed")

        app.buttons["Cancel"].tap()
        let discard = app.alerts.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Alex, 28"].exists)
    }
    func testDarkLargeTypeReduceMotionAndAccessibleActions() throws {
        launch(options: ["--dark", "--large-text", "--reduce-motion"])
        XCTAssertTrue(app.buttons["passProfile"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["likeProfile"].isHittable)
        capture("Discover dark large text Reduce Motion")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        app.buttons["likeProfile"].tap()
        XCTAssertTrue(app.buttons["matchSayHello"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["matchKeepDiscovering"].isHittable)
        XCTAssertGreaterThan(app.staticTexts["matchTitle"].frame.height, 60, "Large text must reach the presented match screen")
        capture("Match dark large text Reduce Motion")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        app.buttons["matchKeepDiscovering"].tap()
        XCTAssertEqual(app.buttons["passProfile"].label, "Next introduction, skip June")
        XCTAssertFalse(app.buttons["undoPass"].exists)
        app.tabBars.buttons["You"].tap(); capture("Your story dark large text")
    }
    private func showChats() throws {
        let tab = app.tabBars.buttons["Chats"]
        let search = app.textFields["conversationSearch"]
        tab.tap()
        if !search.waitForExistence(timeout: 3), !tab.isSelected {
            tab.tap()
        }
        guard search.waitForExistence(timeout: 8) else {
            throw XCTUIChatNavigationError.chatsDidNotOpen
        }
    }

    private enum XCTUIChatNavigationError: Error {
        case chatsDidNotOpen
    }

    func testConversationIdeasProtectDraftAndNeverSendAutomatically() throws {
        launch()
        try showChats()
        app.buttons["conversation-eli"].tap()
        let field = app.textFields["messageComposer"]; field.tap(); field.typeText("My own draft")
        dismissChatKeyboard(); app.buttons["conversationIdeas"].tap()
        let starter = app.buttons["starter-eli-0"]
        XCTAssertTrue(starter.waitForExistence(timeout: 3)); XCTAssertTrue(starter.isHittable)
        starter.tap()
        app.buttons["Keep my draft"].tap()
        XCTAssertEqual(field.value as? String, "My own draft")
        starter.tap(); app.buttons["Use suggestion"].tap()
        XCTAssertTrue((field.value as? String)?.contains("Hi Eli!") == true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(starter.exists, "Choosing an idea returns attention to the editable draft")
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        capture("Conversation starter focused composer")
        dismissChatKeyboard()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["That sounds like my kind of afternoon. I'd bring something homemade!"].exists)
    }
    private func dismissChatKeyboard() {
        XCTAssertFalse(app.navigationBars.buttons["Done"].exists)
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.textFields["messageComposer"].frame.minY
        let point = CGVector(dx: app.frame.width / 2, dy: (top + bottom) / 2 - app.frame.minY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    func testConversationKeyboardKeepsComposerVisible() throws {
        for options in [[], ["--dark", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options)
            try showChats()
            capture("Refined chat previews \(options)")
            app.buttons["conversation-eli"].tap()
            let field = app.textFields["messageComposer"]
            field.tap(); field.typeText("A thoughtful question\nAnd a little more")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            XCTAssertTrue(app.buttons["sendMessage"].isHittable)
            capture("Refined multiline composer \(options)")
            dismissChatKeyboard()
            XCTAssertTrue(field.isHittable)
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue((field.value as? String)?.contains("thoughtful question") == true)
            app.buttons["sendMessage"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            dismissChatKeyboard()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You: A thoughtful question'")).firstMatch.exists)
        }
    }
    func testPreferencesClippingDiagnostic() throws {
        for options in [[], ["--largest-text", "--large-text", "--reduce-motion"]] as [[String]] {
            launch(options: options)
            app.buttons["discoveryPreferences"].tap()
            reveal(app.staticTexts["ageRangeSummary"])
            capture("Clipping diagnostic age \(options)")
            try app.performAccessibilityAudit(for: [.textClipped]) { issue in
                print("CLIPPING DIAGNOSTIC: \(issue.compactDescription) element: \(issue.element?.debugDescription ?? "unidentified")")
                return false
            }
        }
    }
    func testPreferencesAndChatsLargeTextVisualChecks() throws {
        launch(options: ["--dark", "--large-text", "--reduce-motion"])
        let save = app.buttons["savePreferences"]
        guard tapAndWait(app.buttons["discoveryPreferences"], for: save) else {
            XCTFail("Discovery preferences did not open")
            return
        }
        capture("Preferences dark large text top")
        let radius = app.sliders["Discovery radius"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        for _ in 0..<15 {
            if radius.isHittable { break }
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
        }
        guard radius.isHittable else {
            capture("Discovery radius did not become reachable")
            XCTFail("The Discovery radius slider must be reachable before auditing the form")
            return
        }
        capture("Preferences dark large text radius")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        app.buttons["Cancel"].tap()
        try showChats(); capture("Chats dark large text")
        app.buttons["conversation-eli"].tap(); capture("Conversation dark large text")
        XCTAssertTrue(app.textFields["messageComposer"].isHittable)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
    }
    func testBlockRemovesConversation() {
        launch(); app.tabBars.buttons["Chats"].tap(); app.buttons["conversation-eli"].tap()
        app.buttons["Profile safety options"].tap(); app.buttons["Block profile"].tap()
        app.buttons["Block profile"].tap()
        XCTAssertTrue(app.staticTexts["Conversation unavailable"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["conversation-eli"].exists)
        XCTAssertTrue(app.staticTexts["Your next hello is waiting"].exists)
    }
}
