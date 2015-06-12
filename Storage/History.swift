/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

public class IgnoredSiteError: ErrorType {
    public var description: String {
        return "Ignored site."
    }
}

/**
 * The base history protocol for front-end code.
 *
 * Note that the implementation of these methods might be complicated if
 * the implementing class also implements SyncableHistory -- for example,
 * `clear` might or might not need to set a bunch of flags to upload deletions.
 */
public protocol BrowserHistory {
    func addLocalVisit(visit: SiteVisit) -> Success
    func clearHistory() -> Success
    func removeHistoryForURL(url: String) -> Success

    func getSitesByFrecencyWithLimit(limit: Int) -> Deferred<Result<Cursor<Site>>>
    func getSitesByFrecencyWithLimit(limit: Int, whereURLContains filter: String) -> Deferred<Result<Cursor<Site>>>
    func getSitesByLastVisit(limit: Int) -> Deferred<Result<Cursor<Site>>>
}

/**
 * The interface that history storage needs to provide in order to be
 * synced by a `HistorySynchronizer`.
 */
public protocol SyncableHistory {
    /**
     * Make sure that the local place with the provided URL has the provided GUID.
     * Succeeds if no place exists with that URL.
     */
    func ensurePlaceWithURL(url: String, hasGUID guid: GUID) -> Success

    /**
     * Delete the place with the provided GUID, and all of its visits. Succeeds if the GUID is unknown.
     */
    func deleteByGUID(guid: GUID, deletedAt: Timestamp) -> Success

    func storeRemoteVisits(visits: [Visit], forGUID guid: GUID) -> Success
    func insertOrUpdatePlace(place: Place, modified: Timestamp) -> Deferred<Result<GUID>>

    func getModifiedHistoryToUpload() -> Deferred<Result<[(Place, [Visit])]>>
    func getDeletedHistoryToUpload() -> Deferred<Result<[GUID]>>

    /**
     * Chains through the provided timestamp.
     */
    func markAsSynchronized([GUID], modified: Timestamp) -> Deferred<Result<Timestamp>>
    func markAsDeleted(guids: [GUID]) -> Success

    /**
     * Clean up any metadata.
     */
    func onRemovedAccount() -> Success
}

// TODO: integrate Site with this.

public class Place {
    public let guid: GUID
    public let url: String
    public let title: String

    public init(guid: GUID, url: String, title: String) {
        self.guid = guid
        self.url = url
        self.title = title
    }
}