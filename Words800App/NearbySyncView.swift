import SwiftUI

struct NearbySyncView: View {
    @StateObject private var model: NearbySyncModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var forgetConfirmation = false
    @State private var localMessage = ""

    init(dataManager: DataManager) { _model = StateObject(wrappedValue: NearbySyncModel(dataManager: dataManager)) }

    var body: some View {
        List {
            Section {
                Label("仅两台设备之间传输", systemImage: "lock.shield")
                    .font(.headline).foregroundColor(AppStyle.accent)
                Text("无需账号或互联网。两台都打开本页面并开启 Wi-Fi、蓝牙；首次允许“本地网络”。同一 Wi-Fi 下更容易发现，路由器无需连接互联网。")
                    .font(.footnote).foregroundColor(.secondary)
                Text("两台 App 都需升级到支持 v3 内容的版本。离开页面或切到后台会停止同步。手动词条、题目、收藏、笔记、近义词、答题和学习记录会合并；提醒时间、每日目标和未完成练习进度各自保留。")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("连接状态") {
                Text(model.status).fixedSize(horizontal: false, vertical: true)
                if model.started { Text(model.transport.status).font(.footnote).foregroundColor(.secondary) }
                if !model.transport.errorMessage.isEmpty { Text(model.transport.errorMessage).font(.footnote).foregroundColor(.red) }
                if !localMessage.isEmpty { Text(localMessage).font(.footnote).foregroundColor(.secondary) }
                Button(model.started ? "断开并重新寻找" : "开始寻找附近设备") { localMessage = ""; model.start() }
                if model.started { Button("停止同步", role: .destructive) { model.stop() } }
            }
            if let invite = model.transport.invitation {
                Section("收到连接请求") {
                    Text("\(invite.displayName) 想与你连接。仅接受你自己的设备。")
                    Button("允许连接") { model.transport.acceptInvitation() }
                    Button("拒绝", role: .destructive) { model.transport.declineInvitation() }
                }
            }
            if !model.transport.isReady, let code = model.transport.verificationCode {
                Section("核对配对码") {
                    Text(code).font(.system(size: 38, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity).padding(.vertical, 12).accessibilityLabel("配对码 " + code.map(String.init).joined(separator: " "))
                    Text("请确认两台屏幕上的六位数字完全相同，并在两台都点确认。不同就取消；设备名称相同不能证明身份。")
                        .font(.footnote).foregroundColor(.secondary)
                    if model.transport.needsVerification {
                        Button("数字一致，确认是我的设备") { model.transport.confirmVerification() }
                    } else {
                        Text("本机已确认，请在另一台核对并确认。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Button("不一致，取消连接", role: .destructive) { model.transport.rejectVerification() }
                }
            }
            if model.started && !model.transport.isReady && model.transport.connectedName.isEmpty && model.transport.invitation == nil {
                Section("发现的设备") {
                    if model.transport.peers.isEmpty {
                        Text("尚未发现另一台。请在另一台也点“开始寻找附近设备”，并检查设置中的本地网络权限。")
                            .foregroundColor(.secondary)
                    }
                    ForEach(model.transport.peers) { peer in
                        Button { model.transport.connect(peer) } label: { Label(peer.displayName, systemImage: "ipad.and.iphone") }
                    }
                }
            }
            if let preview = model.preview {
                Section("合并概况") {
                    Text("本机新增 \(preview.incomingCount) 条记录，对方新增 \(preview.outgoingCount) 条记录。")
                    Text("新增条数是学习操作数量，不是词数；重复记录不会再次计入。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                SyncContentSummaryView(summary: preview.contentChanges)
                if !preview.contentConflicts.isEmpty {
                    SyncContentConflictSections(preview: preview, choices: $model.contentChoices)
                } else {
                    SyncContentChangesView(preview: preview)
                    SyncConflictSections(conflicts: preview.conflicts, choices: $model.choices, incomingLabel: "对方")
                }
                Section {
                    if !preview.contentConflicts.isEmpty {
                        Button("确认内容选择，继续核对") { model.resolveContent() }.disabled(!model.allConflictsChosen)
                    } else {
                        Button("发送合并方案，等待对方确认") { model.confirmMerge() }.disabled(!model.allConflictsChosen)
                    }
                    Button("取消此次同步", role: .destructive) { model.cancel() }
                }
            }
            if model.needsApproval {
                if let preview = model.proposalPreview {
                    SyncContentSummaryView(summary: preview.contentChanges, showOutgoing: false)
                    SyncContentChangesView(preview: preview)
                }
                Section("保存前确认") {
                    Text("本机将新增 \(model.incomingCount) 条记录，原有历史全部保留。")
                    Text("下面列出笔记、近义词、错误次数、收藏和掌握程度的变化。答题记录按条合并，复习安排由合并后的学习记录重新计算。")
                        .font(.footnote).foregroundColor(.secondary)
                    Button("确认变化并保存到本机") { model.approveProposal() }
                    Button("拒绝此次合并", role: .destructive) { model.cancel() }
                }
                ForEach(model.changes) { change in
                    Section(change.word) {
                        ForEach(Array(change.details.enumerated()), id: \.offset) { _, detail in
                            Text(detail).font(.subheadline).textSelection(.enabled)
                        }
                    }
                }
            }
            Section("配对管理") {
                Button("忘记已配对设备", role: .destructive) { forgetConfirmation = true }
                Text("忘记配对不会删除学习记录，下次连接需要重新确认配对码。扫描发现并不代表已获准读取你的记录。")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .navigationTitle("附近设备同步").navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { if $0 == .background { model.backgrounded() } }
        .confirmationDialog("忘记所有已配对设备？学习记录不会删除。", isPresented: $forgetConfirmation, titleVisibility: .visible) {
            Button("忘记配对", role: .destructive) {
                model.stop()
                do { try model.transport.forgetTrustedDevices(); localMessage = "已忘记配对设备。" }
                catch { localMessage = error.localizedDescription }
            }
        }
    }
}

// Used by nearby sync and manual backup imports, including clearing a note or resetting a count.
struct SyncConflictSections: View {
    let conflicts: [SyncConflict]
    @Binding var choices: [String: SyncChoice]
    let incomingLabel: String
    var body: some View {
        ForEach(conflicts) { conflict in
            Section("\(conflict.word) · \(conflict.title)冲突") {
                Text("本机：" + filled(conflict.localDisplay, conflict)).textSelection(.enabled)
                Text("\(incomingLabel)：" + filled(conflict.incomingDisplay, conflict)).textSelection(.enabled)
                choice("保留本机", value: .local, conflict: conflict)
                choice("保留\(incomingLabel)", value: .incoming, conflict: conflict)
                if conflict.kind != .errorCount {
                    choice(conflict.kind == .note ? "两份笔记合并" : "两份近义词合并", value: .combined, conflict: conflict)
                }
                Text(footnote(conflict)).font(.footnote).foregroundColor(.secondary)
            }
        }
    }
    private func filled(_ value: String, _ conflict: SyncConflict) -> String {
        guard value.isEmpty else { return value }
        return conflict.kind == .note ? "空笔记" : ""
    }
    private func footnote(_ conflict: SyncConflict) -> String {
        switch conflict.kind {
        case .note: return "旧笔记仍保留在词条的笔记历史中。"
        case .synonym: return "合并会保留两份里不重复的近义词；旧内容仍保留在词条的近义词修改历史中。"
        case .errorCount: return "选择最终错误总数，不会删除历史错题。两台的总数不会直接相加。"
        }
    }
    private func choice(_ title: String, value: SyncChoice, conflict: SyncConflict) -> some View {
        Button { choices[conflict.id] = value } label: {
            HStack { Text(title); Spacer(); if choices[conflict.id] == value { Image(systemName: "checkmark") } }
        }
    }
}

struct BackupMergeView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var preview: SyncMergePreview
    @State private var choices: [String: SyncChoice] = [:]
    @State private var contentChoices: [String: UUID] = [:]
    @State private var errorMessage = ""
    @State private var stale = false
    @State private var completed = false
    init(preview: SyncMergePreview) { _preview = State(initialValue: preview) }
    var body: some View {
        NavigationView {
            List {
                Section("导入预览") {
                    Text("本机将新增 \(preview.incomingCount) 条学习操作，已有记录和历史会保留。")
                    Text("收藏、掌握程度和复习安排按事件时间合并。遇到双方修改的笔记、近义词和手动次数，需先选择最终内容。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                SyncContentSummaryView(summary: preview.contentChanges, otherLabel: "相对备份")
                if !preview.contentConflicts.isEmpty {
                    SyncContentConflictSections(preview: preview, choices: $contentChoices)
                } else {
                    SyncContentChangesView(preview: preview)
                    SyncConflictSections(conflicts: preview.conflicts, choices: $choices, incomingLabel: "备份")
                }
                if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundColor(.red) } }
                Section {
                    if !preview.contentConflicts.isEmpty {
                        Button("确认内容选择，继续核对") {
                            do {
                                preview = try dataManager.resolveContent(preview, choices: contentChoices)
                                contentChoices = [:]; choices = [:]; errorMessage = ""
                            } catch { errorMessage = error.localizedDescription }
                        }.disabled(stale || !preview.contentConflicts.allSatisfy { contentChoices[$0.id] != nil })
                    } else { Button("确认合并并保存") {
                        guard !completed, !stale else { return }
                        do {
                            let result = try SyncMergeEngine.resolve(preview, choices: choices)
                            try dataManager.commitImport(result, expected: preview.local)
                            completed = true
                            dismiss(); dataManager.message = "备份已合并，原有学习记录和历史已保留。"
                        } catch { errorMessage = error.localizedDescription }
                    }.disabled(stale || completed || !preview.conflicts.allSatisfy { choices[$0.id] != nil }) }
                }
            }
            .navigationTitle("合并学习备份").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.navigationViewStyle(.stack)
        .onReceive(dataManager.snapshotDidChange) { _ in
            if !completed {
                stale = true
                errorMessage = "本机内容或学习记录已变化，这份预览不能再保存。请取消后重新导入或重新打开本机冲突处理。"
            }
        }
    }
}

struct SyncContentSummaryView: View {
    let summary: SyncContentChangeSummary
    var showOutgoing = true
    var otherLabel = "对方"
    var body: some View {
        Section("个人内容变化") {
            Text("本机：" + describe(summary.incoming))
            if showOutgoing { Text(otherLabel + "：" + describe(summary.outgoing)) }
            Text("按当前词条和题目计数，编辑包含恢复。历史版本与学习操作另外保留，不按版本数重复计词。")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
    private func describe(_ value: SyncContentChangeCounts) -> String {
        "词条新增 \(value.addedWords)、编辑 \(value.editedWords)、归档 \(value.archivedWords)；题目新增 \(value.addedQuestions)、编辑 \(value.editedQuestions)、归档 \(value.archivedQuestions)"
    }
}

struct SyncContentConflictSections: View {
    @EnvironmentObject private var dataManager: DataManager
    let preview: SyncMergePreview
    @Binding var choices: [String: UUID]
    private var names: [UUID: String] {
        guard let catalog = try? dataManager.catalog(for: preview.merged) else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalog.words.map { ($0.id, $0.word) })
    }
    var body: some View {
        let resolvedNames = names
        ForEach(preview.contentConflicts) { conflict in
            Section(conflict.kind == .revision ? "同一条目的不同版本" : "同名词条：\(conflict.normalizedName ?? "")") {
                Text(conflict.kind == .revision ? "选择要保留的内容和归档状态。各版本历史会保留。" : "选择继续使用的词条，其余个人同名词将归档。原资料词条不可改写或归档。")
                    .font(.footnote).foregroundColor(.secondary)
                ForEach(conflict.options) { option in
                    VStack(alignment: .leading, spacing: 12) {
                        if let revision = option.revision {
                            Text("版本：\(revision.id.uuidString)").font(.caption2).foregroundColor(.secondary)
                            PersonalPayloadView(word: revision.word, question: revision.question, archived: revision.archived, wordNames: resolvedNames)
                        }
                        if let word = option.builtInWord {
                            Text("原资料词条：\(word.word)").font(.headline)
                            Text(word.meanings.joined(separator: "\n"))
                            Text("\(word.category) · 第 \(word.sourcePages) 页").font(.caption).foregroundColor(.secondary)
                        }
                        Button {
                            choices[conflict.id] = option.id
                        } label: {
                            Label(choices[conflict.id] == option.id ? "已选择这个版本 / 词条" : "保留这个版本 / 词条",
                                systemImage: choices[conflict.id] == option.id ? "checkmark.circle.fill" : "circle")
                        }.disabled(!option.isSelectable)
                        if !option.isSelectable { Text("已有原资料词条，个人同名词必须归档。").font(.caption).foregroundColor(.secondary) }
                        Divider()
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}

struct SyncContentChangesView: View {
    @EnvironmentObject private var dataManager: DataManager
    let preview: SyncMergePreview
    var body: some View {
        if let before = try? dataManager.catalog(for: preview.local),
           let incoming = try? dataManager.catalog(for: preview.incoming),
           let after = try? dataManager.catalog(for: preview.merged) {
            let changed = after.headsByEntryID.keys.filter {
                Set((before.headsByEntryID[$0] ?? []).map(\.id)) != Set((after.headsByEntryID[$0] ?? []).map(\.id))
                    || Set((incoming.headsByEntryID[$0] ?? []).map(\.id)) != Set((after.headsByEntryID[$0] ?? []).map(\.id))
            }.sorted { $0.uuidString < $1.uuidString }
            let names = Dictionary(uniqueKeysWithValues: after.words.map { ($0.id, $0.word) })
            ForEach(changed, id: \.self) { entryID in
                Section("\(names[entryID] ?? "手动题目") · 合并后的内容") {
                    ForEach(after.headsByEntryID[entryID] ?? []) { revision in
                        PersonalPayloadView(word: revision.word, question: revision.question, archived: revision.archived, wordNames: names)
                    }
                    if let old = before.headsByEntryID[entryID], !old.isEmpty {
                        DisclosureGroup("查看本机合并前的内容") {
                            ForEach(old) { revision in
                                PersonalPayloadView(word: revision.word, question: revision.question, archived: revision.archived, wordNames: names)
                            }
                        }
                    }
                    if let old = incoming.headsByEntryID[entryID], !old.isEmpty {
                        DisclosureGroup("查看传入内容") {
                            ForEach(old) { revision in
                                PersonalPayloadView(word: revision.word, question: revision.question, archived: revision.archived, wordNames: names)
                            }
                        }
                    }
                }
            }
        }
    }
}
