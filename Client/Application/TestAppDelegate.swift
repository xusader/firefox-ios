/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

class TestAppDelegate: AppDelegate {
    override func getProfile(application: UIApplication) -> Profile {
        // Use a clean profile for each test session.
        let profile = BrowserProfile(localName: "testProfile", app: application)
        profile.files.removeFilesInDirectory()
        profile.prefs.clearAll()

        // Skip the first run UI.
        profile.prefs.setInt(1, forKey: IntroViewControllerSeenProfileKey)

        return profile
    }

    // Prevent app state from being saved/restored between tests.
    override func application(application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        return false
    }

    override func application(application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        return false
    }
}