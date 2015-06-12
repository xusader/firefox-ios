/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Storage
import XCGLogger
import WebKit

private let log = XCGLogger.defaultInstance()

private let SaveButtonTitle = NSLocalizedString("Save", comment: "Button to save the user's password")
private let NotNowButtonTitle = NSLocalizedString("Not now", comment: "Button to not save the user's password")
private let UpdateButtonTitle = NSLocalizedString("Update", comment: "Button to update the user's password")
private let CancelButtonTitle = NSLocalizedString("Cancel", comment: "Authentication prompt cancel button")
private let LogInButtonTitle  = NSLocalizedString("Log in", comment: "Authentication prompt log in button")

class LoginsHelper: BrowserHelper {
    private weak var browser: Browser?
    private let profile: Profile
    private var snackBar: SnackBar?
    private static let MaxAuthenticationAttempts = 3

    class func name() -> String {
        return "LoginsHelper"
    }

    required init(browser: Browser, profile: Profile) {
        self.browser = browser
        self.profile = profile

        if let path = NSBundle.mainBundle().pathForResource("LoginsHelper", ofType: "js") {
            if let source = NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding, error: nil) as? String {
                var userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.AtDocumentEnd, forMainFrameOnly: true)
                browser.webView!.configuration.userContentController.addUserScript(userScript)
            }
        }
    }

    func scriptMessageHandlerName() -> String? {
        return "loginsManagerMessageHandler"
    }

    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        var res = message.body as! [String: String]
        let type = res["type"]
        if let url = browser?.url {
            if type == "request" {
                res["username"] = ""
                res["password"] = ""
                let login = Login.fromScript(url, script: res)
                requestLogins(login, requestId: res["requestId"]!)
            } else if type == "submit" {
                setCredentials(Login.fromScript(url, script: res))
            }
        }
    }

    class func replace(base: String, keys: [String], replacements: [String]) -> NSMutableAttributedString {
        var ranges = [NSRange]()
        var string = base
        for (index, key) in enumerate(keys) {
            let replace = replacements[index]
            let range = string.rangeOfString(key,
                options: NSStringCompareOptions.LiteralSearch,
                range: nil,
                locale: nil)!
            string.replaceRange(range, with: replace)
            let nsRange = NSMakeRange(distance(string.startIndex, range.startIndex),
                count(replace))
            ranges.append(nsRange)
        }

        var attributes = [NSObject: AnyObject]()
        attributes[NSFontAttributeName] = UIFont.systemFontOfSize(13, weight: UIFontWeightRegular)
        attributes[NSForegroundColorAttributeName] = UIColor.darkGrayColor()
        var attr = NSMutableAttributedString(string: string, attributes: attributes)
        for (index, range) in enumerate(ranges) {
            attr.addAttribute(NSFontAttributeName, value: UIFont.systemFontOfSize(13, weight: UIFontWeightMedium), range: range)
        }
        return attr
    }

    private func setCredentials(login: LoginData) {
        if login.password.isEmpty {
            log.debug("Empty password")
            return
        }

        profile.logins.getLoginsForProtectionSpace(login.protectionSpace).uponQueue(dispatch_get_main_queue()) { res in
            if let data = res.successValue {
                for saved in data {
                    if saved?.username == login.username {
                        if saved?.password == login.password {
                            self.profile.logins.addUseOf(login)
                            return
                        }

                        self.promptUpdate(login)
                        return
                    }
                }
            }

            self.promptSave(login)
        }
    }

    private func promptSave(login: LoginData) {
        let promptMessage: NSAttributedString
        if let username = login.username {
            let promptStringFormat = NSLocalizedString("Do you want to save the password for %@ on %@?", comment: "Prompt for saving a password. The first parameter is the username being saved. The second parameter is the hostname of the site.")
            promptMessage = NSAttributedString(string: String(format: promptStringFormat, username, login.hostname))
        } else {
            let promptStringFormat = NSLocalizedString("Do you want to save the password on %@?", comment: "Prompt for saving a password with no username. The parameter is the hostname of the site.")
            promptMessage = NSAttributedString(string: String(format: promptStringFormat, login.hostname))
        }

        if snackBar != nil {
            browser?.removeSnackbar(snackBar!)
        }

        snackBar = CountdownSnackBar(attrText: promptMessage,
            img: UIImage(named: "lock_verified"),
            buttons: [
                SnackButton(title: SaveButtonTitle, callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    self.profile.logins.addLogin(login)
                }),

                SnackButton(title: NotNowButtonTitle, callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    return
                })
            ])
        browser?.addSnackbar(snackBar!)
    }

    private func promptUpdate(login: LoginData) {
        let formatted: String
        if let username = login.username {
            let promptStringFormat = NSLocalizedString("Do you want to update the password for %@ on %@?", comment: "Prompt for updating a password. The first parameter is the username being saved. The second parameter is the hostname of the site.")
            formatted = String(format: promptStringFormat, username, login.hostname)
        } else {
            let promptStringFormat = NSLocalizedString("Do you want to update the password on %@?", comment: "Prompt for updating a password with on username. The parameter is the hostname of the site.")
            formatted = String(format: promptStringFormat, login.hostname)
        }
        let promptMessage = NSAttributedString(string: formatted)

        if snackBar != nil {
            browser?.removeSnackbar(snackBar!)
        }

        snackBar = CountdownSnackBar(attrText: promptMessage,
            img: UIImage(named: "lock_verified"),
            buttons: [
                SnackButton(title: UpdateButtonTitle, callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    self.profile.logins.updateLogin(login)
                }),
                SnackButton(title: NotNowButtonTitle, callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    return
                })
            ])
        browser?.addSnackbar(snackBar!)
    }

    private func requestLogins(login: LoginData, requestId: String) {
        profile.logins.getLoginsForProtectionSpace(login.protectionSpace).uponQueue(dispatch_get_main_queue()) { res in
            var jsonObj = [String: AnyObject]()
            if let cursor = res.successValue {
                jsonObj["requestId"] = requestId
                jsonObj["name"] = "RemoteLogins:loginsFound"
                jsonObj["logins"] = map(cursor, { $0!.toDict() })
            }

            let json = JSON(jsonObj)
            let src = "window.__firefox__.logins.inject(\(json.toString()))"
            self.browser?.webView?.evaluateJavaScript(src, completionHandler: { (obj, err) -> Void in
            })
        }
    }

    func handleAuthRequest(viewController: UIViewController, challenge: NSURLAuthenticationChallenge) -> Deferred<Result<LoginData>> {
        // If there have already been too many login attempts, we'll just fail.
        if challenge.previousFailureCount >= LoginsHelper.MaxAuthenticationAttempts {
            return deferResult(LoginDataError(description: "Too many attempts to open site"))
        }

        var credential = challenge.proposedCredential

        // If we were passed an initial set of credentials from iOS, try and use them.
        if let proposed = credential {
            if !(proposed.user?.isEmpty ?? true) {
                if challenge.previousFailureCount == 0 {
                    return deferResult(Login.createWithCredential(credential!, protectionSpace: challenge.protectionSpace))
                }
            } else {
                credential = nil
            }
        }

        if let credential = credential {
            // If we have some credentials, we'll show a prompt with them.
            return promptForUsernamePassword(viewController, credentials: credential, protectionSpace: challenge.protectionSpace)
        }

        // Otherwise, try to look one up
        let options = QueryOptions(filter: challenge.protectionSpace.host, filterType: .None, sort: .None)
        return profile.logins.getLoginsForProtectionSpace(challenge.protectionSpace).bindQueue(dispatch_get_main_queue()) { res in
            let credentials = res.successValue?[0]?.credentials
            return self.promptForUsernamePassword(viewController, credentials: credentials, protectionSpace: challenge.protectionSpace)
        }
    }

    private func promptForUsernamePassword(viewController: UIViewController, credentials: NSURLCredential?, protectionSpace: NSURLProtectionSpace) -> Deferred<Result<LoginData>> {
        if protectionSpace.host.isEmpty {
            println("Unable to show a password prompt without a hostname")
            return deferResult(LoginDataError(description: "Unable to show a password prompt without a hostname"))
        }

        let deferred = Deferred<Result<LoginData>>()
        let alert: UIAlertController
        let title = NSLocalizedString("Authentication required", comment: "Authentication prompt title")
        if !(protectionSpace.realm?.isEmpty ?? true) {
            let msg = NSLocalizedString("A username and password are being requested by %@. The site says: %@", comment: "Authentication prompt message with a realm. First parameter is the hostname. Second is the realm string")
            let formatted = NSString(format: msg, protectionSpace.host, protectionSpace.realm ?? "") as String
            alert = UIAlertController(title: title, message: formatted, preferredStyle: UIAlertControllerStyle.Alert)
        } else {
            let msg = NSLocalizedString("A username and password are being requested by %@.", comment: "Authentication prompt message with no realm. Parameter is the hostname of the site")
            let formatted = NSString(format: msg, protectionSpace.host) as String
            alert = UIAlertController(title: title, message: formatted, preferredStyle: UIAlertControllerStyle.Alert)
        }

        // Add a button to log in.
        let action = UIAlertAction(title: LogInButtonTitle,
            style: UIAlertActionStyle.Default) { (action) -> Void in
                let user = (alert.textFields?[0] as! UITextField).text
                let pass = (alert.textFields?[1] as! UITextField).text

                let login = Login.createWithCredential(NSURLCredential(user: user, password: pass, persistence: .ForSession), protectionSpace: protectionSpace)
                deferred.fill(Result(success: login))
                self.setCredentials(login)
        }
        alert.addAction(action)

        // Add a cancel button.
        let cancel = UIAlertAction(title: CancelButtonTitle, style: UIAlertActionStyle.Cancel) { (action) -> Void in
            deferred.fill(Result(failure: LoginDataError(description: "Save password cancelled")))
        }
        alert.addAction(cancel)

        // Add a username textfield.
        alert.addTextFieldWithConfigurationHandler { (textfield) -> Void in
            textfield.placeholder = NSLocalizedString("Username", comment: "Username textbox in Authentication prompt")
            textfield.text = credentials?.user
        }

        // Add a password textfield.
        alert.addTextFieldWithConfigurationHandler { (textfield) -> Void in
            textfield.placeholder = NSLocalizedString("Password", comment: "Password textbox in Authentication prompt")
            textfield.secureTextEntry = true
            textfield.text = credentials?.password
        }
        
        viewController.presentViewController(alert, animated: true) { () -> Void in }
        return deferred
    }
    
}
