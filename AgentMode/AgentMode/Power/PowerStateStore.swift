import Foundation

/// Crash-safe record of any persistent power change we made (section 8).
///
/// The IOPMAssertion path needs no recovery — the kernel drops assertions when
/// the process dies. Only `pmset disablesleep` survives our death, so before
/// setting it we write a restore file; after restoring we delete it. If the
/// app launches and the file exists, a previous run died without restoring
/// and we must put the user's setting back.
struct PowerRestoreRecord: Codable {
    /// The user's SleepDisabled value before we touched it (almost always false).
    let previousSleepDisabled: Bool
    let changedAt: Date
}

enum PowerStateStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentMode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("power-restore.json")
    }

    static func savePendingRestore(_ record: PowerRestoreRecord) {
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func pendingRestore() -> PowerRestoreRecord? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PowerRestoreRecord.self, from: data)
    }

    static func clearPendingRestore() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
