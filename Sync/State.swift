
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

/**
 * This file includes types that manage intra-sync and inter-sync metadata
 * for the use of synchronizers and the state machine.
 *
 * See docs/sync.md for details on what exactly we need to persist.
 */

public struct Fetched<T> {
    let value: T
    let timestamp: UInt64
}

/**
 * The scratchpad consists of the following:
 *
 * 1. Cached records. We cache meta/global and crypto/keys until they change.
 * 2. Metadata like timestamps.
 *
 * Note that the scratchpad itself is immutable, but is a class passed by reference.
 * Its mutable fields can be mutated, but you can't accidentally e.g., switch out
 * meta/global and get confused.
 */
public class Scratchpad {
    let syncKeyBundle: KeyBundle

    // Cached records.
    let global: Fetched<MetaGlobal>?
    let keys: Fetched<Keys>?

    // Collection timestamps.
    var collectionLastFetched: [String: UInt64]

    init(b: KeyBundle) {
        self.syncKeyBundle = b
        self.collectionLastFetched = [String: UInt64]()
    }

    init(b: KeyBundle, m: Fetched<MetaGlobal>?, k: Fetched<Keys>?, fetches: [String: UInt64]) {
        self.syncKeyBundle = b
        self.keys = k
        self.global = m
        self.collectionLastFetched = fetches
    }

    convenience init(b: KeyBundle, m: Fetched<MetaGlobal>?, k: Fetched<Keys>?) {
        self.init(b: b, m: m, k: k, fetches: [String: UInt64]())
    }

    convenience init(b: KeyBundle, m: GlobalEnvelope?, k: Fetched<Keys>?, fetches: [String: UInt64]) {
        var fetchedGlobal: Fetched<MetaGlobal>? = nil
        if let m = m {
            if let global = m.global {
                fetchedGlobal = Fetched<MetaGlobal>(value: global, timestamp: m.modified)
            }
        }
        self.init(b: b, m: fetchedGlobal, k: k, fetches: fetches)
    }

    func withGlobal(m: Fetched<MetaGlobal>?) -> Scratchpad {
        let s = Scratchpad(b: self.syncKeyBundle, m: m, k: self.keys, fetches: self.collectionLastFetched)
        if let timestamp = m?.timestamp {
            s.collectionLastFetched["meta"] = timestamp
        }
        return s
    }

    func withGlobal(m: MetaGlobal, t: UInt64) -> Scratchpad {
        return withGlobal(Fetched(value: m, timestamp: t))
    }

    func withGlobal(m: GlobalEnvelope) -> Scratchpad {
        return withGlobal(m.toFetched())
    }

    func withKeys(k: Keys, t: UInt64) -> Scratchpad {
        let f = Fetched(value: k, timestamp: t)
        let s = Scratchpad(b: self.syncKeyBundle, m: self.global, k: f, fetches: self.collectionLastFetched)
        s.collectionLastFetched["crypto"] = t
        return s
    }
}