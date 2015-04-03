/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Account
import XCGLogger

// TODO: same comment as for SyncAuthState.swift!
private let log = XCGLogger.defaultInstance()

private let STORAGE_VERSION_CURRENT = 5
private let ENGINES_DEFAULT: [String: Int] = ["tabs": 1]
private let DECLINED_DEFAULT: [String] = [String]()

private func getDefaultEngines() -> [String: EngineMeta] {
    return mapValues(ENGINES_DEFAULT, { EngineMeta(version: $0, syncID: Bytes.generateGUID()) })
}

public typealias TokenSource = () -> Deferred<Result<TokenServerToken>>

// See docs in docs/sync.md.

// You might be wondering why this doesn't have a Sync15StorageClient like FxALoginStateMachine
// does. Well, such a client is pinned to a particular server, and this state machine must
// acknowledge that a Sync client occasionally must migrate between two servers, preserving
// some state from the last.
// The resultant 'Ready' will have a suitably initialized storage client.
public class SyncStateMachine {
    // TODO: unbundle persisted values into the Scratchpad.

    public class func getInfoCollections(authState: SyncAuthState) -> Deferred<Result<InfoCollections>> {
        log.debug("Fetching info/collections in state machine.")
        let token = authState.token(NSDate.now(), canBeExpired: true)
        return chainDeferred(token, { (token, kB) in
            log.debug("Got token from auth state.")
            let state = InitialWithExpiredToken(scratchpad: Scratchpad(b: KeyBundle.fromKB(kB)), token: token)
            return state.getInfoCollections()
        })
    }

    public class func toReady(authState: SyncAuthState) -> Deferred<Result<Ready>> {
        let token = authState.token(NSDate.now(), canBeExpired: false)
        return chainDeferred(token, { (token, kB) in
            log.debug("Got token from auth state. Server is \(token.api_endpoint).")
            let state = InitialWithLiveToken(scratchpad: Scratchpad(b: KeyBundle.fromKB(kB)), token: token)
            return advanceSyncState(state)
        })
    }
}

public enum SyncStateLabel: String {
    case Stub = "STUB"     // For 'abstract' base classes.

    case InitialWithExpiredToken = "initialWithExpiredToken"
    case InitialWithExpiredTokenAndInfo = "initialWithExpiredTokenAndInfo"
    case InitialWithLiveToken = "initialWithLiveToken"
    case InitialWithLiveTokenAndInfo = "initialWithLiveTokenAndInfo"
    case ResolveMetaGlobal = "resolveMetaGlobal"
    case HasMetaGlobal = "hasMetaGlobal"
    case Restart = "restart"                                  // Go around again... once only, perhaps.
    case Ready = "ready"

    case ChangedServer = "changedServer"
    case MissingMetaGlobal = "missingMetaGlobal"
    case MissingCryptoKeys = "missingCryptoKeys"
    case MalformedCryptoKeys = "malformedCryptoKeys"
    case SyncIDChanged = "syncIDChanged"

    static let allValues: [SyncStateLabel] = [
        InitialWithExpiredToken,
        InitialWithExpiredTokenAndInfo,
        InitialWithLiveToken,
        InitialWithLiveTokenAndInfo,
        ResolveMetaGlobal,
        HasMetaGlobal,
        Restart,
        Ready,

        ChangedServer,
        MissingMetaGlobal,
        MissingCryptoKeys,
        MalformedCryptoKeys,
        SyncIDChanged,
    ]
}

/**
 * States in this state machine all implement SyncState.
 *
 * States are either successful main-flow states, or (recoverable) error states.
 * Errors that aren't recoverable are simply errors.
 * Main-flow states flow one to one.
 *
 * (Terminal failure states might be introduced at some point.)
 *
 * Multiple error states (but typically only one) can arise from each main state transition.
 * For example, parsing meta/global can result in a number of different non-routine situations.
 *
 * For these reasons, and the lack of useful ADTs in Swift, we model the main flow as
 * the success branch of a Result, and the recovery flows as a part of the failure branch.
 *
 * We could just as easily use a ternary Either-style operator, but thanks to Swift's
 * optional-cast-let it's no saving to do so.
 *
 * Because of the lack of type system support, all RecoverableSyncStates must have the same
 * signature. That signature implies a possibly multi-state transition; individual states
 * will have richer type signatures.
 */
