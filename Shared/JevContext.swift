import Foundation

// MARK: - 对话上下文（多轮记忆）
//
// iPhone 没有安卓那种「无障碍读屏」能力，键盘只能拿到两样东西：剪贴板里最新的一条、
// 当前输入框里的文字。本文件在 App Group 里维护一份「滚动的对话记录」，让判断层和起草层
// 都能看到前情：
//   · 自动记忆：分析对方消息 → 点一条候选插入，就把「对方消息 + 你选的回复」记成一轮；
//   · 手动补充：管理页可把剪贴板内容按「对方 / 我」逐条加入，也可一次粘贴多行自动拆分；
//   · 常驻笔记：写一段背景（两人关系、前情提要），每次分析都带上。
// 生成出的文本通过 JevPipeline 的 context 参数注入（见 JevPrompts / JevJudge）。

/// 换行符（用码位构造，避免在源码里写反斜杠转义）。
private let jevNL = String(Character(UnicodeScalar(10)!))

/// 一条对话。
struct ChatTurn: Codable, Equatable, Identifiable {
    enum Speaker: String, Codable {
        case them
        case me

        /// 注入模型 / 展示时用的称呼。对方可替换成联系人名字。
        func label(language: JevLanguage, contactName: String?) -> String {
            if language == .english { return self == .them ? "Them" : "Me" }
            if self == .them, let name = contactName, !name.isEmpty { return name }
            return self == .them ? "对方" : "我"
        }
    }

    var id: UUID = UUID()
    var speaker: Speaker
    var text: String
    var at: Date = Date()
}

/// 上下文相关设置（单独存一个 key，避免改动 JevConfig 的 Codable 结构）。
struct ContextSettings: Codable, Equatable {
    /// 点候选插入后自动记录一轮（默认开）。
    var autoRecord: Bool = true
    /// 联系人怎么称呼（留空则显示「对方」）。
    var contactName: String = ""
    /// 常驻背景笔记，每次分析都带上。
    var standingNote: String = ""
    /// 最多保留多少条对话（滚动窗口，控制 token 与内存）。
    var maxTurns: Int = 24
}

/// 对话上下文的唯一存放点。
final class JevContextStore {
    static let shared = JevContextStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private static let turnsKey = "jev.context.turns.v1"
    private static let settingsKey = "jev.context.settings.v1"

    init(defaults: UserDefaults = JevStore.defaults) {
        self.defaults = defaults
    }

    // MARK: 无锁内部实现（公共方法先拿锁，再调用这些，避免 NSLock 重入死锁）

    private func _settings() -> ContextSettings {
        guard let data = defaults.data(forKey: Self.settingsKey),
              let s = try? JSONDecoder().decode(ContextSettings.self, from: data) else {
            return ContextSettings()
        }
        return s
    }

    private func _turns() -> [ChatTurn] {
        guard let data = defaults.data(forKey: Self.turnsKey),
              let t = try? JSONDecoder().decode([ChatTurn].self, from: data) else { return [] }
        return t
    }

