/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared

protocol TabManagerDelegate: class {
    func tabManager(tabManager: TabManager, didSelectedTabChange selected: Browser?, previous: Browser?)
    func tabManager(tabManager: TabManager, didCreateTab tab: Browser)
    func tabManager(tabManager: TabManager, didAddTab tab: Browser, atIndex: Int)
    func tabManager(tabManager: TabManager, didRemoveTab tab: Browser, atIndex index: Int)
}

// We can't use a WeakList here because this is a protocol.
class WeakTabManagerDelegate {
    weak var value : TabManagerDelegate?

    init (value: TabManagerDelegate) {
        self.value = value
    }

    func get() -> TabManagerDelegate? {
        return value
    }
}

// TabManager must extend NSObjectProtocol in order to implement WKNavigationDelegate
class TabManager : NSObject {
    private var delegates = [WeakTabManagerDelegate]()

    func addDelegate(delegate: TabManagerDelegate) {
        assert(NSThread.isMainThread())
        delegates.append(WeakTabManagerDelegate(value: delegate))
    }

    func removeDelegate(delegate: TabManagerDelegate) {
        assert(NSThread.isMainThread())
        for var i = 0; i < delegates.count; i++ {
            var del = delegates[i]
            if delegate === del.get() {
                delegates.removeAtIndex(i)
                return
            }
        }
    }

    private var tabs: [Browser] = []
    private var _selectedIndex = -1
    var selectedIndex: Int { return _selectedIndex }
    private let defaultNewTabRequest: NSURLRequest
    private let navDelegate: TabManagerNavDelegate
    private var configuration: WKWebViewConfiguration
    let storage: RemoteClientsAndTabs?

    private let prefs: Prefs

    init(defaultNewTabRequest: NSURLRequest, storage: RemoteClientsAndTabs? = nil, prefs: Prefs) {
        // Create a common webview configuration with a shared process pool.
        configuration = WKWebViewConfiguration()
        configuration.processPool = WKProcessPool()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !(prefs.boolForKey("blockPopups") ?? true)

        self.defaultNewTabRequest = defaultNewTabRequest
        self.storage = storage
        self.navDelegate = TabManagerNavDelegate()
        self.prefs = prefs
        super.init()

        addNavigationDelegate(self)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "prefsDidChange", name: NSUserDefaultsDidChangeNotification, object: nil)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    func addNavigationDelegate(delegate: WKNavigationDelegate) {
        self.navDelegate.insert(delegate)
    }

    var count: Int {
        return tabs.count
    }

    var selectedTab: Browser? {
        if !(0..<count ~= _selectedIndex) {
            return nil
        }

        return tabs[_selectedIndex]
    }

    subscript(index: Int) -> Browser? {
        if index >= tabs.count {
            return nil
        }
        return tabs[index]
    }

    subscript(webView: WKWebView) -> Browser? {
        for tab in tabs {
            if tab.webView === webView {
                return tab
            }
        }

        return nil
    }

    func selectTab(tab: Browser?) {
        assert(NSThread.isMainThread())

        if selectedTab === tab {
            return
        }

        let previous = selectedTab

        _selectedIndex = -1
        for i in 0..<count {
            if tabs[i] === tab {
                _selectedIndex = i
                break
            }
        }

        assert(tab === selectedTab, "Expected tab is selected")
        selectedTab?.createWebview()

        for delegate in delegates {
            delegate.get()?.tabManager(self, didSelectedTabChange: tab, previous: previous)
        }
    }

    // This method is duplicated to hide the flushToDisk option from consumers.
    func addTab(var request: NSURLRequest! = nil, configuration: WKWebViewConfiguration! = nil) -> Browser {
        return self.addTab(request: request, configuration: configuration, flushToDisk: true, zombie: false)
    }

    func addTab(var request: NSURLRequest! = nil, configuration: WKWebViewConfiguration! = nil, flushToDisk: Bool, zombie: Bool) -> Browser {
        assert(NSThread.isMainThread())

        configuration?.preferences.javaScriptCanOpenWindowsAutomatically = !(prefs.boolForKey("blockPopups") ?? true)

        let tab = Browser(configuration: configuration ?? self.configuration)

        for delegate in delegates {
            delegate.get()?.tabManager(self, didCreateTab: tab)
        }

        tabs.append(tab)

        for delegate in delegates {
            delegate.get()?.tabManager(self, didAddTab: tab, atIndex: tabs.count - 1)
        }

        if !zombie {
            tab.createWebview()
        }
        tab.navigationDelegate = self.navDelegate
        tab.loadRequest(request ?? defaultNewTabRequest)

        if flushToDisk {
        	storeChanges()
        }

        return tab
    }

    // This method is duplicated to hide the flushToDisk option from consumers.
    func removeTab(tab: Browser) {
        self.removeTab(tab, flushToDisk: true)
    }

    private func removeTab(tab: Browser, flushToDisk: Bool) {
        assert(NSThread.isMainThread())
        // If the removed tab was selected, find the new tab to select.
        if tab === selectedTab {
            let index = getIndex(tab)
            if index + 1 < count {
                selectTab(tabs[index + 1])
            } else if index - 1 >= 0 {
                selectTab(tabs[index - 1])
            } else {
                assert(count == 1, "Removing last tab")
                selectTab(nil)
            }
        }

        let prevCount = count
        var index = -1
        for i in 0..<count {
            if tabs[i] === tab {
                tabs.removeAtIndex(i)
                index = i
                break
            }
        }
        assert(count == prevCount - 1, "Tab removed")

        // There's still some time between this and the webView being destroyed.
        // We don't want to pick up any stray events.
        tab.webView?.navigationDelegate = nil

        for delegate in delegates {
            delegate.get()?.tabManager(self, didRemoveTab: tab, atIndex: index)
        }

        if flushToDisk {
        	storeChanges()
        }
    }

