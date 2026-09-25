import Foundation
import Combine
import UIKit
import MultipeerConnectivity
import CryptoKit

struct NearbyPeer: Identifiable, Equatable {
    let peerID: MCPeerID
    var id: MCPeerID { peerID }
    var displayName: String {
        String(peerID.displayName.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(60))
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}

/// Foreground-only, explicitly invited, single-peer transport. MCPeerID and
/// device names are discovery handles; authenticated identity comes from Keychain.
@MainActor
final class NearbyTransport: ObservableObject {
    @Published private(set) var peers: [NearbyPeer] = []
    @Published private(set) var invitation: NearbyPeer?
    @Published private(set) var verificationCode: String?
    @Published private(set) var needsVerification = false
    @Published private(set) var isReady = false
    @Published private(set) var isInitiator = false
    @Published private(set) var connectedName = ""
    @Published private(set) var status = "尚未开启附近同步"
    @Published private(set) var errorMessage = ""

    var onReady: (() -> Void)?
    var onData: ((Data) -> Void)?

    static let maximumPayload = SnapshotCodec.maximumBytes + 2_052
    private static let chunkSize = 60 * 1_024
    nonisolated fileprivate static let maximumFrame = NearbySecureChannel.maximumPacket + 1
    private static let serviceType = "words800-sync"

    private enum Phase { case disconnected, commitment, hello, confirmation, ready }
    private var phase: Phase = .disconnected
    fileprivate var session: MCSession?
    fileprivate var advertiser: MCNearbyServiceAdvertiser?
    fileprivate var browser: MCNearbyServiceBrowser?
    private var identity: Curve25519.Signing.PrivateKey?
    private var trustedKeys: Set<Data> = []
    private var channel: NearbySecureChannel?
    private var target: MCPeerID?
    private var invitationHandler: ((Bool, MCSession?) -> Void)?
    private var timeout: Task<Void, Never>?
    private var backgroundObserver: NSObjectProtocol?
    private var running = false
    private lazy var delegate = NearbyTransportDelegate(owner: self)

