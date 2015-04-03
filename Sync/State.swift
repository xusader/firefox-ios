
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
    public class Builder {
        var syncKeyBundle: KeyBundle         // For the love of god, if you change this, invalidate keys, too!
        private var global: Fetched<MetaGlobal>?
        private var keys: Fetched<Keys>?
        var collectionLastFetched: [String: UInt64]
        var engineConfiguration: EngineConfiguration?
        var clientRecordLastUpload: UInt64 = 0
        var clientName: String

        init(p: Scratchpad) {
            self.syncKeyBundle = p.syncKeyBundle
            self.global = p.global
            self.collectionLastFetched = p.collectionLastFetched
            self.engineConfiguration = p.engineConfiguration
            self.clientRecordLastUpload = p.clientRecordLastUpload
            self.clientName = p.clientName
        }

        public func setKeys(keys: Fetched<Keys>?) -> Builder {
            self.keys = keys
            if let keys = keys {
                self.collectionLastFetched["crypto"] = keys.timestamp
            }
            return self
        }

        public func setGlobal(global: Fetched<MetaGlobal>?) -> Builder {
            self.global = global
            if let global = global {
                self.collectionLastFetched["meta"] = global.timestamp
            }
            return self
        }

        public func build() -> Scratchpad {
            return Scratchpad(
                    b: self.syncKeyBundle,
                    m: self.global,
                    k: self.keys,
                    fetches: self.collectionLastFetched,
                    engines: self.engineConfiguration,
                    clientUpload: self.clientRecordLastUpload,
                    clientName: self.clientName
            )
        }
    }

    public func evolve() -> Scratchpad.Builder {
        return Scratchpad.Builder(p: self)
    }

    let syncKeyBundle: KeyBundle

    // Cached records.
    // This cached meta/global is what we use to add or remove enabled engines. See also
    // engineConfiguration, below.
    // We also use it to detect when meta/global hasn't changed -- compare timestamps.
    //
    // Note that a Scratchpad held by a Ready state will have the current server meta/global
    // here. That means we don't need to track syncIDs separately (which is how desktop and
    // Android are implemented).
    // If we don't have a meta/global, and thus we don't know syncIDs, it means we haven't
    // synced with this server before, and we'll do a fresh sync.
    let global: Fetched<MetaGlobal>?
    let keys: Fetched<Keys>?

    // Collection timestamps.
    var collectionLastFetched: [String: UInt64]

    // Enablement states.
    let engineConfiguration: EngineConfiguration?       // TODO: should this be optional?

    // When did we last upload our client record?
    let clientRecordLastUpload: UInt64

    // What's our client name?
    let clientName: String

    class func defaultClientName() -> String {
        return "Firefox"   // TODO
    }

    init(b: KeyBundle,
         m: Fetched<MetaGlobal>?,
         k: Fetched<Keys>?,
         fetches: [String: UInt64],
         engines: EngineConfiguration?,
         clientUpload: UInt64,
         clientName: String) {
        self.syncKeyBundle = b
        self.keys = k
        self.global = m
        self.collectionLastFetched = fetches
        self.clientRecordLastUpload = clientUpload
        self.clientName = clientName
    }

    // This should never be used in the end; we'll unpickle instead.
    // This should be a convenience initializer, but... Swift compiler bug?
    init(b: KeyBundle) {
        self.syncKeyBundle = b
        self.keys = nil
        self.global = nil
        self.collectionLastFetched = [String: UInt64]()
        self.clientRecordLastUpload = 0
        self.clientName = Scratchpad.defaultClientName()
    }

    /*
    convenience init(b: KeyBundle, m: Fetched<MetaGlobal>?, k: Fetched<Keys>?, fetches: [String: UInt64]) {
        self.init(b: b, m: m, k: k, fetches: fetches, engines: nil, clientUpload: 0, clientName: Scratchpad.defaultClientName())
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
    */

    func withGlobal(m: Fetched<MetaGlobal>?) -> Scratchpad {
        return self.evolve().setGlobal(m).build()
    }

    func withGlobal(m: MetaGlobal, t: UInt64) -> Scratchpad {
        return withGlobal(Fetched(value: m, timestamp: t))
    }

    func withGlobal(m: GlobalEnvelope) -> Scratchpad {
        return withGlobal(m.toFetched())
    }

    func withKeys(k: Fetched<Keys>?) -> Scratchpad {
        return self.evolve().setKeys(k).build()
    }

    func withKeys(k: Keys, t: UInt64) -> Scratchpad {
        return withKeys(Fetched(value: k, timestamp: t))
    }
}