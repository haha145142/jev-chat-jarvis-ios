import SwiftUI

/// 上下文页的本地状态（与 ConfigStore 分开：只管对话记录与上下文设置）。
@MainActor
final class ContextStoreUI: ObservableObject {
    @Published var settings: ContextSettings {
        didSet { JevContextStore.shared.saveSettings(settings) }
    }
    @Published var turns: [ChatTurn] = []
    @Published var transcriptDraft: String = ""
    @Published var lastParsedCount: Int = 0

    init() {
        settings = JevContextStore.shared.loadSettings()
        refresh()
    }

    func refresh() { turns = JevContextStore.shared.turns() }

    func delete(_ id: ChatTurn.ID) {
        JevContextStore.shared.remove(id: id)
        refresh()
    }

    func clearAll() {
        JevContextStore.shared.clear()
        refresh()
    }

    func parseAndAdd() {
        lastParsedCount = JevContextStore.shared.addParsedTranscript(transcriptDraft)
        if lastParsedCount > 0 { transcriptDraft = "" }
        refresh()
    }
}

/// 「上下文」页：自动记忆开关、联系人称呼、常驻笔记、多行粘贴、历史管理。
struct ContextView: View {
    @EnvironmentObject private var cfg: ConfigStore
    @StateObject private var ctx = ContextStoreUI()

    private var lang: JevLanguage { cfg.language }

    var body: some View {
        NavigationStack {
            List {
                settingsSection
                transcriptSection
                historySection
            }
            .navigationTitle(jevLocalized(lang, zh: "上下文", en: "Context"))
            .onAppear { ctx.refresh() }
        }
    }

    // MARK: 设置

    private var settingsSection: some View {
        Section {
            Toggle(jevLocalized(lang, zh: "自动记忆每一轮", en: "Auto-save every exchange"),
                   isOn: $ctx.settings.autoRecord)
            TextField(jevLocalized(lang, zh: "联系人称呼（留空显示「对方」）", en: "Contact name (blank = Them)"),
                      text: $ctx.settings.contactName)
            TextField(jevLocalized(lang, zh: "常驻背景笔记（关系、前情提要）", en: "Standing background note"),
                      text: $ctx.settings.standingNote, axis: .vertical)
                .lineLimit(2...5)
            Stepper(value: $ctx.settings.maxTurns, in: 6...60, step: 2) {
                Text(jevLocalized(lang,
                                  zh: "最多保留 \(ctx.settings.maxTurns) 条",
                                  en: "Keep up to \(ctx.settings.maxTurns)"))
            }
        } header: {
            Text(jevLocalized(lang, zh: "记忆设置", en: "Memory settings"))
        } footer: {
            Text(jevLocalized(lang,
                              zh: "开了自动记忆后，在键盘上「分析 → 点候选插入」就会把对方消息和你的回复记成一轮，下次分析自动带上。",
                              en: "With auto-save on, analyzing and inserting a suggestion records the exchange for next time."))
        }
    }

    // MARK: 多行粘贴

    private var transcriptSection: some View {
        Section {
            TextField(jevLocalized(lang, zh: "把多行聊天记录粘到这里", en: "Paste multi-line chat here"),
                      text: $ctx.transcriptDraft, axis: .vertical)
                .lineLimit(4...9)
                .font(.system(.caption, design: .monospaced))
            Button {
                ctx.parseAndAdd()
            } label: {
                Label(jevLocalized(lang, zh: "解析并加入", en: "Parse & add"), systemImage: "doc.text")
            }
            .disabled(ctx.transcriptDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            if ctx.lastParsedCount > 0 {
                Text(jevLocalized(lang,
                                  zh: "上次解析加入 \(ctx.lastParsedCount) 条",
                                  en: "Last parse added \(ctx.lastParsedCount)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(jevLocalized(lang, zh: "一次补多句", en: "Add many at once"))
        } footer: {
            Text(jevLocalized(lang,
                              zh: "微信 / QQ 里「多选 → 复制」，形如「名字: 内容」会自动区分「对方 / 我」；日期等杂行会忽略。",
                              en: "Use Select → Copy in WeChat/QQ. Lines like “Name: text” are split by speaker; date lines are ignored."))
        }
    }

    // MARK: 历史

    private var historySection: some View {
        Section {
            if ctx.turns.isEmpty {
                Text(jevLocalized(lang, zh: "还没有记住的对话", en: "No saved conversation yet"))
                    .foregroundStyle(.secondary)
            }
            ForEach(ctx.turns) { turn in
                HStack(alignment: .top, spacing: 8) {
                    Text(turn.speaker.label(language: lang, contactName: ctx.settings.contactName))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(turn.speaker == .them ? Color(KB.brand) : .green)
                        .frame(width: 46, alignment: .leading)
                    Text(turn.text).font(.subheadline)
                }
            }
            .onDelete { offsets in
                for i in offsets where ctx.turns.indices.contains(i) {
                    ctx.delete(ctx.turns[i].id)
                }
            }
            if !ctx.turns.isEmpty {
                Button(role: .destructive) {
                    ctx.clearAll()
                } label: {
                    Label(jevLocalized(lang, zh: "清空，开始新对话", en: "Clear & start a new chat"),
                          systemImage: "trash")
                }
            }
        } header: {
            Text(jevLocalized(lang, zh: "已记住的对话", en: "Saved conversation"))
        }
    }
}