public protocol SyncState {
    var label: SyncStateLabel { get }
}

/*
 * Base classes to avoid repeating initializers all over the place.
 */
public class BaseSyncState: SyncState {
    public var label: SyncStateLabel { return SyncStateLabel.Stub }

    let client: Sync15StorageClient!
    let token: TokenServerToken    // Maybe expired.
    var scratchpad: Scratchpad

    // TODO: 304 for i/c.
    public func getInfoCollections() -> Deferred<Result<InfoCollections>> {
        return chain(self.client.getInfoCollections(), {
            return $0.value
        })
    }

    public init(client: Sync15StorageClient, scratchpad: Scratchpad, token: TokenServerToken) {
        self.scratchpad = scratchpad
        self.token = token
        self.client = client
        log.info("Inited \(self.label.rawValue)")
    }

    // This isn't a convenience initializer 'cos subclasses can't call convenience initializers.
    public init(scratchpad: Scratchpad, token: TokenServerToken) {
        let workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let resultQueue = dispatch_get_main_queue()
        let client = Sync15StorageClient(token: token, workQueue: workQueue, resultQueue: resultQueue)
        self.scratchpad = scratchpad
        self.token = token
        self.client = client
        log.info("Inited \(self.label.rawValue)")
    }
}

public class BaseSyncStateWithInfo: BaseSyncState {
    let info: InfoCollections

    init(client: Sync15StorageClient, scratchpad: Scratchpad, token: TokenServerToken, info: InfoCollections) {
        self.info = info
        super.init(client: client, scratchpad: scratchpad, token: token)
    }

    init(scratchpad: Scratchpad, token: TokenServerToken, info: InfoCollections) {
        self.info = info
        super.init(scratchpad: scratchpad, token: token)
    }
}

/*
 * Error types.
 */
public protocol SyncError: ErrorType {}

public class UnknownError: SyncError {
    public var description: String {
        return "Unknown error."
    }
}

public class CouldNotFetchMetaGlobalError: SyncError {
    public var description: String {
        return "Could not fetch meta/global."
    }
}

public class CouldNotFetchKeysError: SyncError {
    public var description: String {
        return "Could not fetch crypto/keys."
    }
}

/*
 * Error states. These are errors that can be recovered from by taking actions.
 */

public protocol RecoverableSyncState: SyncState, SyncError {
    // All error states must be able to advance to a usable state.
    func advance() -> Deferred<Result<SyncState>>
}

/**
 * Recovery: discard our local timestamps and sync states; discard caches.
 * Be prepared to handle a conflict between our selected engines and the new
 * server's meta/global; if an engine is selected locally but not declined
 * remotely, then we'll need to upload a new meta/global and sync that engine.
 */
public class ChangedServerError: RecoverableSyncState {
    public var label: SyncStateLabel { return SyncStateLabel.ChangedServer }

    public var description: String {
        return "Token destination changed to \(self.newToken.api_endpoint)/\(self.newToken.uid)."
    }

    let newToken: TokenServerToken
    let syncKeyBundle: KeyBundle

    public init(scratchpad: Scratchpad, token: TokenServerToken) {
        self.newToken = token
        self.syncKeyBundle = scratchpad.syncKeyBundle
    }

    public func advance() -> Deferred<Result<SyncState>> {
        // TODO: mutate local storage to allow for a fresh start.
        let state = InitialWithLiveToken(scratchpad: Scratchpad(b: self.syncKeyBundle), token: newToken)
        return Deferred(value: Result(success: state))
    }
}

/**
 * Recovery: same as for changed server, but no need to upload a new meta/global.
 */
public class SyncIDChangedError: RecoverableSyncState {
    public var label: SyncStateLabel { return SyncStateLabel.SyncIDChanged }

    public var description: String {
        return "Global sync ID changed."
    }

    private let previousState: BaseSyncStateWithInfo
    private let newMetaGlobal: Fetched<MetaGlobal>

