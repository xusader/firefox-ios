/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import XCTest

import Storage
import WebKit

class ClientTests: XCTestCase {
    func testArrayCursor() {
        let data = ["One", "Two", "Three"];
        let t = ArrayCursor<String>(data: data);
        
        // Test subscript access
        XCTAssertNil(t[-1], "Subscript -1 returns nil");
        XCTAssertEqual(t[0]!, "One", "Subscript zero returns the correct data");
        XCTAssertEqual(t[1]!, "Two", "Subscript one returns the correct data");
        XCTAssertEqual(t[2]!, "Three", "Subscript two returns the correct data");
        XCTAssertNil(t[3], "Subscript three returns nil");

        // Test status data with default initializer
        XCTAssertEqual(t.status, CursorStatus.Success, "Cursor as correct status");
        XCTAssertEqual(t.statusMessage, "Success", "Cursor as correct status message");
        XCTAssertEqual(t.count, 3, "Cursor as correct size");

        // Test generator access
        var i = 0;
        for s in t {
            XCTAssertEqual(s!, data[i], "Subscript zero returns the correct data");
            i++;
        }

        // Test creating a failed cursor
        let t2 = ArrayCursor<String>(data: data, status: CursorStatus.Failure, statusMessage: "Custom status message");
        XCTAssertEqual(t2.status, CursorStatus.Failure, "Cursor as correct status");
        XCTAssertEqual(t2.statusMessage, "Custom status message", "Cursor as correct status message");
        XCTAssertEqual(t2.count, 0, "Cursor as correct size");

        // Test subscript access return nil for a failed cursor
        XCTAssertNil(t2[0], "Subscript zero returns nil if failure");
        XCTAssertNil(t2[1], "Subscript one returns nil if failure");
        XCTAssertNil(t2[2], "Subscript two returns nil if failure");
        XCTAssertNil(t2[3], "Subscript three returns nil if failure");
    
        // Test that generator doesn't work with failed cursors
        var ran = false;
        for s in t2 {
            println("Got \(s)")
            ran = true;
        }
        XCTAssertFalse(ran, "for...in didn't run for failed cursor");
    }

    // Simple test to make sure the WKWebView UA matches the expected FxiOS pattern.
    func testUserAgent() {
        let expectation = expectationWithDescription("Found Firefox user agent")

        let webView = WKWebView()
        webView.evaluateJavaScript("navigator.userAgent") { result, error in
            let userAgent = result as! String
            let appVersion = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
            let range = userAgent.rangeOfString("^Mozilla/5\\.0 \\(.+\\) AppleWebKit/[0-9\\.]+ \\(KHTML, like Gecko\\) FxiOS/\(appVersion) Mobile/[A-Z0-9]+ Safari/[0-9\\.]+$", options: NSStringCompareOptions.RegularExpressionSearch)

            if range != nil {
                expectation.fulfill()
            } else {
                XCTFail("User agent did not match expected pattern! \(userAgent)")
            }
        }

        waitForExpectationsWithTimeout(5, handler: nil)
    }
}
