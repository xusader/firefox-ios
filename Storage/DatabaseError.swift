/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

/**
 * Used to bridge the NSErrors we get here into something that Result is happy with.
 */
public class DatabaseError: ErrorType {
    let err: NSError?

    public var description: String {
        return err?.localizedDescription ?? "Unknown database error."
    }

    init(err: NSError?) {
        self.err = err
    }
}