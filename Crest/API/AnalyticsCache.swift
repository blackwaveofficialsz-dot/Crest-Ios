import CryptoKit
import Foundation
import Security
import SQLite3

struct AnalyticsCacheIdentity: Hashable, Sendable {
    let userID: String
    let workspaceID: String

    init?(userID: String, workspaceID: String) {
        guard !userID.isEmpty, !workspaceID.isEmpty else { return nil }
        self.userID = userID
        self.workspaceID = workspaceID
    }
}

struct AnalyticsCachedSnapshot<Value> {
    let value: Value
    let cachedAt: Date
}

struct AnalyticsCachedDay<Payload> {
    let date: String
    let version: String
    let payload: Payload
}

struct AnalyticsChangedDay<Payload> {
    let date: String
    let version: String
    let payload: Payload?
}

struct AnalyticsDailyMetadata: Codable, Sendable {
    let schemaVersion: String
    let accessScopeHash: String
    let namespace: String
    let paramsHash: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case accessScopeHash = "access_scope_hash"
        case namespace
        case paramsHash = "params_hash"
    }
}

private enum AnalyticsCacheError: Error {
    case database(String)
    case encryption
    case oversizedPayload
}

actor AnalyticsCache {
    static let shared = AnalyticsCache()

    private let snapshotTTL: TimeInterval = 30 * 24 * 60 * 60
    private let dailyTTL: TimeInterval = 365 * 24 * 60 * 60
    private let maximumPayloadBytes = 1_000_000
    private let keychainService = "com.blackwave.crest.analytics-cache"
    private let keychainAccount = "encryption-key-v1"
    private var databaseHandle: OpaquePointer?
    private var cachedKey: SymmetricKey?

    deinit {
        if let databaseHandle { sqlite3_close(databaseHandle) }
    }

    func snapshot<Value: Codable>(
        identity: AnalyticsCacheIdentity,
        scope: String,
        as type: Value.Type = Value.self
    ) throws -> AnalyticsCachedSnapshot<Value>? {
        let db = try database()
        try purgeExpired(db)
        let keys = try cacheKeys(identity: identity, scope: scope)
        let statement = try prepare(
            "SELECT payload, cached_at FROM analytics_snapshots "
                + "WHERE identity_hash = ? AND scope_hash = ? LIMIT 1",
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let value = try JSONDecoder().decode(Value.self, from: decrypt(columnData(statement, at: 0)))
        return AnalyticsCachedSnapshot(
            value: value,
            cachedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        )
    }

    func saveSnapshot<Value: Codable>(
        _ value: Value,
        identity: AnalyticsCacheIdentity,
        scope: String
    ) throws {
        let plain = try JSONEncoder().encode(value)
        guard plain.count <= maximumPayloadBytes else { throw AnalyticsCacheError.oversizedPayload }
        let db = try database()
        let keys = try cacheKeys(identity: identity, scope: scope)
        let encrypted = try encrypt(plain)
        let now = Date().timeIntervalSince1970
        let statement = try prepare(
            """
            INSERT INTO analytics_snapshots
                (identity_hash, scope_hash, payload, cached_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(identity_hash, scope_hash) DO UPDATE SET
                payload = excluded.payload,
                cached_at = excluded.cached_at,
                expires_at = excluded.expires_at
            """,
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        bind(encrypted, at: 3, to: statement)
        sqlite3_bind_double(statement, 4, now)
        sqlite3_bind_double(statement, 5, now + snapshotTTL)
        try stepDone(statement, in: db)
        try execute(
            "DELETE FROM analytics_snapshots WHERE rowid NOT IN "
                + "(SELECT rowid FROM analytics_snapshots ORDER BY cached_at DESC LIMIT 300)",
            in: db
        )
    }

    func dailyEntries<Payload: Codable>(
        identity: AnalyticsCacheIdentity,
        scope: String,
        dateFrom: String,
        dateTo: String,
        as type: Payload.Type = Payload.self
    ) throws -> [String: AnalyticsCachedDay<Payload>] {
        let db = try database()
        try purgeExpired(db)
        let keys = try cacheKeys(identity: identity, scope: scope)
        let statement = try prepare(
            """
            SELECT business_date, version, payload FROM analytics_daily_cache
            WHERE identity_hash = ? AND scope_hash = ?
              AND business_date >= ? AND business_date <= ?
            ORDER BY business_date
            """,
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        bind(dateFrom, at: 3, to: statement)
        bind(dateTo, at: 4, to: statement)
        var result: [String: AnalyticsCachedDay<Payload>] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let date = columnText(statement, at: 0)
            let payload = try JSONDecoder().decode(Payload.self, from: decrypt(columnData(statement, at: 2)))
            result[date] = AnalyticsCachedDay(
                date: date,
                version: columnText(statement, at: 1),
                payload: payload
            )
        }
        return result
    }

    func dailyMetadata(
        identity: AnalyticsCacheIdentity,
        scope: String
    ) throws -> AnalyticsDailyMetadata? {
        let db = try database()
        try purgeExpired(db)
        let keys = try cacheKeys(identity: identity, scope: scope)
        let statement = try prepare(
            "SELECT payload FROM analytics_daily_metadata "
                + "WHERE identity_hash = ? AND scope_hash = ? LIMIT 1",
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try JSONDecoder().decode(
            AnalyticsDailyMetadata.self,
            from: decrypt(columnData(statement, at: 0))
        )
    }

    func saveDailyMetadata(
        _ metadata: AnalyticsDailyMetadata,
        identity: AnalyticsCacheIdentity,
        scope: String
    ) throws {
        let plain = try JSONEncoder().encode(metadata)
        guard plain.count <= maximumPayloadBytes else { throw AnalyticsCacheError.oversizedPayload }
        let db = try database()
        let keys = try cacheKeys(identity: identity, scope: scope)
        let encrypted = try encrypt(plain)
        let now = Date().timeIntervalSince1970
        let statement = try prepare(
            """
            INSERT INTO analytics_daily_metadata
                (identity_hash, scope_hash, payload, cached_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(identity_hash, scope_hash) DO UPDATE SET
                payload = excluded.payload,
                cached_at = excluded.cached_at,
                expires_at = excluded.expires_at
            """,
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        bind(encrypted, at: 3, to: statement)
        sqlite3_bind_double(statement, 4, now)
        sqlite3_bind_double(statement, 5, now + dailyTTL)
        try stepDone(statement, in: db)
    }

    func mergeDaily<Payload: Codable>(
        _ changedDays: [AnalyticsChangedDay<Payload>],
        identity: AnalyticsCacheIdentity,
        scope: String
    ) throws {
        let db = try database()
        let keys = try cacheKeys(identity: identity, scope: scope)
        try execute("BEGIN IMMEDIATE", in: db)
        do {
            for day in changedDays {
                if let payload = day.payload {
                    try upsertDaily(payload, day: day, keys: keys, in: db)
                } else {
                    try deleteDaily(date: day.date, keys: keys, in: db)
                }
            }
            try trimDaily(keys: keys, in: db)
            try execute("COMMIT", in: db)
        } catch {
            try? execute("ROLLBACK", in: db)
            throw error
        }
    }

    func clearDaily(identity: AnalyticsCacheIdentity, scope: String) throws {
        let db = try database()
        let keys = try cacheKeys(identity: identity, scope: scope)
        try execute("BEGIN IMMEDIATE", in: db)
        do {
            try clear(table: "analytics_daily_cache", keys: keys, in: db)
            try clear(table: "analytics_daily_metadata", keys: keys, in: db)
            try execute("COMMIT", in: db)
        } catch {
            try? execute("ROLLBACK", in: db)
            throw error
        }
    }

    func clearSnapshot(identity: AnalyticsCacheIdentity, scope: String) throws {
        try clear(table: "analytics_snapshots", identity: identity, scope: scope)
    }

    func clearAll() throws {
        if let databaseHandle {
            guard sqlite3_close(databaseHandle) == SQLITE_OK else {
                throw AnalyticsCacheError.database("无法关闭经营分析缓存")
            }
            self.databaseHandle = nil
        }
        let url = try databaseURL()
        let manager = FileManager.default
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where manager.fileExists(atPath: path) {
            try manager.removeItem(atPath: path)
        }
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let status = SecItemDelete(lookup as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AnalyticsCacheError.encryption
        }
        cachedKey = nil
    }

    private func upsertDaily<Payload: Codable>(
        _ payload: Payload,
        day: AnalyticsChangedDay<Payload>,
        keys: (identity: String, scope: String),
        in db: OpaquePointer
    ) throws {
        let plain = try JSONEncoder().encode(payload)
        guard plain.count <= maximumPayloadBytes else { throw AnalyticsCacheError.oversizedPayload }
        let encrypted = try encrypt(plain)
        let now = Date().timeIntervalSince1970
        let statement = try prepare(
            """
            INSERT INTO analytics_daily_cache
                (identity_hash, scope_hash, business_date, version, payload, cached_at, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(identity_hash, scope_hash, business_date) DO UPDATE SET
                version = excluded.version,
                payload = excluded.payload,
                cached_at = excluded.cached_at,
                expires_at = excluded.expires_at
            """,
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        bind(day.date, at: 3, to: statement)
        bind(day.version, at: 4, to: statement)
        bind(encrypted, at: 5, to: statement)
        sqlite3_bind_double(statement, 6, now)
        sqlite3_bind_double(statement, 7, now + dailyTTL)
        try stepDone(statement, in: db)
    }

    private func deleteDaily(
        date: String,
        keys: (identity: String, scope: String),
        in db: OpaquePointer
    ) throws {
        let statement = try prepare(
            "DELETE FROM analytics_daily_cache "
                + "WHERE identity_hash = ? AND scope_hash = ? AND business_date = ?",
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        bind(date, at: 3, to: statement)
        try stepDone(statement, in: db)
    }

    private func trimDaily(
        keys: (identity: String, scope: String),
        in db: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            DELETE FROM analytics_daily_cache
            WHERE identity_hash = ? AND scope_hash = ? AND business_date NOT IN (
                SELECT business_date FROM analytics_daily_cache
                WHERE identity_hash = ? AND scope_hash = ?
                ORDER BY business_date DESC LIMIT 365
            )
            """,
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        bind(keys.identity, at: 3, to: statement)
        bind(keys.scope, at: 4, to: statement)
        try stepDone(statement, in: db)
    }

    private func clear(
        table: String,
        identity: AnalyticsCacheIdentity,
        scope: String
    ) throws {
        let db = try database()
        let keys = try cacheKeys(identity: identity, scope: scope)
        try clear(table: table, keys: keys, in: db)
    }

    private func clear(
        table: String,
        keys: (identity: String, scope: String),
        in db: OpaquePointer
    ) throws {
        let statement = try prepare(
            "DELETE FROM \(table) WHERE identity_hash = ? AND scope_hash = ?",
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bind(keys.identity, at: 1, to: statement)
        bind(keys.scope, at: 2, to: statement)
        try stepDone(statement, in: db)
    }

    private func database() throws -> OpaquePointer {
        if let databaseHandle { return databaseHandle }
        let manager = FileManager.default
        let url = try databaseURL()
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw AnalyticsCacheError.database("无法打开经营分析缓存")
        }
        databaseHandle = handle
        try execute("PRAGMA journal_mode=WAL", in: handle)
        try execute("PRAGMA secure_delete=ON", in: handle)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS analytics_daily_cache (
                identity_hash TEXT NOT NULL,
                scope_hash TEXT NOT NULL,
                business_date TEXT NOT NULL,
                version TEXT NOT NULL,
                payload BLOB NOT NULL,
                cached_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                PRIMARY KEY(identity_hash, scope_hash, business_date)
            )
            """,
            in: handle
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS analytics_snapshots (
                identity_hash TEXT NOT NULL,
                scope_hash TEXT NOT NULL,
                payload BLOB NOT NULL,
                cached_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                PRIMARY KEY(identity_hash, scope_hash)
            )
            """,
            in: handle
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS analytics_daily_metadata (
                identity_hash TEXT NOT NULL,
                scope_hash TEXT NOT NULL,
                payload BLOB NOT NULL,
                cached_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                PRIMARY KEY(identity_hash, scope_hash)
            )
            """,
            in: handle
        )
        try? manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        return handle
    }

    private func databaseURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appending(path: "AnalyticsCache", directoryHint: .isDirectory)
        .appending(path: "analytics-cache.sqlite3")
    }

    private func purgeExpired(_ db: OpaquePointer) throws {
        let now = Date().timeIntervalSince1970
        try execute("DELETE FROM analytics_daily_cache WHERE expires_at < \(now)", in: db)
        try execute("DELETE FROM analytics_daily_metadata WHERE expires_at < \(now)", in: db)
        try execute("DELETE FROM analytics_snapshots WHERE expires_at < \(now)", in: db)
    }

    private func cacheKeys(
        identity: AnalyticsCacheIdentity,
        scope: String
    ) throws -> (identity: String, scope: String) {
        let key = try encryptionKey()
        return (
            digest("identity\u{0}\(identity.userID)\u{0}\(identity.workspaceID)", key: key),
            digest("scope\u{0}\(scope)", key: key)
        )
    }

    private func digest(_ value: String, key: SymmetricKey) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func encrypt(_ data: Data) throws -> Data {
        guard let result = try AES.GCM.seal(data, using: encryptionKey()).combined else {
            throw AnalyticsCacheError.encryption
        }
        return result
    }

    private func decrypt(_ data: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: encryptionKey())
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        let data: Data
        if status == errSecSuccess, let saved = item as? Data, saved.count == 32 {
            data = saved
        } else if status == errSecItemNotFound {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AnalyticsCacheError.encryption
            }
            data = Data(bytes)
            let insert: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw AnalyticsCacheError.encryption
            }
        } else {
            throw AnalyticsCacheError.encryption
        }
        let key = SymmetricKey(data: data)
        cachedKey = key
        return key
    }

    private func prepare(_ sql: String, in db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AnalyticsCacheError.database(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func execute(_ sql: String, in db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw AnalyticsCacheError.database(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func stepDone(_ statement: OpaquePointer, in db: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AnalyticsCacheError.database(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
    }

    private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) {
        _ = value.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient)
        }
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func columnData(_ statement: OpaquePointer, at index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
