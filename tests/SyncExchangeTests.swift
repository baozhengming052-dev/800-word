import Foundation

@main struct SyncExchangeTests {
    static func main() throws {
        func rejects(_ title: String, _ action: () throws -> Void) {
            do { try action(); fatalError(title) } catch { }
        }
        var sender = SyncExchange(initiator: true), receiver = SyncExchange(initiator: false)
        let request = try sender.begin()
        try receiver.receive(request)
        let backup = Data("{\"schemaVersion\":3,\"events\":[],\"revisions\":[]}".utf8)
        let snapshot = try receiver.snapshot(backup)
        let decoded = try SyncPacket.decode(snapshot.encode())
        assert(decoded.payload == backup && decoded.id == request.id, "Binary envelope preserves exact bytes and run ID")
        try sender.receive(decoded)
        let proposal = try sender.propose(backup)
        try receiver.receive(proposal)
        rejects("A repeated proposal must not cause duplicate saves") { try receiver.receive(proposal) }
        let digest = String(repeating: "a", count: 64)
        let accepted = try receiver.accept(digest: digest)
        try sender.receive(accepted)
        assert(sender.phase == .committingLocal && receiver.phase == .waitingCompletion, "Remote save is not bilateral completion")
        let completed = try sender.complete(digest: digest)
        try receiver.receive(completed)
        assert(sender.phase == .complete && receiver.phase == .complete, "Both acknowledgements complete the run")
        rejects("A replayed ack cannot restart a completed run") { try sender.receive(accepted) }

        var fresh = SyncExchange(initiator: true)
        let newRun = try fresh.begin()
        rejects("Messages from another connection cannot be consumed") { try fresh.receive(snapshot) }
        rejects("Accept cannot arrive before a proposal") {
            try fresh.receive(SyncPacket(id: newRun.id, kind: .accepted, digest: digest))
        }
        rejects("Truncated packet must be rejected") { _ = try SyncPacket.decode(Data([0, 0, 8, 0, 1])) }
        rejects("Control packets cannot carry a hidden backup") { _ = try SyncPacket(id: newRun.id, kind: .request, payload: backup).encode() }
        rejects("Empty proposals are invalid") { _ = try SyncPacket(id: newRun.id, kind: .proposal).encode() }
        rejects("Malformed digest is invalid") { _ = try SyncPacket(id: newRun.id, kind: .accepted, digest: "not-a-digest").encode() }
        var matchingLibrary = SyncPacket(id: newRun.id, kind: .request)
        matchingLibrary.libraryFingerprint = String(repeating: "b", count: 64)
        let matchingDecoded = try SyncPacket.decode(matchingLibrary.encode())
        try matchingDecoded.validateLibrary(String(repeating: "b", count: 64))
        func envelope(_ version: Int, _ schema: Int?) throws -> Data {
            var header: [String: Any] = ["version": version, "id": newRun.id.uuidString, "kind": "request"]
            if let schema = schema { header["contentSchemaVersion"] = schema }
            let bytes = try JSONSerialization.data(withJSONObject: header)
            let n = UInt32(bytes.count)
            var packet = Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
            packet.append(bytes); return packet
        }
        for (version, schema) in [(1, nil as Int?), (2, nil), (2, 2)] {
            do {
                _ = try SyncPacket.decode(envelope(version, schema))
                fatalError("Old or missing content capability must fail before exchange")
            } catch {
                assert(error.localizedDescription.contains("更新"), "Incompatible peers receive actionable upgrade guidance")
            }
        }
        let personal = PersonalRevision(entryID: UUID(), word: PersonalWordContent(word: "自建", meaning: "释义"))
        let personalBytes = try JSONEncoder().encode(StudySnapshot(revisions: [personal]))
        let differentPersonal = SyncPacket(id: newRun.id, kind: .snapshot, payload: personalBytes, libraryFingerprint: String(repeating: "b", count: 64))
        let personalDecoded = try SyncPacket.decode(differentPersonal.encode())
        try personalDecoded.validateLibrary(String(repeating: "b", count: 64))
        assert(personalDecoded.payload == personalBytes, "Personal content differences do not change bundled compatibility")
        rejects("Different library contents must not produce diverging records") {
            try matchingDecoded.validateLibrary(String(repeating: "c", count: 64))
        }
        rejects("Missing library identity cannot bypass compatibility checks") { try request.validateLibrary(String(repeating: "b", count: 64)) }
        let cancel = fresh.cancel(reason: "已取消")!
        assert(cancel.id == newRun.id && fresh.phase == .cancelled, "Cancellation retains run ID and terminal state")
        print("PASS: sync wire framing, ordered two-party confirmation, replay and malformed packet rejection")
    }
}