    private struct Outgoing {
        let data: Data
        var acknowledged = 0
        var expectedAcknowledgement = 0
    }
    private struct Incoming {
        let total: Int
        var data = Data()
    }
    private var outgoing: Outgoing?
    private var incoming: Incoming?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.fail("应用进入后台，附近同步已停止。请回到同步页面重新连接。")
            }
        }
    }

    deinit {
        timeout?.cancel()
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
    }

    func start() {
        guard !running else { return }
        guard UIApplication.shared.applicationState == .active else {
            errorMessage = "请在应用前台开启附近同步。"
            return
        }
        errorMessage = ""
        do {
            identity = try NearbyIdentityStore.identity()
            trustedKeys = try NearbyIdentityStore.trustedKeys()
            var name = String(UIDevice.current.name.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(60))
            // MCPeerID requires a nonempty display name of at most 63 UTF-8 bytes.
            while name.utf8.count > 63 { name.removeLast() }
            let localPeer = MCPeerID(displayName: name.isEmpty ? "花生800词" : name)
            let newSession = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
            newSession.delegate = delegate
            session = newSession
            let newAdvertiser = MCNearbyServiceAdvertiser(peer: localPeer, discoveryInfo: nil, serviceType: Self.serviceType)
            newAdvertiser.delegate = delegate
            advertiser = newAdvertiser
            let newBrowser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
            newBrowser.delegate = delegate
            browser = newBrowser
            running = true
            status = "正在寻找附近设备；请在另一台设备打开此页面"
            newAdvertiser.startAdvertisingPeer()
            newBrowser.startBrowsingForPeers()
        } catch { fail(error.localizedDescription) }
    }

    func stop() {
        running = false
        timeout?.cancel()
        timeout = nil
        invitationHandler?(false, nil)
        invitationHandler = nil
        invitation = nil
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        session?.delegate = nil
        session?.disconnect()
        session = nil
        target = nil
        identity = nil
        trustedKeys = []
        channel = nil
        incoming = nil
        outgoing = nil
        phase = .disconnected
        peers = []
        verificationCode = nil
        needsVerification = false
        isReady = false
        isInitiator = false
        connectedName = ""
        status = "附近同步已停止"
    }

    func connect(_ peer: NearbyPeer) {
        guard running, phase == .disconnected, target == nil, invitation == nil,
              let session, let browser, peer.peerID != session.myPeerID,
              peers.contains(peer) else { return }
        isInitiator = true
        target = peer.peerID
        connectedName = peer.displayName
        status = "等待对方接受连接邀请"
        advertiser?.stopAdvertisingPeer()
        browser.invitePeer(peer.peerID, to: session, withContext: nil, timeout: 60)
        browser.stopBrowsingForPeers()
        peers = []
        armTimeout(seconds: 65, message: "连接邀请超时，请重新连接。")
    }

    func acceptInvitation() {
        guard running, target == nil, let invitation, let handler = invitationHandler, let session else { return }
        target = invitation.peerID
        connectedName = invitation.displayName
        isInitiator = false
        self.invitation = nil
        invitationHandler = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        peers = []
        status = "正在建立安全连接"
        armTimeout(seconds: 65, message: "建立连接超时，请重新连接。")
        handler(true, session)
    }

    func declineInvitation() {
        invitationHandler?(false, nil)
        invitationHandler = nil
        invitation = nil
        timeout?.cancel()
        timeout = nil
        status = "已拒绝邀请，继续寻找附近设备"
    }

    func confirmVerification() {
        guard needsVerification, phase == .confirmation else { return }
        do {
            try sendConfirmation()
            needsVerification = false
            status = "已确认校验码，等待对方确认"
            try becomeReadyIfConfirmed()
        } catch { fail(error.localizedDescription) }
    }

    func rejectVerification() { fail("已取消配对，未发送学习数据。") }

    func forgetTrustedDevices() throws {
        stop()
        try NearbyIdentityStore.forgetTrustedDevices()
        status = "已忘记配对设备；下次连接需要重新核对校验码"
    }

    /// Queues one bounded payload. Reliable stop-and-wait chunks bound memory and
    /// provide flow control; an application acknowledgement remains the caller's job.
    func send(_ data: Data) throws {
        guard isReady, phase == .ready, outgoing == nil else { throw NearbySecurityError.invalidState }
        guard data.count <= Self.maximumPayload else { throw NearbySecurityError.oversized }
        outgoing = Outgoing(data: data)
        do {
            try sendApplication(Data([0]) + NearbySecureChannel.encode(UInt64(data.count)))
            refreshTransferTimeout()
        } catch {
            fail(error.localizedDescription)
            throw error
        }
    }

    fileprivate func discovered(_ peer: MCPeerID, in source: MCNearbyServiceBrowser) {
        guard running, source === browser, target == nil, peer != session?.myPeerID else { return }
        let item = NearbyPeer(peerID: peer)
        if !peers.contains(item), peers.count < 40 { peers.append(item) }
    }

    fileprivate func acceptsCertificate(from peer: MCPeerID, source: MCSession) -> Bool {
        running && UIApplication.shared.applicationState == .active && source === session && peer == target
    }

    fileprivate func lost(_ peer: MCPeerID, in source: MCNearbyServiceBrowser) {
        guard source === browser else { return }
        peers.removeAll { $0.peerID == peer }
    }

    fileprivate func invited(_ peer: MCPeerID, context: Data?, source: MCNearbyServiceAdvertiser,
                             handler: @escaping (Bool, MCSession?) -> Void) {
        guard running, UIApplication.shared.applicationState == .active,
              source === advertiser, target == nil, invitation == nil,
              peer != session?.myPeerID, context == nil || context?.isEmpty == true else {
            handler(false, nil)
            return
        }
        invitation = NearbyPeer(peerID: peer)
        invitationHandler = handler
        status = "收到附近设备的连接邀请"
        // Remembered peers still require this explicit invitation approval.
        armTimeout(seconds: 60, message: "连接邀请已过期，请让对方重新邀请。")
    }

    fileprivate func stateChanged(_ state: MCSessionState, peer: MCPeerID, source: MCSession) {
        guard running, source === session else { return }
        guard UIApplication.shared.applicationState == .active else {
            fail("应用已离开前台，附近同步已停止。")
            return
        }
        guard peer == target else { fail("发现额外连接，附近同步已停止。"); return }
        switch state {
        case .connected:
            guard phase == .disconnected, let identity, source.connectedPeers.count == 1 else {
                fail("连接状态异常，请重新连接。")
                return
            }
            do {
                let secure = try NearbySecureChannel(identity: identity, isInitiator: isInitiator)
                channel = secure
                phase = .commitment
                status = "正在验证设备身份"
                armTimeout(seconds: 120, message: "安全配对超时，请重新连接。")
                try sendFrame(type: 0, data: secure.commitment)
            } catch { fail(error.localizedDescription) }
        case .notConnected: fail("与附近设备的连接已断开；尚未完成的同步需要重新开始。")
        case .connecting: status = "正在建立安全连接"
        @unknown default: fail("连接状态无法识别，请重新连接。")
        }
    }

    fileprivate func received(_ frame: Data, peer: MCPeerID, source: MCSession) {
        guard running, source === session else { return }
        guard UIApplication.shared.applicationState == .active else {
            fail("应用已离开前台，附近同步已停止。")
            return
        }
        guard peer == target, let channel, !frame.isEmpty, frame.count <= Self.maximumFrame else {
            fail(NearbySecurityError.invalidMessage.localizedDescription)
            return
        }
        let body = Data(frame.dropFirst())
        do {
            switch frame.first {
            case 0:
                guard phase == .commitment else { throw NearbySecurityError.invalidState }
                try channel.receiveCommitment(body)
                phase = .hello
                try sendFrame(type: 1, data: channel.hello)
            case 1:
                guard phase == .hello else { throw NearbySecurityError.invalidState }
                try channel.receiveHello(body)
                phase = .confirmation
                verificationCode = channel.verificationCode
                if let key = channel.remoteIdentity, trustedKeys.contains(key) {
                    status = "已验证已配对设备，等待对方确认"
                    try sendConfirmation()
                } else {
                    needsVerification = true
                    status = "请核对两台设备的六位校验码，并在两端确认一致"
                }
            case 2:
                guard phase == .confirmation else { throw NearbySecurityError.invalidState }
                try channel.receiveConfirmation(body)
                try becomeReadyIfConfirmed()
            case 3:
                guard phase == .ready, isReady else { throw NearbySecurityError.invalidState }
                try receiveApplication(channel.open(body))
            default: throw NearbySecurityError.invalidMessage
            }
        } catch { fail(error.localizedDescription) }
    }

    private func sendConfirmation() throws {
        guard let channel else { throw NearbySecurityError.invalidState }
        try sendFrame(type: 2, data: channel.confirmLocally())
    }

    private func becomeReadyIfConfirmed() throws {
        guard let channel, channel.isReady, !isReady, let key = channel.remoteIdentity else { return }
        // Persistence must succeed before the application is allowed to send data.
        try NearbyIdentityStore.trust(key)
        phase = .ready
        needsVerification = false
        timeout?.cancel()
        timeout = nil
        isReady = true
        status = "安全连接已建立"
        onReady?()
    }

    private func sendFrame(type: UInt8, data: Data) throws {
        guard running, UIApplication.shared.applicationState == .active,
              let session, let target, session.connectedPeers == [target],
              data.count + 1 <= Self.maximumFrame else { throw NearbySecurityError.invalidState }
        try session.send(Data([type]) + data, toPeers: [target], with: .reliable)
    }

    private func sendApplication(_ data: Data) throws {
        guard let channel, isReady else { throw NearbySecurityError.invalidState }
        try sendFrame(type: 3, data: channel.seal(data))
    }

    private func receiveApplication(_ data: Data) throws {
        guard let type = data.first else { throw NearbySecurityError.invalidMessage }
        switch type {
        case 0: // Begin; at most one incoming payload, exact declared size.
            guard incoming == nil, data.count == 9,
                  let size = NearbySecureChannel.decode(Data(data.dropFirst())),
                  size <= UInt64(Self.maximumPayload) else { throw NearbySecurityError.invalidMessage }
            incoming = Incoming(total: Int(size))
            try acknowledge(0)
        case 1: // Chunk includes exact expected offset; no gaps or overlaps.
            guard let total = incoming?.total, let receivedCount = incoming?.data.count,
                  data.count > 9, data.count <= Self.chunkSize + 9,
                  let offset = NearbySecureChannel.decode(Data(data[1..<9])),
                  offset == UInt64(receivedCount),
                  data.count - 9 <= total - receivedCount else {
                throw NearbySecurityError.invalidMessage
            }
            incoming?.data.append(data.dropFirst(9))
            try acknowledge(receivedCount + data.count - 9)
        case 2: // End: no data leaves this layer until the full bounded body exists.
            guard data.count == 1, let transfer = incoming, transfer.data.count == transfer.total else {
                throw NearbySecurityError.invalidMessage
            }
            incoming = nil
            refreshTransferTimeout()
            onData?(transfer.data)
            return
        case 3: // Ack; exactly one chunk can be queued ahead of the receiver.
            guard var transfer = outgoing, data.count == 9,
                  let offset = NearbySecureChannel.decode(Data(data.dropFirst())),
                  offset == UInt64(transfer.expectedAcknowledgement) else {
                throw NearbySecurityError.invalidMessage
            }
            transfer.acknowledged = Int(offset)
            if transfer.acknowledged == transfer.data.count {
                outgoing = nil
                try sendApplication(Data([2]))
            } else {
                let end = min(transfer.acknowledged + Self.chunkSize, transfer.data.count)
                let chunk = Data([1]) + NearbySecureChannel.encode(offset)
                    + transfer.data[transfer.acknowledged..<end]
                transfer.expectedAcknowledgement = end
                outgoing = transfer
                try sendApplication(chunk)
            }
        default: throw NearbySecurityError.invalidMessage
        }
        refreshTransferTimeout()
    }

    private func acknowledge(_ count: Int) throws {
        try sendApplication(Data([3]) + NearbySecureChannel.encode(UInt64(count)))
    }

    private func refreshTransferTimeout() {
        if incoming != nil || outgoing != nil {
            armTimeout(seconds: 60, message: "同步传输超时，连接已停止。请重新连接后重试。")
        } else {
            timeout?.cancel()
            timeout = nil
        }
    }

    private func armTimeout(seconds: UInt64, message: String) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.fail(message)
        }
    }

    fileprivate func fail(_ message: String) {
        stop()
        errorMessage = message
        status = message
    }
}

