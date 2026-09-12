import Foundation

@main struct SyncExchangeTests {
    static func main() throws {
        func rejects(_ title: String, _ action: () throws -> Void) {
            do { try action(); fatalError(title) } catch { }
        }
        var sender = SyncExchange(initiator: true), receiver = SyncExchange(initiator: false)
        let request = try sender.begin()
        try receiver.receive(request)
        let backup = Data("{\"schemaVersion\":2,\"events\":[]}".utf8)
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
        rejects("Different library contents must not produce diverging records") {
            try matchingDecoded.validateLibrary(String(repeating: "c", count: 64))
        }
        rejects("Missing library identity cannot bypass compatibility checks") { try request.validateLibrary(String(repeating: "b", count: 64)) }
        let cancel = fresh.cancel(reason: "已取消")!
        assert(cancel.id == newRun.id && fresh.phase == .cancelled, "Cancellation retains run ID and terminal state")
        print("PASS: sync wire framing, ordered two-party confirmation, replay and malformed packet rejection")
    }
}
