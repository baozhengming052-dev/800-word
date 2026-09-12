import Foundation
import Combine
import CryptoKit

struct SyncChange: Identifiable {
    let id: UUID
    let word: String
    let details: [String]
}

@MainActor final class NearbySyncModel: ObservableObject {
    let transport = NearbyTransport()
    @Published private(set) var started = false
    @Published private(set) var status = "两台设备都打开此页面，再开始寻找。"
    @Published private(set) var preview: SyncMergePreview?
    @Published var choices: [String: SyncChoice] = [:]
    @Published private(set) var changes: [SyncChange] = []
    @Published private(set) var needsApproval = false
    @Published private(set) var incomingCount = 0
    @Published private(set) var finished = false
    @Published private(set) var savedLocally = false
    private let dataManager: DataManager
    private var observation: AnyCancellable?
    private var readiness: AnyCancellable?
    private var exchange: SyncExchange?
    private var baseline: StudySnapshot?
    private var proposal: StudySnapshot?
    private var proposalDigest: String?
    private var timeout: Task<Void, Never>?

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        observation = transport.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        readiness = transport.$isReady.dropFirst().sink { [weak self] ready in
            guard let self = self, !ready, self.exchange != nil, !self.finished else { return }
            self.interrupted("连接已断开，请重新开始。")
        }
        transport.onReady = { [weak self] in self?.connected() }
        transport.onData = { [weak self] data in self?.received(data) }
    }

    func start() {
        stop()
        exchange = nil; baseline = nil; proposal = nil; proposalDigest = nil
        preview = nil; choices = [:]; changes = []; needsApproval = false
        incomingCount = 0; finished = false; savedLocally = false; started = true
        status = "选择另一台设备；也可以在另一台上发起连接。"
        transport.start()
    }
    func stop() {
        timeout?.cancel(); timeout = nil
        if var run = exchange, let cancel = run.cancel(reason: "对方已离开同步页面。") {
            exchange = run
            if transport.isReady { try? send(cancel) }
        }
        exchange = nil
        transport.stop(); started = false; preview = nil; needsApproval = false
        if !finished { status = savedLocally ? "本机已保存，对方可能未完成。重新同步即可补齐，不会重复计数。" : "同步已停止，已保存的学习记录不会被删除。" }
    }
    func backgrounded() { if started { stop() } }
    var allConflictsChosen: Bool { preview?.conflicts.allSatisfy { choices[$0.id] != nil } ?? false }

    private func connected() {
        exchange = SyncExchange(initiator: transport.isInitiator)
        status = "安全连接已建立，正在交换学习记录…"
        do {
            if transport.isInitiator, var run = exchange {
                let packet = try run.begin(); exchange = run; try send(packet)
            }
            armTimeout()
        } catch { fail(error) }
    }

    private func received(_ data: Data) {
        do {
            let packet = try SyncPacket.decode(data)
            try packet.validateLibrary(dataManager.libraryFingerprint)
            guard var run = exchange else { throw SyncError.invalid("没有正在进行的同步。") }
            try run.receive(packet); exchange = run
            timeout?.cancel()
            switch packet.kind {
            case .request:
                let bytes = try dataManager.exportData()
                baseline = try dataManager.validatedSnapshot(bytes)
                let response = try run.snapshot(bytes); exchange = run; try send(response)
                status = "记录已发送，等待对方查看合并结果。"
                armTimeout(seconds: 600)
            case .snapshot:
                let candidate = try dataManager.previewImport(packet.payload)
                baseline = candidate.local; preview = candidate; choices = [:]
                status = candidate.conflicts.isEmpty ? "请查看本次合并概况，再发送给对方确认。" : "两台设备有独立修改，请选择要保留的内容。"
                armTimeout(seconds: 600)
            case .proposal:
                guard let expected = baseline else { throw SyncError.invalid("缺少本机同步快照。") }
                let proposed = try dataManager.validatedSnapshot(packet.payload)
                let current = try dataManager.validatedSnapshot(dataManager.exportData())
                try SyncMergeEngine.validateCommit(current: current, expected: expected, proposed: proposed)
                proposal = proposed; proposalDigest = Self.digest(packet.payload)
                changes = changesBetween(expected, proposed)
                incomingCount = proposed.events.count - expected.events.count
                needsApproval = true
                status = "对方已确认合并方案。请检查本机变化，再确认保存。"
                armTimeout(seconds: 600)
            case .accepted:
                guard let expected = baseline, let proposed = proposal,
                      let digest = proposalDigest, packet.digest == digest else { throw SyncError.invalid("对方确认的记录与本次方案不一致。") }
                try dataManager.commitImport(proposed, expected: expected); savedLocally = true
                let response = try run.complete(digest: digest); exchange = run; try send(response)
                complete()
            case .completed:
                guard savedLocally, packet.digest == proposalDigest else { throw SyncError.invalid("完成确认的校验值不一致。") }
                complete()
            case .cancel:
                interrupted(packet.reason ?? "对方取消了本次同步。")
            }
        } catch { fail(error) }
    }

    func confirmMerge() {
        do {
            guard let preview = preview, var run = exchange else { return }
            let proposed = try SyncMergeEngine.resolve(preview, choices: choices)
            let current = try dataManager.validatedSnapshot(dataManager.exportData())
            try SyncMergeEngine.validateCommit(current: current, expected: preview.local, proposed: proposed)
            let data = try dataManager.encodedSnapshot(proposed)
            proposal = proposed; proposalDigest = Self.digest(data)
            let packet = try run.propose(data); exchange = run
            self.preview = nil; try send(packet)
            status = "合并方案已发送，等待另一台确认。此时本机还未修改记录。"
            armTimeout(seconds: 600)
        } catch { fail(error) }
    }

    func approveProposal() {
        do {
            guard let expected = baseline, let proposed = proposal, let digest = proposalDigest, var run = exchange else { return }
            try dataManager.commitImport(proposed, expected: expected); savedLocally = true
            let packet = try run.accept(digest: digest); exchange = run
            needsApproval = false; try send(packet)
            status = "本机已保存，正在等待对方保存确认…"
            armTimeout()
        } catch { fail(error) }
    }

    func cancel() {
        if var run = exchange, let packet = run.cancel(reason: "对方取消了同步。") {
            exchange = run
            if transport.isReady { try? send(packet) }
        }
        interrupted("已取消本次同步。")
    }
    private func send(_ packet: SyncPacket) throws {
        var identified = packet
        identified.libraryFingerprint = dataManager.libraryFingerprint
        try transport.send(identified.encode())
    }
    private func complete() {
        timeout?.cancel(); finished = true; preview = nil; needsApproval = false
        status = "双方学习记录已保存。可以返回学习，也可以关闭此页面。"
        UserDefaults.standard.set(Date(), forKey: "lastNearbySync")
    }
    private func interrupted(_ reason: String) {
        timeout?.cancel(); preview = nil; needsApproval = false
        status = savedLocally ? "本机已保存，但双方确认未完成。请重新同步补齐；重试不会重复计数。" : reason + " 本次未保存合并结果。"
        if var run = exchange { _ = run.cancel(reason: "连接中断"); exchange = run }
    }
    private func fail(_ error: Error) {
        if var run = exchange, let packet = run.cancel(reason: "同步校验或保存失败，请重新同步。") {
            exchange = run
            if transport.isReady { try? send(packet) }
        }
        interrupted(error.localizedDescription)
    }
    private func armTimeout(seconds: UInt64 = 120) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self = self, !Task.isCancelled else { return }
            self.fail(SyncError.invalid("等待超时，请保持两台 App 在前台并重新同步。"))
        }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func changesBetween(_ before: StudySnapshot, _ after: StudySnapshot) -> [SyncChange] {
        let a = LearningEngine.reduce(words: dataManager.words, questions: dataManager.questions, events: before.events).records
        let b = LearningEngine.reduce(words: dataManager.words, questions: dataManager.questions, events: after.events).records
        return dataManager.words.compactMap { word in
            let left = a[word.id] ?? StudyRecord(), right = b[word.id] ?? StudyRecord()
            var details: [String] = []
            if left.errorCount != right.errorCount { details.append("错误次数：\(left.errorCount) → \(right.errorCount)") }
            if left.personalNotes != right.personalNotes {
                details.append("原笔记：" + (left.personalNotes.isEmpty ? "空" : left.personalNotes))
                details.append("合并后：" + (right.personalNotes.isEmpty ? "空" : right.personalNotes))
            }
            if left.isFavorite != right.isFavorite { details.append(right.isFavorite ? "加入收藏" : "取消收藏") }
            if left.masteryLevel != right.masteryLevel { details.append("掌握程度：\(left.masteryLevel.rawValue) → \(right.masteryLevel.rawValue)") }
            return details.isEmpty ? nil : SyncChange(id: word.id, word: word.word, details: details)
        }
    }
}