    func removeAll() {
        let tabs = self.tabs

        for tab in tabs {
            self.removeTab(tab, flushToDisk: false)
        }
        storeChanges()
    }

    func getIndex(tab: Browser) -> Int {
        for i in 0..<count {
            if tabs[i] === tab {
                return i
            }
        }
        
        assertionFailure("Tab not in tabs list")
        return -1
    }

    private func storeChanges() {
        // It is possible that not all tabs have loaded yet, so we filter out tabs with a nil URL.
        let storedTabs: [RemoteTab] = optFilter(tabs.map(Browser.toTab))
        storage?.insertOrUpdateTabs(storedTabs)
    }

    func prefsDidChange() {
        let allowPopups = !(prefs.boolForKey("blockPopups") ?? true)
        for tab in tabs {
            tab.webView?.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
        }
    }
}

extension TabManager {
    class SavedTab: NSObject, NSCoding {
        let url: NSURL?
        let isSelected: Bool
        let screenshot: UIImage?

        init?(browser: Browser, isSelected: Bool) {
            self.url = browser.url
            self.screenshot = browser.screenshot
            self.isSelected = isSelected

            super.init()

            if browser.url == nil {
                return nil
            }
        }

        required init(coder: NSCoder) {
            self.url = coder.decodeObjectForKey("url") as? NSURL
            self.screenshot = coder.decodeObjectForKey("screenshot") as? UIImage
            self.isSelected = coder.decodeBoolForKey("isSelected")
        }

        func encodeWithCoder(coder: NSCoder) {
            coder.encodeObject(url, forKey: "url")
            coder.encodeObject(screenshot, forKey: "screenshot")
            coder.encodeBool(isSelected, forKey: "isSelected")
        }
    }

    func encodeRestorableStateWithCoder(coder: NSCoder) {
        var savedTabs = [SavedTab]()
        for (tabIndex, tab) in enumerate(tabs) {
            if let savedTab = SavedTab(browser: tab, isSelected: tabIndex == selectedIndex) {
                savedTabs.append(savedTab)
            }
        }
        coder.encodeObject(savedTabs, forKey: "tabs")
    }

    func decodeRestorableStateWithCoder(coder: NSCoder) {
        var tabToSelect: Browser?
        if let savedTabs = coder.decodeObjectForKey("tabs") as? [SavedTab] {
            for savedTab in savedTabs {
                if let url = savedTab.url, updatedURL = WebServer.sharedInstance.updateLocalURL(url) {
                    let tab = self.addTab(request: NSURLRequest(URL: updatedURL), flushToDisk: false, zombie: true)
                    tab.screenshot = savedTab.screenshot
                    if savedTab.isSelected {
                        tabToSelect = tab
                    }
                }
            }
        }
        selectTab(tabToSelect ?? tabs.first)
    }
}

extension TabManager : WKNavigationDelegate {
    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        storeChanges()
    }
}

// WKNavigationDelegates must implement NSObjectProtocol
class TabManagerNavDelegate : NSObject, WKNavigationDelegate {
    private var delegates = WeakList<WKNavigationDelegate>()

    func insert(delegate: WKNavigationDelegate) {
        delegates.insert(delegate)
    }

    func webView(webView: WKWebView, didCommitNavigation navigation: WKNavigation!) {
        for delegate in delegates {
            delegate.webView?(webView, didCommitNavigation: navigation)
        }
    }

    func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
        for delegate in delegates {
            delegate.webView?(webView, didFailNavigation: navigation, withError: error)
        }
    }

    func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: NSError) {
            for delegate in delegates {
                delegate.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
            }
    }

    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        for delegate in delegates {
            delegate.webView?(webView, didFinishNavigation: navigation)
        }
    }

    func webView(webView: WKWebView, didReceiveAuthenticationChallenge challenge: NSURLAuthenticationChallenge,
        completionHandler: (NSURLSessionAuthChallengeDisposition,
        NSURLCredential!) -> Void) {
            var disp: NSURLSessionAuthChallengeDisposition? = nil
            for delegate in delegates {
                delegate.webView?(webView, didReceiveAuthenticationChallenge: challenge) { (disposition, credential) in
                    // Whoever calls this method first wins. All other calls are ignored.
                    if disp != nil {
                        return
                    }

                    disp = disposition
                    completionHandler(disposition, credential)
                }
            }
    }

    func webView(webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        for delegate in delegates {
            delegate.webView?(webView, didReceiveServerRedirectForProvisionalNavigation: navigation)
        }
    }

    func webView(webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        for delegate in delegates {
            delegate.webView?(webView, didStartProvisionalNavigation: navigation)
        }
    }

    func webView(webView: WKWebView, decidePolicyForNavigationAction navigationAction: WKNavigationAction,
        decisionHandler: (WKNavigationActionPolicy) -> Void) {
            var res = WKNavigationActionPolicy.Allow
            for delegate in delegates {
                delegate.webView?(webView, decidePolicyForNavigationAction: navigationAction, decisionHandler: { policy in
                    if policy == .Cancel {
                        res = policy
                    }
                })
            }

            decisionHandler(res)
    }

    func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse,
        decisionHandler: (WKNavigationResponsePolicy) -> Void) {
            var res = WKNavigationResponsePolicy.Allow
            for delegate in delegates {
                delegate.webView?(webView, decidePolicyForNavigationResponse: navigationResponse, decisionHandler: { policy in
                    if policy == .Cancel {
                        res = policy
                    }
                })
            }

            decisionHandler(res)
    }
}
