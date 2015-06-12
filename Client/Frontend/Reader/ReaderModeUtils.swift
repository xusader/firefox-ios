/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

struct ReaderModeUtils {

    static let DomainPrefixesToSimplify = ["www.", "mobile.", "m.", "blog."]

    static func simplifyDomain(domain: String) -> String {
        for prefix in DomainPrefixesToSimplify {
            if domain.hasPrefix(prefix) {
                return domain.substringFromIndex(advance(domain.startIndex, count(prefix)))
            }
        }
        return domain
    }

    static func generateReaderContent(readabilityResult: ReadabilityResult, initialStyle: ReaderModeStyle) -> String? {
        if let stylePath = NSBundle.mainBundle().pathForResource("Reader", ofType: "css") {
            if let css = NSString(contentsOfFile: stylePath, encoding: NSUTF8StringEncoding, error: nil) {
                if let tmplPath = NSBundle.mainBundle().pathForResource("Reader", ofType: "html") {
                    if let tmpl = NSMutableString(contentsOfFile: tmplPath, encoding: NSUTF8StringEncoding, error: nil) {
                        tmpl.replaceOccurrencesOfString("%READER-CSS%", withString: css as String,
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        tmpl.replaceOccurrencesOfString("%READER-STYLE%", withString: initialStyle.encode(),
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        tmpl.replaceOccurrencesOfString("%READER-DOMAIN%", withString: simplifyDomain(readabilityResult.domain),
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        tmpl.replaceOccurrencesOfString("%READER-URL%", withString: readabilityResult.url,
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        tmpl.replaceOccurrencesOfString("%READER-TITLE%", withString: readabilityResult.title,
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        tmpl.replaceOccurrencesOfString("%READER-CREDITS%", withString: readabilityResult.credits,
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        tmpl.replaceOccurrencesOfString("%READER-CONTENT%", withString: readabilityResult.content,
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        tmpl.replaceOccurrencesOfString("%WEBSERVER-BASE%", withString: WebServer.sharedInstance.base,
                            options: NSStringCompareOptions.allZeros, range: NSMakeRange(0, tmpl.length))

                        return tmpl as String
                    }
                }
            }
        }
        return nil
    }

    static func isReaderModeURL(url: NSURL) -> Bool {
        if let scheme = url.scheme, host = url.host, path = url.path {
            return scheme == "http" && host == "localhost" && path == "/reader-mode/page"
        }
        return false
    }

    static func decodeURL(url: NSURL) -> NSURL? {
        if ReaderModeUtils.isReaderModeURL(url) {
            if let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false), queryItems = components.queryItems where queryItems.count == 1 {
                if let queryItem = queryItems.first as? NSURLQueryItem, value = queryItem.value {
                    return NSURL(string: value)
                }
            }
        }
        return nil
    }

    static func encodeURL(url: NSURL?) -> NSURL? {
        let baseReaderModeURL: String = WebServer.sharedInstance.URLForResource("page", module: "reader-mode")
        if let absoluteString = url?.absoluteString {
            if let encodedURL = absoluteString.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.alphanumericCharacterSet()) {
                if let aboutReaderURL = NSURL(string: "\(baseReaderModeURL)?url=\(encodedURL)") {
                    return aboutReaderURL
                }
            }
        }
        return nil
    }
}