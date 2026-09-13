import Foundation

enum SnapshotStoreError: LocalizedError {
    case unsupportedSchema(Int)
    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "记录使用不支持的版本 \(version)，请升级 App。原文件已保留，未回退或覆盖记录。"
        }
    }
}

/// Synchronous persistence boundary. Callers publish a proposed snapshot only after save succeeds.
final class SnapshotStore {
    private struct Header: Decodable { let schemaVersion: Int }
    private let directory: URL
    private let validate: (Data) throws -> StudySnapshot
    private let files = FileManager.default
    private(set) var recoveryMessage: String?
    init(directory: URL, validate: @escaping (Data) throws -> StudySnapshot) {
        self.directory = directory; self.validate = validate
    }
    private var primary: URL { directory.appendingPathComponent("study-v3.json") }
    private var previous: URL { directory.appendingPathComponent("study-v3.previous.json") }
    private func exists(_ url: URL) -> Bool { files.fileExists(atPath: url.path) }
    private func read(_ url: URL, version: Int) throws -> (Data, StudySnapshot) {
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= Int64(SnapshotCodec.maximumBytes) else {
            throw PersonalLibraryError.invalid("备份文件过大。")
        }
        let data = try Data(contentsOf: url)
        // Future formats may omit every current payload field. Read only their version contract first.
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard [2, 3].contains(header.schemaVersion) else { throw SnapshotStoreError.unsupportedSchema(header.schemaVersion) }
        // The filename is part of recovery provenance: a v2 file renamed v3 is not a valid v3 backup.
        guard header.schemaVersion == version else { throw PersonalLibraryError.invalid("备份文件版本与存储位置不匹配。") }
        return (data, try validate(data))
    }
    private func recoverableRead(_ url: URL, version: Int) throws -> (Data, StudySnapshot)? {
        do { return try read(url, version: version) }
        catch let error as SnapshotStoreError { throw error }
        catch { return nil }
    }
    func load() throws -> StudySnapshot? {
        recoveryMessage = nil
        if exists(primary) || exists(previous) {
            if let valid = try recoverableRead(primary, version: 3) { return valid.1 }
            if let valid = try recoverableRead(previous, version: 3) {
                recoveryMessage = "主记录损坏或缺失，已载入上一份有效 v3 记录。损坏文件已保留。"
                return valid.1
            }
            throw PersonalLibraryError.invalid("v3 记录及上一份备份均无法读取，已保留原文件，未回退到旧版记录。")
        }
        let legacy = directory.appendingPathComponent("study-v2.json")
        let legacyPrevious = directory.appendingPathComponent("study-v2.previous.json")
        guard exists(legacy) || exists(legacyPrevious) else { return nil }
        let migrated: StudySnapshot
        if let value = try recoverableRead(legacy, version: 2) { migrated = value.1 }
        else if let value = try recoverableRead(legacyPrevious, version: 2) {
            migrated = value.1; recoveryMessage = "旧版主记录损坏，已从旧版备份迁移，原文件已保留。"
        } else { throw PersonalLibraryError.invalid("旧版记录及备份均无法读取，未创建空白记录。") }
        try save(migrated)
        return migrated
    }
    func save(_ snapshot: StudySnapshot) throws {
        guard snapshot.schemaVersion == 3 else { throw PersonalLibraryError.invalid("仅可保存 v3 记录。") }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= SnapshotCodec.maximumBytes else { throw PersonalLibraryError.invalid("备份文件过大。") }
        _ = try validate(data)
        // Preflight both destinations before any directory, backup or evidence-file mutation.
        // This also protects a future backup when the primary itself is valid or damaged.
        let existingPrimary = try recoverableRead(primary, version: 3)
        _ = try recoverableRead(previous, version: 3)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        if exists(primary) {
            if let valid = existingPrimary {
                // Do not advance primary unless the previous valid snapshot is safely on disk.
                try valid.0.write(to: previous, options: .atomic)
            } else {
                // copyItem preserves even oversized/unreadable corrupt bytes without decoding or replacing them.
                let evidence = directory.appendingPathComponent("study-v3.corrupt-\(UUID().uuidString).json")
                try files.copyItem(at: primary, to: evidence)
            }
        }
        try data.write(to: primary, options: .atomic)
    }
}
