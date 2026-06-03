import Foundation
import SQLite3

/// SQLite requires the bound bytes to either live forever (STATIC) or be copied
/// immediately (TRANSIENT). Swift `String`/`NSString` buffers are temporary, so we
/// must always bind text as TRANSIENT to avoid writing freed/garbage memory.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// `nonisolated` so it can run off the main actor (the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise pin this
/// type — and its blocking SQLite calls — to the main thread). All access is
/// internally serialized on a private dispatch queue, so it is safe to use from
/// any thread as long as a single instance isn't shared across isolation domains.
nonisolated final class BufferDatabase {

    static let appGroupID = "group.com.BlackBeansInc.Tally"

    // MARK: - Private State

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.BlackBeansInc.Tally.BufferDatabase", qos: .userInitiated)

    /// Whether the database opened successfully. When false, all operations are
    /// safe no-ops — the buffer simply collects nothing rather than crashing.
    private(set) var isOpen = false

    // MARK: - Init

    init() {
        let dbPath = Self.databaseURL().path

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            // Never crash the host app/keyboard over a storage hiccup — degrade gracefully.
            let errorMessage = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            print("BufferDatabase: Unable to open database at \(dbPath): \(errorMessage)")
            if let db { sqlite3_close(db) }
            db = nil
            return
        }

        // WAL lets the app process read/upload while the keyboard process writes,
        // and a busy timeout makes concurrent writers wait instead of silently failing
        // with SQLITE_BUSY (both targets open the same file in the App Group container).
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_busy_timeout(db, 3000)

        isOpen = true
        createTableIfNeeded()
    }

    /// Resolves the SQLite file location. Prefers the shared App Group container
    /// (so the app and keyboard see the same buffer); if that is unavailable
    /// (e.g. entitlements not provisioned), falls back to a local directory so the
    /// app still launches instead of crashing.
    private static func databaseURL() -> URL {
        let fm = FileManager.default
        let baseURL: URL
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            baseURL = container
        } else {
            print("BufferDatabase: App Group container unavailable — falling back to local storage.")
            baseURL = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                       ?? fm.temporaryDirectory)
            try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
        return baseURL.appendingPathComponent("buffer.sqlite")
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Table Creation

    private func createTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS batches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            app_context TEXT,
            wpm REAL,
            backspace_rate REAL,
            ts TEXT NOT NULL,
            locale TEXT NOT NULL,
            uploaded INTEGER DEFAULT 0
        )
        """
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("BufferDatabase: Failed to prepare CREATE TABLE: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                print("BufferDatabase: Failed to execute CREATE TABLE: \(String(cString: sqlite3_errmsg(db)))")
                sqlite3_finalize(stmt)
                return
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Insert

    func insertBatch(text: String, appContext: String?, wpm: Double?, backspaceRate: Double?, locale: String) {
        let iso8601 = ISO8601DateFormatter().string(from: Date())

        queue.sync {
            let sql = """
            INSERT INTO batches (text, app_context, wpm, backspace_rate, ts, locale)
            VALUES (?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("BufferDatabase: Failed to prepare INSERT: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)

            if let appContext = appContext {
                sqlite3_bind_text(stmt, 2, appContext, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 2)
            }

            if let wpm = wpm {
                sqlite3_bind_double(stmt, 3, wpm)
            } else {
                sqlite3_bind_null(stmt, 3)
            }

            if let backspaceRate = backspaceRate {
                sqlite3_bind_double(stmt, 4, backspaceRate)
            } else {
                sqlite3_bind_null(stmt, 4)
            }

            sqlite3_bind_text(stmt, 5, iso8601, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, locale, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("BufferDatabase: INSERT failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    // MARK: - Fetch

    func fetchUnuploaded(limit: Int = 100) -> [Batch] {
        queue.sync {
            let sql = "SELECT id, text, app_context, wpm, backspace_rate, ts, locale FROM batches WHERE uploaded = 0 ORDER BY id ASC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("BufferDatabase: Failed to prepare SELECT: \(String(cString: sqlite3_errmsg(db)))")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            var results: [Batch] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let text = String(cString: sqlite3_column_text(stmt, 1))

                var appContext: String?
                if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                    appContext = String(cString: sqlite3_column_text(stmt, 2))
                }

                var wpm: Double?
                if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                    wpm = sqlite3_column_double(stmt, 3)
                }

                var backspaceRate: Double?
                if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                    backspaceRate = sqlite3_column_double(stmt, 4)
                }

                let timestamp = String(cString: sqlite3_column_text(stmt, 5))
                let locale = String(cString: sqlite3_column_text(stmt, 6))

                let batch = Batch(
                    id: id,
                    text: text,
                    appContext: appContext,
                    wpm: wpm,
                    backspaceRate: backspaceRate,
                    timestamp: timestamp,
                    locale: locale
                )
                results.append(batch)
            }
            return results
        }
    }

    // MARK: - Mark Uploaded

    func markUploaded(ids: [Int64]) {
        guard !ids.isEmpty else { return }

        queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "UPDATE batches SET uploaded = 1 WHERE id IN (\(placeholders))"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("BufferDatabase: Failed to prepare UPDATE: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }

            for (index, id) in ids.enumerated() {
                sqlite3_bind_int64(stmt, Int32(index + 1), id)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("BufferDatabase: UPDATE failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    // MARK: - Delete

    func deleteUploaded() {
        queue.sync {
            executeSimple("DELETE FROM batches WHERE uploaded = 1")
        }
    }

    func deleteAll() {
        queue.sync {
            executeSimple("DELETE FROM batches")
        }
    }

    // MARK: - Count

    func countUnuploaded() -> Int {
        queue.sync {
            let sql = "SELECT COUNT(*) FROM batches WHERE uploaded = 0"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("BufferDatabase: Failed to prepare COUNT: \(String(cString: sqlite3_errmsg(db)))")
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    // MARK: - Helpers

    private func executeSimple(_ sql: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("BufferDatabase: Failed to prepare \(sql): \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("BufferDatabase: Failed to execute \(sql): \(String(cString: sqlite3_errmsg(db)))")
        }
    }
}
