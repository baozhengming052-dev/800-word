import Foundation

struct SyncPacket {
    enum Kind: String, Codable { case request, snapshot, proposal, accepted, completed, cancel }
    let id: UUID
    let kind: Kind
    var payload = Data()
    var digest: String? = nil
    var reason: String? = nil
    var libraryFingerprint: String? = nil
    private struct Header: Codable { let version: Int; let contentSchemaVersion: Int?; let id: UUID; let kind: Kind; let digest: String?; let reason: String?; let libraryFingerprint: String? }

    // Raw payload follows a bounded JSON header; no base64 expansion of a large backup.
    // 内容能力 4 = v3 快照 + 个人补充近义词事件；旧版会明确要求升级，而不是收到无法解析的记录。
    func encode() throws -> Data {
        try validate()
        let header = try JSONEncoder().encode(Header(version: 2, contentSchemaVersion: 4, id: id, kind: kind, digest: digest, reason: reason, libraryFingerprint: libraryFingerprint))
        guard header.count <= 2048 else { throw SyncError.invalid("同步消息头过长。") }
        let length = UInt32(header.count)
        var bytes = Data([UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
        bytes.append(header); bytes.append(payload)
        return bytes
    }

    static func decode(_ data: Data) throws -> SyncPacket {
        guard (5...20_002_052).contains(data.count) else { throw SyncError.invalid("同步消息大小无效。") }
        let length = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (1...2048).contains(length), data.count >= 4 + length else { throw SyncError.invalid("同步消息不完整。") }
        let header = try JSONDecoder().decode(Header.self, from: data.subdata(in: 4..<(4 + length)))
        guard header.version == 2, header.contentSchemaVersion == 4 else { throw SyncError.invalid("同步协议或个人内容格式不一致，请更新两台设备的 App。") }
        let packet = SyncPacket(id: header.id, kind: header.kind, payload: data.subdata(in: (4 + length)..<data.count), digest: header.digest, reason: header.reason, libraryFingerprint: header.libraryFingerprint)
        try packet.validate()
        return packet
    }

    func validateLibrary(_ expected: String) throws {
        guard expected.count == 64, libraryFingerprint == expected else {
            throw SyncError.invalid("两台设备的词库/题库不是同一版本，请先安装同一份新版 IPA 再同步。")
        }
    }

    private func validate() throws {
        if kind == .snapshot || kind == .proposal {
            guard !payload.isEmpty, payload.count <= 20_000_000 else { throw SyncError.invalid("学习备份为空或超过 20 MB。") }
        } else if !payload.isEmpty { throw SyncError.invalid("控制消息不应包含学习数据。") }
        if kind == .accepted || kind == .completed {
            guard let digest = digest, digest.count == 64, digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw SyncError.invalid("同步校验值无效。")
            }
        } else if digest != nil { throw SyncError.invalid("不符合当前步骤的校验消息。") }
        if let reason = reason {
            guard kind == .cancel, reason.utf8.count <= 512 else { throw SyncError.invalid("无效的取消消息。") }
        }
    }
}

// Protocol state is separate from UI and disk writes so duplicate/out-of-order packets cannot save twice.
struct SyncExchange {
    enum Phase { case waitingRequest, idle, waitingSnapshot, preparingSnapshot, waitingProposal, choosingMerge, waitingAcceptance, confirmingProposal, committingLocal, waitingCompletion, complete, cancelled }
    let initiator: Bool
    private(set) var phase: Phase
    private(set) var id: UUID?
    init(initiator: Bool) { self.initiator = initiator; phase = initiator ? .idle : .waitingRequest }

    mutating func begin() throws -> SyncPacket {
        guard initiator, phase == .idle else { throw wrongStep() }
        let run = UUID(); id = run; phase = .waitingSnapshot
        return SyncPacket(id: run, kind: .request)
    }
    mutating func receive(_ packet: SyncPacket) throws {
        guard phase != .complete, phase != .cancelled else { throw wrongStep() }
        if !initiator, phase == .waitingRequest, packet.kind == .request {
            id = packet.id; phase = .preparingSnapshot; return
        }
        guard let id = id, packet.id == id else { throw SyncError.invalid("收到其他同步任务的消息，已停止本次同步。") }
        if packet.kind == .cancel { phase = .cancelled; return }
        switch (phase, packet.kind) {
        case (.waitingSnapshot, .snapshot): phase = .choosingMerge
        case (.waitingProposal, .proposal): phase = .confirmingProposal
        case (.waitingAcceptance, .accepted): phase = .committingLocal
        case (.waitingCompletion, .completed): phase = .complete
        default: throw wrongStep()
        }
    }
    mutating func snapshot(_ data: Data) throws -> SyncPacket {
        guard phase == .preparingSnapshot, let id = id else { throw wrongStep() }
        phase = .waitingProposal; return SyncPacket(id: id, kind: .snapshot, payload: data)
    }
    mutating func propose(_ data: Data) throws -> SyncPacket {
        guard phase == .choosingMerge, let id = id else { throw wrongStep() }
        phase = .waitingAcceptance; return SyncPacket(id: id, kind: .proposal, payload: data)
    }
    mutating func accept(digest: String) throws -> SyncPacket {
        guard phase == .confirmingProposal, let id = id else { throw wrongStep() }
        phase = .waitingCompletion; return SyncPacket(id: id, kind: .accepted, digest: digest)
    }
    mutating func complete(digest: String) throws -> SyncPacket {
        guard phase == .committingLocal, let id = id else { throw wrongStep() }
        phase = .complete; return SyncPacket(id: id, kind: .completed, digest: digest)
    }
    mutating func cancel(reason: String) -> SyncPacket? {
        guard phase != .complete, phase != .cancelled else { return nil }
        phase = .cancelled
        guard let id = id else { return nil }
        return SyncPacket(id: id, kind: .cancel, reason: reason)
    }
    private func wrongStep() -> SyncError { .invalid("同步步骤不一致，未继续保存。请重新连接后重试。") }
}