    private func _persist(_ turns: [ChatTurn]) {
        let cap = max(1, _settings().maxTurns)
        let trimmed = Array(turns.suffix(cap))
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: Self.turnsKey)
        }
    }

    // MARK: 设置

    func loadSettings() -> ContextSettings {
        lock.lock(); defer { lock.unlock() }
        return _settings()
    }

    func saveSettings(_ s: ContextSettings) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: 读 / 写对话

    func turns() -> [ChatTurn] {
        lock.lock(); defer { lock.unlock() }
        return _turns()
    }

    func replace(_ turns: [ChatTurn]) {
        lock.lock(); defer { lock.unlock() }
        _persist(turns)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.turnsKey)
    }

    func remove(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var t = _turns()
        t.removeAll { $0.id == id }
        _persist(t)
    }

    /// 追加一条。
    func append(_ speaker: ChatTurn.Speaker, text raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var t = _turns()
        t.append(ChatTurn(speaker: speaker, text: text))
        _persist(t)
    }

    /// 自动记录一轮：对方来的消息 + 我选的回复。
    ///
    /// - 相同的对方消息已在记录里则不重复添加（「换一批」后再点候选也不会重复）；
    /// - 若末尾已经是一模一样的「我」回复，也不重复追加。
    func recordExchange(incoming rawIncoming: String?, reply rawReply: String) {
        let reply = rawReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var t = _turns()

        var addedIncoming = false
        if let incoming = rawIncoming?.trimmingCharacters(in: .whitespacesAndNewlines), !incoming.isEmpty {
            let already = t.contains { $0.speaker == .them && $0.text == incoming }
            if !already {
                t.append(ChatTurn(speaker: .them, text: incoming))
                addedIncoming = true
            }
        }
        if let last = t.last, last.speaker == .me, last.text == reply, !addedIncoming {
            // 同一条回复已在末尾，别重复
            _persist(t)
            return
        }
        t.append(ChatTurn(speaker: .me, text: reply))
        _persist(t)
    }

    /// 把一段多行文本解析成若干条对话并加入，返回新增条数。
    @discardableResult
    func addParsedTranscript(_ raw: String) -> Int {
        let contactName = loadSettings().contactName
        let parsed = Self.parseTranscript(raw, contactName: contactName)
        guard !parsed.isEmpty else { return 0 }
        lock.lock(); defer { lock.unlock() }
        var t = _turns()
        t.append(contentsOf: parsed)
        _persist(t)
        return parsed.count
    }

    // MARK: 多行粘贴解析
    //
    // 兼容微信 / QQ「多选 → 复制」、合并转发、截图 OCR 文本等：
    //   · 每行若形如「名字: 内容」，名字是「我 / 自己 / me」判为我方，其余判为对方；
    //   · 没有名字前缀的行，视为对方连续发言；
    //   · 纯日期、星期、「上午 / 下午」这类杂行忽略。
    static func parseTranscript(_ raw: String, contactName: String) -> [ChatTurn] {
        var out: [ChatTurn] = []
        for var line in raw.components(separatedBy: .newlines) {
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isNoise(line) { continue }

            var speaker: ChatTurn.Speaker = .them
            var content = line
            if let colon = firstColon(line), colon.idx <= 20, colon.idx >= 1 {
                let name = String(line[line.startIndex..<colon.position])
                    .trimmingCharacters(in: .whitespaces)
                content = String(line[line.index(after: colon.position)...])
                    .trimmingCharacters(in: .whitespaces)
                if ["我", "自己", "本人", "me", "Me", "ME"].contains(name) {
                    speaker = .me
                } else {
                    speaker = .them
                }
            }
            if !content.isEmpty {
                out.append(ChatTurn(speaker: speaker, text: content))
            }
        }
        return out
    }

    /// 第一个半角/全角冒号的位置（取更靠前的）。
    private static func firstColon(_ line: String) -> (position: String.Index, idx: Int)? {
        var best: (String.Index, Int)?
        if let r = line.range(of: ":") {
            let i = line.distance(from: line.startIndex, to: r.lowerBound)
            best = (r.lowerBound, i)
        }
        if let r = line.range(of: "：") {
            let i = line.distance(from: line.startIndex, to: r.lowerBound)
            if best == nil || i < best!.1 { best = (r.lowerBound, i) }
        }
        return best
    }

    /// 杂行判断：日期、星期、时间段、占位提示。
    private static func isNoise(_ line: String) -> Bool {
        let prefixes = ["上午", "下午", "早上", "晚上", "凌晨", "中午", "星期", "周"]
        for p in prefixes where line.hasPrefix(p) { return true }
        let first = String(line.prefix(1))
        let isDigit = first.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 48 && $0.value <= 57 }
        if isDigit && (line.contains("-") || line.contains("/") || line.contains("年") || line.contains("月")) {
            return true
        }
        let placeholders = ["[图片]", "[表情]", "[语音]", "[视频]"]
        for p in placeholders where line == p { return true }
        return false
    }

    // MARK: 注入给模型的上下文文本
    //
    // 按时间顺序列出最近若干轮；当前正要回复的消息若已在末尾（用户先手动加过），剔除掉，
    // 因为它会作为 message 单独出现，避免同一句话重复。
    func contextString(forAnswering message: String?, language: JevLanguage) -> String {
        lock.lock(); defer { lock.unlock() }
        let settings = _settings()
        var t = _turns()

        if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            while let last = t.last, last.speaker == .them, last.text == message {
                t.removeLast()
            }
        }

        var blocks: [String] = []
        let note = settings.standingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            blocks.append((language == .english ? "Background:" + jevNL : "背景：") + note)
        }
        if !t.isEmpty {
            let lines = t.map { turn -> String in
                let name = turn.speaker.label(language: language, contactName: settings.contactName)
                let sep = language == .english ? ": " : "："
                return name + sep + turn.text
            }
            let title = language == .english ? "Recent conversation:" + jevNL : "最近的对话：" + jevNL
            blocks.append(title + lines.joined(separator: jevNL))
        }
        return blocks.joined(separator: jevNL + jevNL)
    }

    // MARK: 状态摘要

    /// (总条数, 已完成的轮数)。轮数按「我」的回复数算。
    func stats() -> (turns: Int, rounds: Int) {
        let t = turns()
        return (t.count, t.filter { $0.speaker == .me }.count)
    }

    func isEmpty() -> Bool { turns().isEmpty }

    /// 待机页那一行的状态文案。
    func statusText(language: JevLanguage) -> String {
        let (turns, rounds) = stats()
        if turns == 0 {
            return language == .english ? "Context: none" : "上下文：无"
        }
        if language == .english {
            return rounds > 0 ? "Context: " + String(rounds) + " exchanges"
                              : "Context: " + String(turns) + " messages"
        }
        return rounds > 0 ? "上下文：" + String(rounds) + " 轮"
                          : "上下文：" + String(turns) + " 条"
    }
}
