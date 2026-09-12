import Foundation
import CryptoKit
import Security

enum NearbySecurityError: LocalizedError {
    case invalidState, invalidMessage, identityMismatch, authenticationFailed, oversized, keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidState: return "同步连接状态异常，请重新连接。"
        case .invalidMessage: return "收到无效或重复的同步消息，连接已停止。"
        case .identityMismatch: return "设备身份验证失败，请重新配对。"
        case .authenticationFailed: return "同步消息未通过安全校验，连接已停止。"
        case .oversized: return "同步数据超过允许大小。"
        case .keychain: return "无法安全读取或保存设备身份，请解锁设备后重试。"
        }
    }
}

/// A session is bound to two signed, committed ephemeral hellos. No shared secrets
/// are advertised. Commit/reveal prevents an active intermediary from choosing
/// its ephemeral key after learning the honest peer's complete handshake.
final class NearbySecureChannel {
    static let maximumPlaintext = 65_536
    static let maximumPacket = maximumPlaintext + 1 + 8 + 12 + 16
    private static let domain = Data("Words800 nearby v1 signed hello".utf8)
    let hello: Data
    let commitment: Data
    private(set) var remoteIdentity: Data?
    private(set) var verificationCode: String?
    var isReady: Bool { localConfirmed && remoteConfirmed }

    private let identity: Curve25519.Signing.PrivateKey
    private let ephemeral: Curve25519.KeyAgreement.PrivateKey
    private let isInitiator: Bool
    private let expectedRemoteIdentity: Data?
    private var remoteCommitment: Data?
    private var sendKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var transcriptHash = Data()
    private var sendSequence: UInt64 = 0
    private var receiveSequence: UInt64 = 0
    private var localConfirmed = false
    private var remoteConfirmed = false

