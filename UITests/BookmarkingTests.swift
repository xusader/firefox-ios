/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit

class BookmarkingTests: KIFTestCase, UITextFieldDelegate {
    private var webRoot: String!

    override func setUp() {
        webRoot = SimplePageServer.start()
    }

    /**
     * Tests basic page navigation with the URL bar.
     */
    func testBookmarkingUI() {
        // Load a page
        tester().tapViewWithAccessibilityIdentifier("url")
        let url1 = "\(webRoot)/numberedPage.html?page=1"
        tester().clearTextFromAndThenEnterText("\(url1)\n", intoViewWithAccessibilityLabel: "Address and Search")
        tester().waitForWebViewElementWithAccessibilityLabel("Page 1")

        // Bookmark it using the bookmark button
        tester().tapViewWithAccessibilityLabel("Bookmark")
        let bookmarkButton = tester().waitForViewWithAccessibilityLabel("Bookmark") as! UIButton
        XCTAssertTrue(bookmarkButton.selected, "Bookmark button is marked selected")

        // Load a different page in a new tab
        tester().tapViewWithAccessibilityLabel("Show Tabs")
        tester().tapViewWithAccessibilityLabel("Add Tab")

        tester().tapViewWithAccessibilityIdentifier("url")
        let url2 = "\(webRoot)/numberedPage.html?page=2"
        tester().clearTextFromAndThenEnterText("\(url2)\n", intoViewWithAccessibilityLabel: "Address and Search")
        tester().waitForWebViewElementWithAccessibilityLabel("Page 2")

        // Check that the bookmark button is no longer selected
        XCTAssertFalse(bookmarkButton.selected, "Bookmark button is not marked selected")

        // Now switch back to the original tab
        tester().tapViewWithAccessibilityLabel("Show Tabs")
        tester().tapViewWithAccessibilityLabel("Page 1")
        XCTAssertTrue(bookmarkButton.selected, "Bookmark button is marked selected")

        // Check that it appears in the bookmarks home panel
        tester().tapViewWithAccessibilityIdentifier("url")
        tester().tapViewWithAccessibilityLabel("Bookmarks")
        let bookmarkRow = tester().waitForViewWithAccessibilityLabel("Page 1") as! UITableViewCell
        XCTAssertNotNil(bookmarkRow.imageView?.image)

        // Tap to open it
        tester().tapViewWithAccessibilityLabel("Page 1")
        tester().waitForWebViewElementWithAccessibilityLabel("Page 1")

        // Unbookmark it using the bookmark button
        tester().tapViewWithAccessibilityLabel("Bookmark")
        XCTAssertFalse(bookmarkButton.selected, "Bookmark button is not selected")

        // Check that it no longer appears in the bookmarks home panel
        tester().tapViewWithAccessibilityIdentifier("url")
        tester().tapViewWithAccessibilityLabel("Bookmarks")
        tester().waitForAbsenceOfViewWithAccessibilityLabel("Page 1")
        tester().tapViewWithAccessibilityLabel("Cancel")
    }

    func testBookmarkNoTitle() {
        // Load a page with no title
        tester().tapViewWithAccessibilityIdentifier("url")
        let url1 = "\(webRoot)/noTitle.html"
        tester().clearTextFromAndThenEnterText("\(url1)\n", intoViewWithAccessibilityLabel: "Address and Search")
        tester().waitForWebViewElementWithAccessibilityLabel("This page has no title")

        // Bookmark it using the bookmark button
        tester().tapViewWithAccessibilityLabel("Bookmark")
        var bookmarkButton = tester().waitForViewWithAccessibilityLabel("Bookmark") as! UIButton
        XCTAssertTrue(bookmarkButton.selected, "Bookmark button is marked selected")

        // Check that its row in the bookmarks panel has a url instead of a title
        tester().tapViewWithAccessibilityIdentifier("url")
        tester().tapViewWithAccessibilityLabel("Bookmarks")
        tester().waitForAbsenceOfViewWithAccessibilityLabel("Page 1")
        // XXX: Searching for the table cell directly here can result in finding the wrong view.
        let cell = tester().waitForCellAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), inTableViewWithAccessibilityIdentifier: "SiteTable")
        XCTAssertEqual(cell.textLabel!.text!, url1, "Cell shows url")

        tester().tapViewWithAccessibilityLabel("Cancel")
    }

    override func tearDown() {
        BrowserUtils.resetToAboutHome(tester())
    }
}
