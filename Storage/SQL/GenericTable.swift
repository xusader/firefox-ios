/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCGLogger

private let log = XCGLogger.defaultInstance()

class GenericTable<T>: BaseTable {
    typealias Type = T

    // Implementors need override these methods
    var name: String { return "" }
    var version: Int { return 0 }
    var rows: String { return "" }
    var factory: ((row: SDRow) -> Type)? {
        return nil
    }

    // These methods take an inout object to avoid some runtime crashes that seem to be due
    // to using generics. Yay Swift!
    func getInsertAndArgs(inout item: Type) -> (String, [AnyObject?])? {
        return nil
    }

    func getUpdateAndArgs(inout item: Type) -> (String, [AnyObject?])? {
        return nil
    }

    func getDeleteAndArgs(inout item: Type?) -> (String, [AnyObject?])? {
        return nil
    }

    func getQueryAndArgs(options: QueryOptions?) -> (String, [AnyObject?])? {
        return nil
    }

    func create(db: SQLiteDBConnection, version: Int) -> Bool {
        if let err = db.executeChange("CREATE TABLE IF NOT EXISTS \(name) (\(rows))") {
            log.error("Error creating \(self.name) - \(err)")
            return false
        }
        return true
    }

    func updateTable(db: SQLiteDBConnection, from: Int, to: Int) -> Bool {
        log.debug("Update table \(self.name) from \(from) to \(to)")
        return false
    }

    func exists(db: SQLiteDBConnection) -> Bool {
        let res = db.executeQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name=?", factory: StringFactory, withArgs: [name])
        return res.count > 0
    }

    func drop(db: SQLiteDBConnection) -> Bool {
        let sqlStr = "DROP TABLE IF EXISTS \(name)"
        let args =  [AnyObject?]()
        let err = db.executeChange(sqlStr, withArgs: args)
        if err != nil {
            log.error("Error dropping \(self.name): \(err)")
        }
        return err == nil
    }

    func insert(db: SQLiteDBConnection, item: Type?, inout err: NSError?) -> Int {
        if var site = item {
            if let (query, args) = getInsertAndArgs(&site) {
                if let error = db.executeChange(query, withArgs: args) {
                    err = error
                    return -1
                }

                return db.lastInsertedRowID
            }
        }

        err = NSError(domain: "mozilla.org", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Tried to save something that isn't a site"
        ])
        return -1
    }

    func update(db: SQLiteDBConnection, item: Type?, inout err: NSError?) -> Int {
        if var item = item {
            if let (query, args) = getUpdateAndArgs(&item) {
                if let error = db.executeChange(query, withArgs: args) {
                    log.error(error.description)
                    err = error
                    return 0
                }

                return db.numberOfRowsModified
            }
        }

        err = NSError(domain: "mozilla.org", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Tried to save something that isn't a site"
            ])
        return 0
    }

    func delete(db: SQLiteDBConnection, item: Type?, inout err: NSError?) -> Int {
        var numDeleted: Int = 0

        if var item: Type? = item {
            if let (query, args) = getDeleteAndArgs(&item) {
                if let error = db.executeChange(query, withArgs: args) {
                    println(error.description)
                    err = error
                    return 0
                }

                return db.numberOfRowsModified
            }
        }
        return 0
    }

    func query(db: SQLiteDBConnection, options: QueryOptions?) -> Cursor<T> {
        if var (query, args) = getQueryAndArgs(options) {
            if let factory = self.factory {
                let c =  db.executeQuery(query, factory: factory, withArgs: args)
                return c
            }
        }
        return Cursor(status: CursorStatus.Failure, msg: "Invalid query: \(options?.filter)")
    }
}