    init(identity: Curve25519.Signing.PrivateKey, isInitiator: Bool, expectedRemoteIdentity: Data? = nil) throws {
        self.identity = identity
        self.isInitiator = isInitiator
        self.expectedRemoteIdentity = expectedRemoteIdentity
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        self.ephemeral = ephemeral
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw NearbySecurityError.keychain(status) }
        var body = Data([isInitiator ? 1 : 0])
        body.append(identity.publicKey.rawRepresentation)
        body.append(ephemeral.publicKey.rawRepresentation)
        body.append(nonce)
        let signature = try identity.signature(for: Self.domain + body)
        hello = body + signature
        commitment = Data(SHA256.hash(data: hello))
    }

    func receiveCommitment(_ value: Data) throws {
        guard remoteCommitment == nil, value.count == 32 else { throw NearbySecurityError.invalidMessage }
        remoteCommitment = value
    }

    func receiveHello(_ value: Data) throws {
        guard let remoteCommitment, remoteIdentity == nil else { throw NearbySecurityError.invalidState }
        guard value.count == 161, Data(SHA256.hash(data: value)) == remoteCommitment,
              value.first == (isInitiator ? 0 : 1) else { throw NearbySecurityError.authenticationFailed }
        let publicIdentity = Data(value[1..<33])
        guard publicIdentity != identity.publicKey.rawRepresentation,
              expectedRemoteIdentity == nil || expectedRemoteIdentity == publicIdentity else {
            throw NearbySecurityError.identityMismatch
        }
        let signer = try Curve25519.Signing.PublicKey(rawRepresentation: publicIdentity)
        guard signer.isValidSignature(Data(value[97..<161]), for: Self.domain + value.prefix(97)) else {
            throw NearbySecurityError.authenticationFailed
        }
        let peerEphemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(value[33..<65]))
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: peerEphemeral)
        let transcript = Data("Words800 nearby v1 transcript".utf8) + (isInitiator ? hello + value : value + hello)
        let hash = Data(SHA256.hash(data: transcript))
        func derive(_ purpose: String) -> SymmetricKey {
            shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: hash,
                sharedInfo: Data(("Words800 nearby v1 " + purpose).utf8), outputByteCount: 32)
        }
        sendKey = derive(isInitiator ? "initiator to responder" : "responder to initiator")
        receiveKey = derive(isInitiator ? "responder to initiator" : "initiator to responder")
        let sasKey = derive("comparison code")
        let sasNumber = sasKey.withUnsafeBytes { bytes -> UInt32 in
            bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        verificationCode = String(format: "%06u", sasNumber % 1_000_000)
        remoteIdentity = publicIdentity
        transcriptHash = hash
    }

    func confirmLocally() throws -> Data {
        guard !localConfirmed, remoteIdentity != nil else { throw NearbySecurityError.invalidState }
        let packet = try encrypt(Data([0xC1]))
        localConfirmed = true
        return packet
    }

    func receiveConfirmation(_ packet: Data) throws {
        guard !remoteConfirmed, remoteIdentity != nil else { throw NearbySecurityError.invalidState }
        let value = try decrypt(packet)
        guard value == Data([0xC1]) else { throw NearbySecurityError.invalidMessage }
        remoteConfirmed = true
    }

    func seal(_ plaintext: Data) throws -> Data {
        guard isReady else { throw NearbySecurityError.invalidState }
        guard plaintext.count <= Self.maximumPlaintext else { throw NearbySecurityError.oversized }
        return try encrypt(Data([0xDA]) + plaintext)
    }

    func open(_ packet: Data) throws -> Data {
        guard isReady else { throw NearbySecurityError.invalidState }
        let value = try decrypt(packet)
        guard value.first == 0xDA else { throw NearbySecurityError.invalidMessage }
        return Data(value.dropFirst())
    }

    private func encrypt(_ value: Data) throws -> Data {
        guard let sendKey, sendSequence < UInt64.max else { throw NearbySecurityError.invalidState }
        let sequence = Self.encode(sendSequence)
        let box = try ChaChaPoly.seal(value, using: sendKey, authenticating: transcriptHash + sequence)
        sendSequence += 1
        return sequence + box.combined
    }

    private func decrypt(_ packet: Data) throws -> Data {
        guard let receiveKey else { throw NearbySecurityError.invalidState }
        guard packet.count >= 37, packet.count <= Self.maximumPacket,
              Self.decode(Data(packet.prefix(8))) == receiveSequence, receiveSequence < UInt64.max else {
            throw NearbySecurityError.invalidMessage
        }
        do {
            let box = try ChaChaPoly.SealedBox(combined: packet.dropFirst(8))
            let value = try ChaChaPoly.open(box, using: receiveKey,
                                           authenticating: transcriptHash + packet.prefix(8))
            receiveSequence += 1
            return value
        } catch { throw NearbySecurityError.authenticationFailed }
    }

    static func encode(_ value: UInt64) -> Data {
        Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    static func decode(_ value: Data) -> UInt64? {
        guard value.count == 8 else { return nil }
        return value.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

/// Signing identity and exact peer public keys are device-only Keychain items.
/// Keychain failures deliberately do not create an in-memory replacement identity.
enum NearbyIdentityStore {
    private static let service = "Words800.nearby.identity.v1"
    private static let identityAccount = "signing-key"
    private static let peersAccount = "trusted-signing-public-keys"

    static func identity() throws -> Curve25519.Signing.PrivateKey {
        if let stored = try read(identityAccount) {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: stored)
        }
        let key = Curve25519.Signing.PrivateKey()
        try write(key.rawRepresentation, account: identityAccount)
        return key
    }

    static func trustedKeys() throws -> Set<Data> {
        guard let value = try read(peersAccount) else { return [] }
        let keys = try JSONDecoder().decode([Data].self, from: value)
        guard keys.count <= 256, keys.allSatisfy({ $0.count == 32 }) else {
            throw NearbySecurityError.identityMismatch
        }
        return Set(keys)
    }

    static func trust(_ key: Data) throws {
        guard key.count == 32 else { throw NearbySecurityError.identityMismatch }
        var keys = try trustedKeys()
        guard keys.contains(key) || keys.count < 256 else { throw NearbySecurityError.oversized }
        keys.insert(key)
        try write(JSONEncoder().encode(Array(keys)), account: peersAccount)
    }

    static func forgetTrustedDevices() throws {
        let status = SecItemDelete(query(peersAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NearbySecurityError.keychain(status)
        }
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private static func read(_ account: String) throws -> Data? {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NearbySecurityError.keychain(status)
        }
        return data
    }

    private static func write(_ data: Data, account: String) throws {
        let attributes = query(account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addition = attributes
            addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw NearbySecurityError.keychain(addStatus) }
        } else if status != errSecSuccess { throw NearbySecurityError.keychain(status) }
    }
}