    public init(previousState: BaseSyncStateWithInfo, newMetaGlobal: Fetched<MetaGlobal>) {
        self.previousState = previousState
        self.newMetaGlobal = newMetaGlobal
    }

    public func advance() -> Deferred<Result<SyncState>> {
        // TODO: mutate local storage to allow for a fresh start.
        let s = self.previousState.scratchpad.evolve().setGlobal(self.newMetaGlobal).setKeys(nil).build()
        let state = HasMetaGlobal(client: self.previousState.client, scratchpad: s, token: self.previousState.token, info: self.previousState.info)
        return Deferred(value: Result(success: state))
    }
}

/**
 * Recovery: wipe the server (perhaps unnecessarily), upload a new meta/global,
 * do a fresh start.
 */
public class MissingMetaGlobalError: RecoverableSyncState {
    public var label: SyncStateLabel { return SyncStateLabel.MissingMetaGlobal }

    public var description: String {
        return "Missing meta/global."
    }

    private let previousState: BaseSyncStateWithInfo

    public init(previousState: BaseSyncStateWithInfo) {
        self.previousState = previousState
    }

    // TODO: this needs EnginePreferences.
    private class func createMetaGlobal(previous: MetaGlobal?, scratchpad: Scratchpad) -> MetaGlobal {
        return MetaGlobal(syncID: Bytes.generateGUID(), storageVersion: STORAGE_VERSION_CURRENT, engines: getDefaultEngines(), declined: DECLINED_DEFAULT)
    }

    private func onWiped(resp: StorageResponse<JSON>, s: Scratchpad) -> Deferred<Result<SyncState>> {
        // Upload a new meta/global.
        // Note that we discard info/collections -- we just wiped storage.
        return Deferred(value: Result(success: InitialWithLiveToken(client: self.previousState.client, scratchpad: s, token: self.previousState.token)))
    }

    private func advanceFromWiped(wipe: Deferred<Result<StorageResponse<JSON>>>) -> Deferred<Result<SyncState>> {
        // TODO: mutate local storage to allow for a fresh start.
        // Note that we discard the previous global and keys -- after all, we just wiped storage.

        let s = self.previousState.scratchpad.evolve().setGlobal(nil).setKeys(nil).build()
        return chainDeferred(wipe, { self.onWiped($0, s: s) })
    }

    public func advance() -> Deferred<Result<SyncState>> {
        return self.advanceFromWiped(self.previousState.client.wipeStorage())
    }
}

public class InvalidKeysError: ErrorType {
    let keys: Keys

    public init(_ keys: Keys) {
        self.keys = keys
    }

    public var description: String {
        return "Invalid crypto/keys."
    }
}

/*
 * Real states.
 */

public class InitialWithExpiredToken: BaseSyncState {
    public override var label: SyncStateLabel { return SyncStateLabel.InitialWithExpiredToken }

    // This looks totally redundant, but try taking it out, I dare you.
    public override init(scratchpad: Scratchpad, token: TokenServerToken) {
        super.init(scratchpad: scratchpad, token: token)
    }

    func advanceWithInfo(info: InfoCollections) -> InitialWithExpiredTokenAndInfo {
        return InitialWithExpiredTokenAndInfo(scratchpad: self.scratchpad, token: self.token, info: info)
    }

    public func advanceIfNeeded(previous: InfoCollections?, collections: [String]?) -> Deferred<Result<InitialWithExpiredTokenAndInfo?>> {
        return chain(getInfoCollections(), { info in
            // Unchanged or no previous state? Short-circuit.
            if let previous = previous {
                if info.same(previous, collections: collections) {
                    return nil
                }
            }

            // Changed? Move to the next state with the fetched info.
            return self.advanceWithInfo(info)
        })
    }
}

public class InitialWithExpiredTokenAndInfo: BaseSyncStateWithInfo {
    public override var label: SyncStateLabel { return SyncStateLabel.InitialWithExpiredTokenAndInfo }

