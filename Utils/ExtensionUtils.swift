/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import MobileCoreServices
import Storage

struct ExtensionUtils {
    /// Small structure to encapsulate all the possible data that we can get from an application sharing a web page or a url.


    /// Look through the extensionContext for a url and title. Walks over all inputItems and then over all the attachments.
    /// Has a completionHandler because ultimately an XPC call to the sharing application is done.
    /// We can always extract a URL and sometimes a title. The favicon is currently just a placeholder, but future code can possibly interact with a web page to find a proper icon.
    static func extractSharedItemFromExtensionContext(extensionContext: NSExtensionContext?, completionHandler: (ShareItem?, NSError!) -> Void) {
        if extensionContext != nil {
            if let inputItems : [NSExtensionItem] = extensionContext!.inputItems as? [NSExtensionItem] {
                for inputItem in inputItems {
                    if let attachments = inputItem.attachments as? [NSItemProvider] {
                        for attachment in attachments {
                            if attachment.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                                attachment.loadItemForTypeIdentifier(kUTTypeURL as String, options: nil, completionHandler: { (obj, err) -> Void in
                                    if err != nil {
                                        completionHandler(nil, err)
                                    } else {
                                        let title = inputItem.attributedContentText?.string as String?
                                        if let url = obj as? NSURL {
                                            completionHandler(ShareItem(url: url.absoluteString!, title: title, favicon: nil), nil)
                                        } else {
                                            completionHandler(nil, NSError(domain: "org.mozilla.fennec", code: 999, userInfo: ["Problem": "Non-URL result."]))
                                        }
                                    }
                                })
                                return
                            }
                        }
                    }
                }
            }
        }
        completionHandler(nil, nil)
    }
    
    /// Return the shared container identifier (also known as the app group) to be used with for example background
    /// http requests. It is the base bundle identifier with a "group." prefix.
    static func sharedContainerIdentifier() -> String? {
        if let baseBundleIdentifier = ExtensionUtils.baseBundleIdentifier() {
            return "group." + baseBundleIdentifier
        } else {
            return nil
        }
    }

    /// Return the keychain access group.
    static func keychainAccessGroupWithPrefix(prefix: String) -> String? {
        if let baseBundleIdentifier = ExtensionUtils.baseBundleIdentifier() {
            return prefix + "." + baseBundleIdentifier
        } else {
            return nil
        }
    }

    /// Return the base bundle identifier.
    ///
    /// This function is smart enough to find out if it is being called from an extension or the main application. In
    /// case of the former, it will chop off the extension identifier from the bundle since that is a suffix not part
    /// of the *base* bundle identifier.
    static func baseBundleIdentifier() -> String? {
        let bundle = NSBundle.mainBundle()
        if let packageType = bundle.objectForInfoDictionaryKey("CFBundlePackageType") as? NSString {
            if let baseBundleIdentifier = bundle.bundleIdentifier {
                if packageType == "XPC!" {
                    let components = baseBundleIdentifier.componentsSeparatedByString(".")
                    return ".".join(components[0..<components.count-1])
                } else {
                    return baseBundleIdentifier
                }
            }
        }
        return nil
    }
}
