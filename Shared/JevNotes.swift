import Foundation

// MARK: - 笔记数据模型（对齐安卓 core/kb/KbModels）

/// 一条本地知识笔记。只存在本机 App Group 与进程私有库，不上传。
struct JevNote: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var content: String
    var tags: [String] = []
    /// 常驻：无论聊什么都注入。
    var alwaysOn: Bool = false
    var enabled: Bool = true
    var builtin: Bool = false
    var updatedAt: TimeInterval = Date().timeIntervalSince1970
}

// MARK: - 笔记存储与命中

enum JevNoteStore {
    private static let notesKey = "jev.notes.v1"
    private static let seedVersionKey = "jev.notes.seed.v2"

    // 对齐安卓 ContextBuilder 的预算
    static let budgetChars = 1500
    static let maxHits = 5

    static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: JevStore.appGroupID) ?? .standard
    }
    static var privateDefaults: UserDefaults { .standard }

    /// 归一化：小写、去空白与标点，用于子串命中（中文原样保留）。
    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    // MARK: 读写（group + private 双写，与配置同样的兜底）

    static func loadNotes() -> [JevNote] {
        let decoder = JSONDecoder()
        func decode(_ store: UserDefaults) -> [JevNote]? {
            guard let data = store.data(forKey: notesKey),
                  let notes = try? decoder.decode([JevNote].self, from: data) else { return nil }
            return notes
        }
        seedIfNeeded()
        return decode(groupDefaults) ?? decode(privateDefaults) ?? []
    }

    static func saveNotes(_ notes: [JevNote]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        groupDefaults.set(data, forKey: notesKey)
        privateDefaults.set(data, forKey: notesKey)
    }

    static func update(_ note: JevNote) {
        var notes = loadNotes()
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            notes[i] = note
        } else {
            notes.append(note)
        }
        saveNotes(notes)
    }

    // MARK: 命中（对齐安卓 matchNotes）

    /// 给定对方消息文本，返回应注入的笔记：常驻在前，命中在后（最多 5 条，预算 1500）。
    static func matched(for text: String) -> [JevNote] {
        let notes = loadNotes().filter { $0.enabled }
        let alwaysOn = notes.filter { $0.alwaysOn }
        let haystack = normalize(text)
        guard !haystack.isEmpty else { return alwaysOn }
        var hits = notes.filter { !$0.alwaysOn }.filter { note in
            (note.tags + [note.title]).contains { raw in
                let needle = normalize(raw)
                return !needle.isEmpty && haystack.contains(needle)
            }
        }
        // 预算：整条丢弃，不截半条。
        var cost = 0
        hits = hits.filter { note in
            let c = note.title.count + note.content.count + 2
            if cost + c > budgetChars { return false }
            cost += c
            return true
        }
        if hits.count > maxHits { hits = Array(hits.prefix(maxHits)) }
        return alwaysOn + hits
    }

    /// 拼成注入提示词的文本：每行「标题：内容」。无命中返回空串。
    static func background(for text: String) -> String {
        matched(for: text).map { "\($0.title)：\($0.content)" }.joined(separator: "\n")
    }

    // MARK: 内置笔记（内容源自狗头军师文献，与安卓内置笔记同纲）

    static func seedIfNeeded() {
        let version = 2
        let seeded = groupDefaults.integer(forKey: seedVersionKey)
        guard seeded < version else { return }
        let now = Date().timeIntervalSince1970
        let notes = builtinNotes(now: now)
        saveNotes(notes)
        groupDefaults.set(version, forKey: seedVersionKey)
        privateDefaults.set(version, forKey: seedVersionKey)
    }

    private static func builtinNotes(now: TimeInterval) -> [JevNote] {
        func n(_ i: Int, _ id: String, _ title: String, _ tags: [String],
               _ content: String, alwaysOn: Bool = false) -> JevNote {
            JevNote(id: id, title: title, content: content, tags: tags,
                    alwaysOn: alwaysOn, enabled: true, builtin: true,
                    updatedAt: now + Double(i))
        }
        return [
            n(0, "builtin.core", "关系总纲", [],
              "亲密的核心是回应性：理解对方处境、确认对方感受有道理、传达关心，而不是知道对方所有秘密。健康关系看三点：回应（情绪被接住）、尊重（边界与差异被当回事）、可靠（承诺能兑现）。先处理心情，再处理事情。",
              alwaysOn: true),
            n(1, "builtin.attachment", "依恋与情绪调节",
              ["想你", "粘人", "不回消息", "安全感", "依赖", "焦虑", "冷淡", "没回"],
              "依恋有两个连续维度：焦虑（怕被抛弃、过度求保证）与回避（怕太亲密、压力下疏远）。焦虑遇回避容易形成追—逃循环：一方追问、一方沉默。破解：焦虑方先自我安抚，把“你为什么不回我”换成“看到消息回我一下就好”；回避方主动给简短回应。安全感来自可预期的回应，不来自保证。"),
            n(2, "builtin.conflict", "沟通冲突与修复",
              ["吵架", "生气", "冲突", "冷战", "道歉", "哄", "对不起", "误会", "计较"],
              "冲突先分类：信息误解（澄清事实即可）、可解决问题（一起定方案）、持续差异（管理而非消灭）、核心不兼容（认真考虑关系）。修复三步：先共情（“我知道你觉得委屈”）、再对事不对人地说感受和需求、最后给一个具体的小约定。可以生气，不攻击人格、不翻旧账。"),
            n(3, "builtin.manipulation", "识别操控与伦理边界",
              ["pua", "打压", "忽冷忽热", "控制", "画饼", "贬低", "拿捏", "推拉"],
              "操控信号：忽冷忽热（间歇强化制造追逐）、贬低式赞美（“你这么胖也就我要你”，先打压自尊）、服从性测试（小要求逐步升级）、煤气灯（否认事实让你怀疑自己）、孤立（切断你的朋友家人）。健康的影响让人更自信，操控让人更自我怀疑。遇到操控不解释、不辩论，拉开距离。"),
            n(4, "builtin.attraction", "吸引与关系启动",
              ["喜欢", "约会", "暧昧", "心动", "追", "追求", "表白", "处对象"],
              "吸引来自三部分：行动者效应（你整体的状态和可接近性）、伴侣效应（对方普遍被欢迎的程度）、独特契合（你们独有的默契）。能提升的是第一项：好好生活、情绪稳定、有自己的节奏。推进关系靠具体的共同经历（邀约时间+事项），不靠反复表白和查岗式问候。对方明确拒绝就体面停止。"),
            n(5, "builtin.breakup", "分手与修复",
              ["分手", "前任", "复合", "背叛", "出轨", "离婚", "想他"],
              "分手是关系决定，不是法庭判决：核心不兼容、长期不被满足、信任耗尽，任何一个都可以是充分理由，不需要对方同意。刚分手的想念多是习惯和丧失感，不代表应该复合。想复合先看两点：当初分开的问题是否真解决、对方是否有复合意愿，缺一不可。停止视奸，先把生活撑起来。"),
            n(6, "builtin.praise", "夸人的方法",
              ["夸", "表扬", "厉害", "好看", "优秀", "棒"],
              "夸奖的本质是精准看见，不是客套。三原则：真诚（只夸真正认同的点）、具体（把“你真棒”换成“你刚才那句话说得特别得体”）、间接（夸细节、努力、影响比夸天赋更让人信）。对长辈夸健康和子女，对伴侣夸用心，对同事夸配合。"),
            n(7, "builtin.emotional", "情绪价值回应",
              ["累", "难过", "委屈", "焦虑", "烦", "压力", "好累", "心情"],
              "情绪价值是情感共鸣，不是讨好。对方倾诉时先接住情绪（“听起来今天真够呛”）、再听细节、最后问“想吐槽还是想要主意”。四不要：不急着讲道理、不无原则附和（对方骂老板你跟着骂可能火上浇油）、不抢话题讲自己、不轻视（“这点事至于吗”）。"),
            n(8, "builtin.initiative", "聊天主动权",
              ["聊", "没话", "尬聊", "冷场", "主动", "话题", "怎么回"],
              "被动不是没话说，是没找到切入点。主动三原则：先接话再延伸（对方说宅家，先“宅家确实舒服”再问“在家都看点啥”）；开放式提问代替封闭式（“吃了吗”换成“今天有啥好吃的”）；分享自己一点小事再抛问题。聊天是双人舞，带节奏但不抢拍。"),
            n(9, "builtin.argument", "吵架技巧",
              ["吵", "骂", "争论", "怼", "不服", "抬杠", "说难听"],
              "吵架的目标是共同解决，不是赢。避坑：人身攻击、翻旧账、威胁分手、翻脸走人、半夜追问。步骤：先降温（“我不是想跟你吵，是想把事说开”）、说事实而不是评判、说感受和需求、给台阶也接台阶。吵完主动递一个修复信号。"),
            n(10, "builtin.refuse", "拒绝与边界",
              ["拒绝", "不好意思", "边界", "借钱", "帮忙", "答应"],
              "高情商拒绝是体面护住边界。结构：直接说清结论（“这周去不了”）+简短真实理由（“已经答应家里了”）+可选替代方案。不过度解释、不反复道歉、不先答应再拖延。好的关系经得起拒绝；需要不断委屈自己才能维持的关系，本来就不牢靠。"),
            n(11, "builtin.safety", "安全底线",
              ["威胁", "暴力", "报警", "安全", "打人", "跟踪", "自杀"],
              "暴力、胁迫、跟踪、骚扰、自伤威胁都是安全事件，不是感情问题，不要独自硬扛。保留证据（截图、录音、伤情照片），向信任的家人朋友求助，必要时拨110或12338妇女维权热线。对方以自杀相威胁时不要独自承担，通知其家人或报警，你没有义务用自己的安全去安抚。"),
        ]
    }
}
