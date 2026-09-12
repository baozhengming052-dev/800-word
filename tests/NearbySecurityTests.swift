import Foundation
import CryptoKit

// Compile on macOS with NearbySecurity.swift; these exercise CryptoKit itself.
@main
struct NearbySecurityTests {
    static func expect(_ value: Bool, _ label: String) {
        precondition(value, label)
    }

    static func rejects(_ label: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Accepted invalid input: \(label)") }
        catch { }
    }

    static func pair() throws -> (NearbySecureChannel, NearbySecureChannel) {
        let a = try NearbySecureChannel(identity: .init(), isInitiator: true)
        let b = try NearbySecureChannel(identity: .init(), isInitiator: false)
        try a.receiveCommitment(b.commitment)
        try b.receiveCommitment(a.commitment)
        try a.receiveHello(b.hello)
        try b.receiveHello(a.hello)
        return (a, b)
    }

    static func confirm(_ a: NearbySecureChannel, _ b: NearbySecureChannel) throws {
        let aConfirmation = try a.confirmLocally()
        expect(!a.isReady, "Local confirmation alone cannot authorize payloads")
        rejects("incoming data before bilateral confirmation") { _ = try b.open(aConfirmation) }
        try b.receiveConfirmation(aConfirmation)
        expect(!b.isReady, "Remote confirmation alone cannot authorize payloads")
        rejects("duplicate remote confirmation") { try b.receiveConfirmation(aConfirmation) }
        let bConfirmation = try b.confirmLocally()
        try a.receiveConfirmation(bConfirmation)
        expect(a.isReady && b.isReady, "Both confirmations authorize both directions")
    }

    static func main() throws {
        // Missing role binding, asymmetric transcript derivation, or early sends break this.
        let (a, b) = try pair()
        expect(a.verificationCode == b.verificationCode, "The six-digit codes must match")
        expect(a.verificationCode?.count == 6, "SAS is six digits")
        rejects("unconfirmed outgoing data") { _ = try a.seal(Data("private".utf8)) }
        try confirm(a, b)
        let packet = try a.seal(Data("learning records".utf8))
        expect(try b.open(packet) == Data("learning records".utf8), "Both peers derive matching directional keys")
        rejects("replayed packet") { _ = try b.open(packet) }
        rejects("reflection of sender's ciphertext") { _ = try a.open(packet) }
        let reply = try b.seal(Data("reply".utf8))
        expect(try a.open(reply) == Data("reply".utf8), "Reverse direction uses matching keys")

        // Missing AEAD verification or consuming sequence numbers before authentication breaks this.
        let next = try a.seal(Data("untampered".utf8))
        var damaged = next
        damaged[damaged.count - 1] ^= 1
        rejects("ciphertext tampering") { _ = try b.open(damaged) }
        expect(try b.open(next) == Data("untampered".utf8), "Unauthenticated packet must not advance sequence")

        // Missing commitment validation permits an attacker to adapt its key to the SAS.
        let c = try NearbySecureChannel(identity: .init(), isInitiator: true)
        let d = try NearbySecureChannel(identity: .init(), isInitiator: false)
        rejects("hello before commitment") { try c.receiveHello(d.hello) }
        try c.receiveCommitment(d.commitment)
        var modifiedHello = d.hello
        modifiedHello[40] ^= 1
        rejects("changed committed hello") { try c.receiveHello(modifiedHello) }
        rejects("second commitment") { try c.receiveCommitment(d.commitment) }

        // A committed but incorrectly signed hello must still fail.
        let signed = try NearbySecureChannel(identity: .init(), isInitiator: true)
        var badSignature = d.hello
        badSignature[badSignature.count - 1] ^= 1
        try signed.receiveCommitment(Data(SHA256.hash(data: badSignature)))
        rejects("invalid identity signature") { try signed.receiveHello(badSignature) }

        let wrongIdentity = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        let pinned = try NearbySecureChannel(identity: .init(), isInitiator: true, expectedRemoteIdentity: wrongIdentity)
        try pinned.receiveCommitment(d.commitment)
        rejects("wrong pinned identity") { try pinned.receiveHello(d.hello) }

        let identity = Curve25519.Signing.PrivateKey()
        let selfA = try NearbySecureChannel(identity: identity, isInitiator: true)
        let selfB = try NearbySecureChannel(identity: identity, isInitiator: false)
        try selfA.receiveCommitment(selfB.commitment)
        rejects("self identity") { try selfA.receiveHello(selfB.hello) }

        let wrongRole = try NearbySecureChannel(identity: .init(), isInitiator: true)
        let initiator = try NearbySecureChannel(identity: .init(), isInitiator: true)
        try initiator.receiveCommitment(wrongRole.commitment)
        rejects("reflected initiator role") { try initiator.receiveHello(wrongRole.hello) }

        let (freshA, freshB) = try pair()
        try confirm(freshA, freshB)
        let (otherA, otherB) = try pair()
        try confirm(otherA, otherB)
        let foreignPacket = try otherA.seal(Data("another session, same sequence number".utf8))
        rejects("ciphertext from another session at the expected sequence") { _ = try freshB.open(foreignPacket) }
        let fullSize = Data(repeating: 0x7B, count: 65_536)
        expect(try freshB.open(freshA.seal(fullSize)) == fullSize, "Largest permitted plaintext round trips")
        rejects("oversized plaintext") { _ = try freshA.seal(Data(count: 65_537)) }
        rejects("oversized frame") { _ = try freshB.open(Data(count: 66_000)) }
        rejects("truncated packet") { _ = try freshB.open(Data(count: 16)) }
        let firstInOrder = try freshA.seal(Data([1]))
        let secondInOrder = try freshA.seal(Data([2]))
        rejects("out-of-order packet") { _ = try freshB.open(secondInOrder) }
        expect(try freshB.open(firstInOrder) == Data([1]), "Rejected future packet preserves expected sequence")
        expect(try freshB.open(secondInOrder) == Data([2]), "Future packet succeeds only after its predecessor")
        rejects("duplicate confirmation") { _ = try a.confirmLocally() }
        print("NearbySecurityTests: passed")
    }
}
