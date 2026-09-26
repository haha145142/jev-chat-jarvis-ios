import Foundation

// MARK: - 狗头军师知识库：随包资源 + 关键词路由 + 字符预算
//
// 融合自开源项目 shengjidaguai-china/goutoujunshi（MIT）：43 篇关系心理学 / 实战话术文献。
// 每次分析按消息关键词挑 1-2 篇，截断到固定预算后注入起草 prompt——
// 键盘扩展内存 <60MB、请求有 token 成本，所以不整库加载。

enum GoutouKnowledge {

    /// 每次分析附带知识的总字符预算（含核心原则）。
    static let budgetChars = 2800

    /// 核心原则（每次都带，刻意压到很短）。
    static let corePrinciples = """
    你是我的狗头军师：先接住情绪，再分清事实，最后给能执行的选择。说人话、有立场，不卑微讨好、不说教、不写小作文；不把沉默当同意，不把客气当喜欢，不凭单个表情定性。
    """

    /// 路由规则：命中任一关键词（消息或上下文，小写匹配）就选对应文件，按顺序短路。
    /// 路径相对 GoutouKnowledge 资源目录。
    private static let routes: [(keywords: [String], files: [String])] = [
        (["家暴", "跟踪", "威胁", "胁迫", "诈骗", "杀猪盘", "骗钱", "报警", "勒索"],
         ["knowledge/17-中国法律安全与危机转介.md", "knowledge/09-在线约会与数字关系.md"]),
        (["分手", "复合", "背叛", "出轨", "前任", "失恋"],
         ["knowledge/15-分手背叛与关系修复.md"]),
        (["离婚", "结婚", "彩礼", "婆婆", "家务", "育儿", "夫妻", "婚姻", "双方父母"],
         ["knowledge/11-婚姻家庭与生命周期.md", "knowledge/12-金钱家务育儿与双方家庭.md"]),
        (["同性", "多元", "性取向", "双性恋", "跨性别", "开放关系", "多偶"],
         ["knowledge/16-多元关系与反刻板印象.md"]),
        (["上床", "亲密", "同意", "性边界"],
         ["knowledge/08-同意边界性与亲密.md"]),
        (["pua", "套路", "冷读", "推拉", "操控", "煤气灯", "服从测试", "mystery", "blueprint", "蓝图"],
         ["knowledge/05-PUA操控与伦理替代.md", "knowledge/20-经典社交体系的机制、证据与风险边界.md"]),
        (["mbti", "依恋", "焦虑型", "回避型", "没安全感", "人格"],
         ["knowledge/04-MBTI人格与匹配.md", "knowledge/03-依恋理论与情绪调节.md"]),
        (["吵架", "争吵", "冲突", "生气", "冷战", "道歉", "矛盾", "发火", "闹脾气"],
         ["knowledge/07-沟通冲突与修复.md", "practical/万能吵架技巧：理性冲突处理指南.md"]),
        (["邀约", "约她", "约他", "见面", "第一次见", "约会", "表白", "推进关系"],
         ["knowledge/06-吸引约会与关系启动.md", "practical/主动表达、第一次见面与自然接触.md"]),
        (["冷淡", "不主动", "不回", "失衡", "投入", "敷衍", "降级"],
         ["practical/关系投入失衡：互惠判断、降级投入与退出决策.md"]),
        (["拒绝", "不想去", "怎么拒"],
         ["practical/高情商拒绝他人：体面护边界的实用指南.md"]),
        (["尴尬", "冷场", "救场", "接话", "没话聊", "怎么接"],
         ["practical/巧妙接话技巧：让沟通更流畅的实用指南.md", "practical/化解尴尬：轻松救场的实用指南.md"]),
        (["夸", "赞美", "哄", "累", "委屈", "难受", "心情", "情绪价值"],
         ["practical/为他人提供情绪价值：温暖且有效的回应指南.md", "practical/万能夸人的话术技巧：真诚认可的实用指南.md"]),
        (["开场白", "怎么聊", "开场", "怎么回", "话术"],
         ["practical/实战话术编排器：从一句回复到后续分支.md"]),
    ]

    private static let defaultFiles = [
        "knowledge/02-亲密关系心理学总论.md",
        "practical/实战话术编排器：从一句回复到后续分支.md",
    ]

    /// 主入口：返回注入 prompt 的知识文本；资源缺失时只给核心原则。
    static func snippet(for message: String, context: String?) -> String {
        let haystack = (message + " " + (context ?? "")).lowercased()
        var files = defaultFiles
        for route in routes {
            if route.keywords.contains(where: { haystack.contains($0.lowercased()) }) {
                files = route.files
                break
            }
        }

        var body = ""
        let remaining = budgetChars - corePrinciples.count - 40
        let perFile = max(400, remaining / max(files.count, 1))
        for rel in files {
            guard let text = load(rel) else { continue }
            let cleaned = clean(text)
            let piece = truncate(cleaned, limit: perFile)
            let title = (rel.split(separator: "/").last.map(String.init) ?? rel)
                .replacingOccurrences(of: ".md", with: "")
            body += "【\(title)】\n\(piece)\n\n"
            if body.count >= remaining { break }
        }

        var out = "（狗头军师知识，仅作回复依据，不要在回复里提及）\n"
        out += corePrinciples + "\n\n"
        out += body
        return out
    }

    // MARK: 资源定位（App 主包 / 键盘扩展包都可能是宿主）

    private static var folderURL: URL? {
        var bundles: [Bundle] = [Bundle.main]
        bundles += Bundle.allBundles.filter { $0.bundlePath.contains(".appex") }
        for b in bundles {
            if let url = b.url(forResource: "GoutouKnowledge", withExtension: nil),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func load(_ relative: String) -> String? {
        guard let folder = folderURL else { return nil }
        let url = folder.appendingPathComponent(relative)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: 文本处理

    /// 去掉 Markdown 噪声：HTML 注释、图片、链接外壳、多余空行、引用符号。
    private static func clean(_ raw: String) -> String {
        var t = raw
        t = t.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^>+\s*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 按字符数截断，尽量落在句号/换行上。
    private static func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let cut = text.prefix(limit)
        if let r = cut.lastIndex(where: { $0 == "。" || $0 == "\n" || $0 == "；" }) {
            return String(cut[..<r]) + "…"
        }
        return String(cut) + "…"
    }
}