    public func advanceWithToken(liveTokenSource: TokenSource) -> Deferred<Result<InitialWithLiveTokenAndInfo>> {
        return chainResult(liveTokenSource(), { token in
            if self.token.sameDestination(token) {
                return Result(success: InitialWithLiveTokenAndInfo(scratchpad: self.scratchpad, token: token, info: self.info))
            }

            // Otherwise, we're screwed: we need to start over.
            // Pass in the new token, of course.
            return Result(failure: ChangedServerError(scratchpad: self.scratchpad, token: token))
        })
    }
}

public class InitialWithLiveToken: BaseSyncState {
    public override var label: SyncStateLabel { return SyncStateLabel.InitialWithLiveToken }

    // This looks totally redundant, but try taking it out, I dare you.
    public override init(scratchpad: Scratchpad, token: TokenServerToken) {
        super.init(scratchpad: scratchpad, token: token)
    }

    // This looks totally redundant, but try taking it out, I dare you.
    public override init(client: Sync15StorageClient, scratchpad: Scratchpad, token: TokenServerToken) {
        super.init(client: client, scratchpad: scratchpad, token: token)
    }

    func advanceWithInfo(info: InfoCollections) -> InitialWithLiveTokenAndInfo {
        return InitialWithLiveTokenAndInfo(scratchpad: self.scratchpad, token: self.token, info: info)
    }

    public func advance() -> Deferred<Result<InitialWithLiveTokenAndInfo>> {
        return chain(getInfoCollections(), self.advanceWithInfo)
    }
}

/**
 * Each time we fetch a new meta/global, we need to reconcile it with our
 * current state.
 *
 * It might be identical to our current meta/global, in which case we can short-circuit.
 *
 * We might have no previous meta/global at all, in which case this state
 * simply configures local storage to be ready to sync according to the
 * supplied meta/global. (Not necessarily datatype elections: those will be per-device.)
 *
 * Or it might be different. In this case the previous m/g and our local user preferences
 * are compared to the new, resulting in some actions and a final state.
 *
 * TODO
 */
public class ResolveMetaGlobal: BaseSyncStateWithInfo {
    public override var label: SyncStateLabel { return SyncStateLabel.ResolveMetaGlobal }

    let fetched: Fetched<MetaGlobal>

    init(fetched: Fetched<MetaGlobal>, client: Sync15StorageClient, scratchpad: Scratchpad, token: TokenServerToken, info: InfoCollections) {
        self.fetched = fetched
        super.init(client: client, scratchpad: scratchpad, token: token, info: info)
    }

    class func fromState(state: BaseSyncStateWithInfo, fetched: Fetched<MetaGlobal>) -> ResolveMetaGlobal {
        return ResolveMetaGlobal(fetched: fetched, client: state.client, scratchpad: state.scratchpad, token: state.token, info: state.info)
    }

    func advance() -> Deferred<Result<HasMetaGlobal>> {
        // TODO: detect when the global syncID has changed.
        // TODO: detect when an individual collection syncID has changed, and make sure that
        //       collection is reset.
        // TODO: detect when the sets of declined or enabled engines have changed, and update
        //       our preferences accordingly.

        let s = self.scratchpad.withGlobal(fetched)
        let state = HasMetaGlobal.fromState(self, scratchpad: s)

        return Deferred(value: Result(success: state))
    }
}

public class InitialWithLiveTokenAndInfo: BaseSyncStateWithInfo {
    public override var label: SyncStateLabel { return SyncStateLabel.InitialWithLiveTokenAndInfo }

    private func processFailure(failure: ErrorType?) -> ErrorType {
        if let failure = failure as? NotFound<StorageResponse<GlobalEnvelope>> {
            // OK, this is easy.
            // This state is responsible for creating the new m/g, uploading it, and
            // restarting with a clean scratchpad.
            return MissingMetaGlobalError(previousState: self)
        }

        // TODO: backoff etc. for all of these.
        if let failure = failure as? ServerError<StorageResponse<GlobalEnvelope>> {
            // Be passive.
            return failure
        }

        if let failure = failure as? BadRequestError<StorageResponse<GlobalEnvelope>> {
            // Uh oh.
            log.error("Bad request. Bailing out. \(failure.description)")
            return failure
        }

        log.error("Unexpected failure. \(failure?.description)")
        return failure ?? UnknownError()
    }

