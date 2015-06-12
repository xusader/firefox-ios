/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

public struct RemoteClient: Equatable {
    public let guid: GUID?
    public let modified: Timestamp

    public let name: String
    public let type: String?

    let version: String?
    let protocols: [String]?

    let os: String?
    let appPackage: String?
    let application: String?
    let formfactor: String?
    let device: String?

    // Requires a valid ClientPayload (: CleartextPayloadJSON: JSON).
    public init(json: JSON, modified: Timestamp) {
        self.guid = json["id"].asString!
        self.modified = modified
        self.name = json["name"].asString!
        self.type = json["type"].asString

        self.version = json["version"].asString
        self.protocols = jsonsToStrings(json["protocols"].asArray)
        self.os = json["os"].asString
        self.appPackage = json["appPackage"].asString
        self.application = json["application"].asString
        self.formfactor = json["formfactor"].asString
        self.device = json["device"].asString
    }

    public init(guid: GUID?, name: String, modified: Timestamp, type: String?, formfactor: String?, os: String?) {
        self.guid = guid
        self.name = name
        self.modified = modified
        self.type = type
        self.formfactor = formfactor
        self.os = os

        self.device = nil
        self.appPackage = nil
        self.application = nil
        self.version = nil
        self.protocols = nil
    }
}

// TODO: should this really compare tabs?
public func ==(lhs: RemoteClient, rhs: RemoteClient) -> Bool {
    return lhs.guid == rhs.guid &&
        lhs.name == rhs.name &&
        lhs.modified == rhs.modified &&
        lhs.type == rhs.type &&
        lhs.formfactor == rhs.formfactor &&
        lhs.os == rhs.os
}

extension RemoteClient: Printable {
    public var description: String {
        return "<RemoteClient GUID: \(guid), name: \(name), modified: \(modified), type: \(type), formfactor: \(formfactor), OS: \(os)>"
    }
}