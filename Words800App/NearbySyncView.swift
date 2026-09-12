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
                Text("离开页面或切到后台会停止同步。收藏、笔记、答题和学习记录会合并；提醒时间、每日目标和未完成练习进度各自保留。")
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
                SyncConflictSections(conflicts: preview.conflicts, choices: $model.choices, incomingLabel: "对方")
                Section {
                    Button("发送合并方案，等待对方确认") { model.confirmMerge() }.disabled(!model.allConflictsChosen)
                    Button("取消此次同步", role: .destructive) { model.cancel() }
                }
            }
            if model.needsApproval {
                Section("保存前确认") {
                    Text("本机将新增 \(model.incomingCount) 条记录，原有历史全部保留。")
                    Text("下面列出笔记、错误次数、收藏和掌握程度的变化。答题记录按条合并，复习安排由合并后的学习记录重新计算。")
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
                Text("本机：" + (conflict.localValue.isEmpty ? "空笔记" : conflict.localValue)).textSelection(.enabled)
                Text("\(incomingLabel)：" + (conflict.incomingValue.isEmpty ? "空笔记" : conflict.incomingValue)).textSelection(.enabled)
                choice("保留本机", value: .local, conflict: conflict)
                choice("保留\(incomingLabel)", value: .incoming, conflict: conflict)
                if conflict.kind == .note { choice("两份笔记合并", value: .combined, conflict: conflict) }
                Text(conflict.kind == .note ? "旧笔记仍保留在词条的笔记历史中。" : "选择最终错误总数，不会删除历史错题。两台的总数不会直接相加。")
                    .font(.footnote).foregroundColor(.secondary)
            }
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
    let preview: SyncMergePreview
    @State private var choices: [String: SyncChoice] = [:]
    @State private var errorMessage = ""
    var body: some View {
        NavigationView {
            List {
                Section("导入预览") {
                    Text("本机将新增 \(preview.incomingCount) 条学习操作，已有记录和历史会保留。")
                    Text("收藏、掌握程度和复习安排按事件时间合并。遇到双方修改的笔记和手动次数，需先选择最终内容。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                SyncConflictSections(conflicts: preview.conflicts, choices: $choices, incomingLabel: "备份")
                if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundColor(.red) } }
                Section {
                    Button("确认导入并保存") {
                        do {
                            let result = try SyncMergeEngine.resolve(preview, choices: choices)
                            try dataManager.commitImport(result, expected: preview.local)
                            dismiss(); dataManager.message = "备份已合并，原有学习记录和历史已保留。"
                        } catch { errorMessage = error.localizedDescription }
                    }.disabled(!preview.conflicts.allSatisfy { choices[$0.id] != nil })
                }
            }
            .navigationTitle("合并学习备份").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.navigationViewStyle(.stack)
    }
}