/// Framework callbacks can arrive off-main. Bound data waiting for the main actor
/// before enqueueing it, and reject streams/resources (the app only uses frames).
/// MCSession itself owns its initial receive allocation; its API has no frame-size
/// configuration. This bounds application decoding and queued frame retention.
private final class NearbyTransportDelegate: NSObject, MCSessionDelegate,
    MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    @MainActor private weak var owner: NearbyTransport?
    private let lock = NSLock()
    private var queuedBytes = 0
    private var overflowReported = false

    @MainActor init(owner: NearbyTransport) { self.owner = owner }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in self?.owner?.stateChanged(state, peer: peerID, source: session) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        lock.lock()
        let allowed = data.count <= NearbyTransport.maximumFrame && queuedBytes + data.count <= 4 * NearbyTransport.maximumFrame
        if allowed { queuedBytes += data.count }
        let report = !allowed && !overflowReported
        if report { overflowReported = true }
        lock.unlock()
        guard allowed else {
            if report {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.owner?.session === session { self.owner?.fail("同步消息过大或发送过快，连接已停止。") }
                    self.resetOverflow()
                }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.release(data.count) }
            self.owner?.received(data, peer: peerID, source: session)
        }
    }

    private func release(_ size: Int) { lock.lock(); queuedBytes -= size; lock.unlock() }
    private func resetOverflow() { lock.lock(); overflowReported = false; lock.unlock() }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close()
        rejectUnsupported(session)
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        progress.cancel()
        rejectUnsupported(session)
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        rejectUnsupported(session)
    }

    private func rejectUnsupported(_ session: MCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let owner = self?.owner, owner.session === session else { return }
            owner.fail("收到不支持的同步传输类型，连接已停止。")
        }
    }

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID,
                 certificateHandler: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            // MC encryption supplies link confidentiality. Signed ephemeral pairing
            // authenticates the peer before any application bytes are accepted.
            certificateHandler(self?.owner?.acceptsCertificate(from: peerID, source: session) == true)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard context == nil || context?.isEmpty == true else { invitationHandler(false, nil); return }
        DispatchQueue.main.async { [weak self] in
            guard let owner = self?.owner else { invitationHandler(false, nil); return }
            owner.invited(peerID, context: context, source: advertiser, handler: invitationHandler)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let owner = self?.owner, owner.advertiser === advertiser else { return }
            owner.fail("无法发现附近设备，请检查系统设置中的本地网络权限。\(error.localizedDescription)")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in self?.owner?.discovered(peerID, in: browser) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in self?.owner?.lost(peerID, in: browser) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let owner = self?.owner, owner.browser === browser else { return }
            owner.fail("无法搜索附近设备，请检查系统设置中的本地网络权限。\(error.localizedDescription)")
        }
    }
}
