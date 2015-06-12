/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import FxA
import Shared
import Account
import XCTest

private class KeyFetchError: ErrorType {
    var description: String {
        return "key fetch error"
    }
}

private class MockBackoffStorage: BackoffStorage {
    var serverBackoffUntilLocalTimestamp: Timestamp? = nil

    func clearServerBackoff() {
        self.serverBackoffUntilLocalTimestamp = nil
    }

    func isInBackoff(now: Timestamp) -> Timestamp? {
        if let ts = self.serverBackoffUntilLocalTimestamp where now < ts {
            return ts
        }
        return nil
    }
}

class LiveStorageClientTests : LiveAccountTest {
    func getKeys(kB: NSData, token: TokenServerToken) -> Deferred<Result<Record<KeysPayload>>> {
        let endpoint = token.api_endpoint
        XCTAssertTrue(endpoint.rangeOfString("services.mozilla.com") != nil, "We got a Sync server.")

        let cryptoURI = NSURL(string: endpoint)
        let authorizer: Authorizer = {
            (r: NSMutableURLRequest) -> NSMutableURLRequest in
            let helper = HawkHelper(id: token.id, key: token.key.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
            r.addValue(helper.getAuthorizationValueFor(r), forHTTPHeaderField: "Authorization")
            return r
        }

        let keyBundle: KeyBundle = KeyBundle.fromKB(kB)
        let encoder = RecordEncoder<KeysPayload>(decode: { KeysPayload($0) }, encode: { $0 })
        let encrypter = Keys(defaultBundle: keyBundle).encrypter("crypto", encoder: encoder)

        let workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let resultQueue = dispatch_get_main_queue()
        let backoff = MockBackoffStorage()

        let storageClient = Sync15StorageClient(serverURI: cryptoURI!, authorizer: authorizer, workQueue: workQueue, resultQueue: resultQueue, backoff: backoff)
        let keysFetcher = storageClient.clientForCollection("crypto", encrypter: encrypter)

        return keysFetcher.get("keys").map({
            // Unwrap the response.
            res in
            if let r = res.successValue {
                return Result(success: r.value)
            }
            return Result(failure: KeyFetchError())
        })
    }

    func getState(user: String, password: String) -> Deferred<Result<FxAState>> {
        let err: NSError = NSError(domain: FxAClientErrorDomain, code: 0, userInfo: nil)
        return Deferred(value: Result<FxAState>(failure: FxAClientError.Local(err)))
    }

    func getTokenAndDefaultKeys() -> Deferred<Result<(TokenServerToken, KeyBundle)>> {
        let authState = self.syncAuthState(NSDate.now())

        let keysPayload: Deferred<Result<Record<KeysPayload>>> = authState.bind {
            tokenResult in
            if let (token, forKey) = tokenResult.successValue {
                return self.getKeys(forKey, token: token)
            }
            XCTAssertEqual(tokenResult.failureValue!.description, "")
            return Deferred(value: Result(failure: KeyFetchError()))
        }

        let result = Deferred<Result<(TokenServerToken, KeyBundle)>>()
        keysPayload.upon {
            res in
            if let rec = res.successValue {
                XCTAssert(rec.id == "keys", "GUID is correct.")
                XCTAssert(rec.modified > 1000, "modified is sane.")
                let payload: KeysPayload = rec.payload as KeysPayload
                println("Body: \(payload.toString(pretty: false))")
                XCTAssert(rec.id == "keys", "GUID inside is correct.")
                let arr = payload["default"].asArray![0].asString
                if let keys = payload.defaultKeys {
                    // Extracting the token like this is not great, but...
                    result.fill(Result(success: (authState.value.successValue!.token, keys)))
                    return
                }
            }

            result.fill(Result(failure: KeyFetchError()))
        }
        return result
    }

    func testLive() {
        let expectation = expectationWithDescription("Waiting on value.")
        let deferred = getTokenAndDefaultKeys()
        deferred.upon {
            res in
            if let (token, keyBundle) = res.successValue {
                println("Yay")
            } else {
                XCTAssertEqual(res.failureValue!.description, "")
            }
            expectation.fulfill()
        }

        // client: mgWl22CIzHiE
        waitForExpectationsWithTimeout(20) { (error) in
            XCTAssertNil(error, "\(error)")
        }
    }

    func testStateMachine() {
        let expectation = expectationWithDescription("Waiting on value.")
        let authState = self.getAuthState(NSDate.now())

        let d = chainDeferred(authState, { SyncStateMachine.toReady($0, prefs: MockProfilePrefs()) })

        d.upon { result in
            if let ready = result.successValue {
                XCTAssertTrue(ready.collectionKeys.defaultBundle.encKey.length == 32)
                XCTAssertTrue(ready.scratchpad.global != nil)
                if let clients = ready.scratchpad.global?.value.engines?["clients"] {
                    XCTAssertTrue(count(clients.syncID) == 12)
                }
            }
            XCTAssertTrue(result.isSuccess)
            expectation.fulfill()
        }

        waitForExpectationsWithTimeout(20) { (error) in
            XCTAssertNil(error, "\(error)")
        }
    }
}