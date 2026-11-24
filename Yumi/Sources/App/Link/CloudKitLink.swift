import CloudKit
import Foundation

/// The link through the person's own iCloud: their private CloudKit database, in a zone of
/// Yumi's. The payloads are encrypted fields (end-to-end with Advanced Data Protection, and never
/// readable by Yumi's author in any case). No server of ours is involved.
///
/// - `mac-snapshot`: the one record the Mac rewrites with what it follows.
/// - `Reply` records: one per answer given on the iPhone; the Mac reads them once, then deletes them.
final class CloudKitLink: YumiLink, @unchecked Sendable {
    static let zoneID = CKRecordZone.ID(zoneName: "Yumi", ownerName: CKCurrentUserDefaultName)
    static let snapshotID = CKRecord.ID(recordName: "mac-snapshot", zoneID: zoneID)
    static let subscriptionID = "yumi-zone"

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }
    private let lock = NSLock()
    private var zoneReady = false
    private var changeToken: CKServerChangeToken?

    init(containerID: String) {
        container = CKContainer(identifier: containerID)
    }

    func isAvailable() async -> Bool {
        guard LinkSetting.isOn() else { return false }
        return (try? await container.accountStatus()) == .available
    }

    func publish(_ snapshot: LinkSnapshot) async throws {
        try await ensureZone()
        let record = CKRecord(recordType: "MacSnapshot", recordID: Self.snapshotID)
        record.encryptedValues["payload"] = try JSONEncoder.link.encode(snapshot)
        // The Mac is the only writer of this record: its latest picture wins
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    func latestSnapshot() async throws -> LinkSnapshot? {
        do {
            let record = try await database.record(for: Self.snapshotID)
            guard let data = record.encryptedValues["payload"] as? Data else { return nil }
            return try JSONDecoder.link.decode(LinkSnapshot.self, from: data)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    func send(_ reply: LinkReply) async throws {
        try await ensureZone()
        let record = CKRecord(recordType: "Reply", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: Self.zoneID))
        record.encryptedValues["payload"] = try JSONEncoder.link.encode(reply)
        _ = try await database.modifyRecords(saving: [record], deleting: [])
    }

    func takeReplies() async throws -> [LinkReply] {
        let token = lock.withLock { changeToken }
        let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                      deletions: [CKDatabase.RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool)
        do {
            changes = try await database.recordZoneChanges(inZoneWith: Self.zoneID, since: token)
        } catch let error as CKError where error.code == .zoneNotFound {
            return []
        } catch let error as CKError where error.code == .changeTokenExpired {
            lock.withLock { changeToken = nil }
            return []
        }
        lock.withLock { changeToken = changes.changeToken }
        var replies: [LinkReply] = []
        var taken: [CKRecord.ID] = []
        for (id, result) in changes.modificationResultsByID {
            guard case .success(let modification) = result, modification.record.recordType == "Reply" else { continue }
            taken.append(id)
            if let data = modification.record.encryptedValues["payload"] as? Data,
               let reply = try? JSONDecoder.link.decode(LinkReply.self, from: data) {
                replies.append(reply)
            }
        }
        // Read once: an answer is never applied twice, even after a restart
        if !taken.isEmpty { _ = try? await database.modifyRecords(saving: [], deleting: taken) }
        return replies
    }

    /// The iPhone: be woken (silently) when the Mac rewrites its picture. Delivery is decided by
    /// iOS: it may be late or skipped when the iPhone saves its battery.
    func subscribe() async throws {
        try await ensureZone()
        let subscription = CKRecordZoneSubscription(zoneID: Self.zoneID, subscriptionID: Self.subscriptionID)
        subscription.recordType = "MacSnapshot"
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    private func ensureZone() async throws {
        if lock.withLock({ zoneReady }) { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
        lock.withLock { zoneReady = true }
    }
}

/// The transport of this build: CloudKit when the build carries an iCloud container
/// (`YumiCloudKitContainer` in its Info.plist, set only where the entitlement is) and the person
/// turned the link on; `OffLink` otherwise. Asked again each time: the setting may change.
enum YumiLinks {
    static var containerID: String? {
        guard let id = (Bundle.main.object(forInfoDictionaryKey: "YumiCloudKitContainer") as? String)?
            .trimmingCharacters(in: .whitespaces), !id.isEmpty, signed(for: id) else { return nil }
        return id
    }

    /// CloudKit stops an app that asks for a container its signature does not carry: the link is
    /// offered only when this build really is signed for it (an unsigned Debug build is not).
    private static func signed(for container: String) -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains(container) == true
        #else
        return true
        #endif
    }

    /// True when this build can use iCloud at all (the setting is shown only then).
    static var isBuiltIn: Bool { containerID != nil }

    private static let shared: CloudKitLink? = containerID.map(CloudKitLink.init(containerID:))

    static func current() -> any YumiLink {
        guard !StudioMode.isOn, LinkSetting.isOn(), let shared else { return OffLink() }
        return shared
    }
}

extension JSONEncoder {
    static var link: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    static var link: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
