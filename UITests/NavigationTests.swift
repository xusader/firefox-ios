/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit

class NavigationTests: KIFTestCase, UITextFieldDelegate {
    private var webRoot: String!

    override func setUp() {
        webRoot = SimplePageServer.start()
    }

    /**
     * Tests basic page navigation with the URL bar.
     */
    func testNavigation() {
        tester().tapViewWithAccessibilityIdentifier("url")
        var textView = tester().waitForViewWithAccessibilityLabel("Address and Search") as? UITextField
        XCTAssertTrue(textView!.text.isEmpty, "Text is empty")
        XCTAssertNotNil(textView!.placeholder, "Text view has a placeholder to show when its empty")

        let url1 = "\(webRoot)/numberedPage.html?page=1"
        tester().clearTextFromAndThenEnterText("\(url1)\n", intoViewWithAccessibilityLabel: "Address and Search")
        tester().waitForWebViewElementWithAccessibilityLabel("Page 1")

        tester().tapViewWithAccessibilityIdentifier("url")
        textView = tester().waitForViewWithAccessibilityLabel("Address and Search") as? UITextField
        XCTAssertEqual(textView!.text, url1, "Text is url")

        let url2 = "\(webRoot)/numberedPage.html?page=2"
        tester().clearTextFromAndThenEnterText("\(url2)\n", intoViewWithAccessibilityLabel: "Address and Search")
        tester().waitForWebViewElementWithAccessibilityLabel("Page 2")

        tester().tapViewWithAccessibilityLabel("Back")
        tester().waitForWebViewElementWithAccessibilityLabel("Page 1")

        tester().tapViewWithAccessibilityLabel("Forward")
        tester().waitForWebViewElementWithAccessibilityLabel("Page 2")
    }

    func testScrollsToTopWithMultipleTabs() {
        // test scrollsToTop works with 1 tab
        tester().tapViewWithAccessibilityIdentifier("url")
        let url = "\(webRoot)/scrollablePage.html?page=1"
        tester().clearTextFromAndThenEnterText("\(url)\n", intoViewWithAccessibilityLabel: "Address and Search")
        tester().waitForWebViewElementWithAccessibilityLabel("Top")

//        var webView = tester().waitForViewWithAccessibilityLabel("Web content") as? WKWebView
        tester().scrollViewWithAccessibilityIdentifier("contentView", byFractionOfSizeHorizontal: -0.9, vertical: -0.9)
        tester().waitForWebViewElementWithAccessibilityLabel("Bottom")

        tester().tapStatusBar()
        tester().waitForWebViewElementWithAccessibilityLabel("Top")

        // now open another tab and test it works too
        tester().tapViewWithAccessibilityLabel("Show Tabs")
        var addTabButton = tester().waitForViewWithAccessibilityLabel("Add Tab") as? UIButton
        addTabButton?.tap()
        tester().waitForViewWithAccessibilityLabel("Web content")
        let url2 = "\(webRoot)/scrollablePage.html?page=2"
        tester().tapViewWithAccessibilityIdentifier("url")
        tester().clearTextFromAndThenEnterText("\(url2)\n", intoViewWithAccessibilityLabel: "Address and Search")
        tester().waitForWebViewElementWithAccessibilityLabel("Top")

        tester().scrollViewWithAccessibilityIdentifier("contentView", byFractionOfSizeHorizontal: -0.9, vertical: -0.9)
        tester().waitForWebViewElementWithAccessibilityLabel("Bottom")

        tester().tapStatusBar()
        tester().waitForWebViewElementWithAccessibilityLabel("Top")
    }

    override func tearDown() {
        BrowserUtils.resetToAboutHome(tester())
    }
}