    func advanceToMG() -> Deferred<Result<HasMetaGlobal>> {
        // Cached and not changed in i/c? Use that.
        // This check would be inaccurate if any other fields were stored in meta/; this
        // has been the case in the past, with the Sync 1.1 migration indicator.
        if let global = self.scratchpad.global {
            if let metaModified = self.info.modified("meta") {
                if global.timestamp == metaModified {
                    // Strictly speaking we can avoid fetching if this condition is not true,
                    // but if meta/ is modified for a different reason -- store timestamps
                    // for the last collection fetch. This will do for now.
                    let newState = HasMetaGlobal.fromState(self)
                    return Deferred(value: Result(success: newState))
                }
            }
        }

        // Fetch.
        return self.client.getMetaGlobal().bind { result in
            if let resp = result.successValue?.value {
                if let fetched = resp.toFetched() {
                    let next = ResolveMetaGlobal.fromState(self, fetched: fetched)
                    return next.advance()
                }

                // This should not occur.
                log.error("Unexpectedly no meta/global despite a successful fetch.")
            }

            // Otherwise, we have a failure state.
            return Deferred(value: Result(failure: self.processFailure(result.failureValue)))
        }
    }

    // This method basically hops over HasMetaGlobal, because it's not a state
    // that we expect consumers to know about.
    func advance() -> Deferred<Result<Ready>> {
        // Either m/g and c/k are in our local cache, and they're up-to-date with i/c,
        // or we need to fetch them.
        return chainDeferred(advanceToMG(), { $0.advance() })
    }
}

public class HasMetaGlobal: BaseSyncStateWithInfo {
    public override var label: SyncStateLabel { return SyncStateLabel.HasMetaGlobal }

    class func fromState(state: BaseSyncStateWithInfo) -> HasMetaGlobal {
        return HasMetaGlobal(client: state.client, scratchpad: state.scratchpad, token: state.token, info: state.info)
    }

    class func fromState(state: BaseSyncStateWithInfo, scratchpad: Scratchpad) -> HasMetaGlobal {
        return HasMetaGlobal(client: state.client, scratchpad: scratchpad, token: state.token, info: state.info)
    }

    func advance() -> Deferred<Result<Ready>> {
        // Fetch crypto/keys, unless it's present in the cache already.
        // For now, just fetch.
        // TODO: detect when the keys have changed, and scream and run away if so.
        // TODO: upload keys if necessary, then go to Restart.
        let syncKey = Keys(defaultBundle: self.scratchpad.syncKeyBundle)
        let keysFactory: (String) -> KeysPayload? = syncKey.factory("keys", { KeysPayload($0) })
        let client = self.client.collectionClient("crypto", factory: keysFactory)
        return client.get("keys").map { result in
            if let resp = result.successValue?.value {
                let collectionKeys = Keys(payload: resp.payload)
                if (!collectionKeys.valid) {
                    return Result(failure: InvalidKeysError(collectionKeys))
                }
                let newState = Ready(client: self.client, scratchpad: self.scratchpad, token: self.token, info: self.info, keys: collectionKeys)
                return Result(success: newState)
            }
            return Result(failure: result.failureValue!)
        }
    }
}

public class Ready: BaseSyncStateWithInfo {
    public override var label: SyncStateLabel { return SyncStateLabel.Ready }
    let collectionKeys: Keys

    public init(client: Sync15StorageClient, scratchpad: Scratchpad, token: TokenServerToken, info: InfoCollections, keys: Keys) {
        self.collectionKeys = keys
        super.init(client: client, scratchpad: scratchpad, token: token, info: info)
    }
}


/*
 * Because a strongly typed state machine is incompatible with protocols,
 * we use function dispatch to ape a protocol.
 */
func advanceSyncState(s: InitialWithLiveToken) -> Deferred<Result<Ready>> {
    return chainDeferred(s.advance(), { $0.advance() })
}

func advanceSyncState(s: HasMetaGlobal) -> Deferred<Result<Ready>> {
    return s.advance()
}