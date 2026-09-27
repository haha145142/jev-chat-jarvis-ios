import Foundation

// MARK: - 生成层：OpenAI / Anthropic 兼容起草客户端
//
// 一个话术一次请求（两话术合在一个 prompt 里会互相渗味，macOS 版实测结论）。
// 两种 API 形状：绝大多数端点（DeepSeek/智谱/通义/Moonshot/硅基/OpenRouter/Ollama）
// 只有 OpenAI 形状；智谱和少数网关两种都有。

final class JevDraft {
    private let cfg: JevConfig

    /// 采样温度。对齐 macOS 版 `src/generate.py` 的 0.9：部分渠道把范围夹在 [0,1]，
    /// 发 1.2 会被上游直接拒（400 temperature参数非法）。
    private static let temperature: Double = 0.9

    init(cfg: JevConfig) {
        self.cfg = cfg
    }

    var isConfigured: Bool {
        let g = cfg.generation
        return !g.key.isEmpty && !g.base.isEmpty && !g.model.isEmpty
    }

    // MARK: URL 拼接
    //
    // base 带不带末尾 /chat/completions、/v1、/v4 都能拼对：
    //   https://api.deepseek.com                -> /chat/completions
    //   https://api.deepseek.com/v1             -> /v1/chat/completions
    //   https://open.bigmodel.cn/api/paas/v4    -> /api/paas/v4/chat/completions
    // Anthropic 形状对版本段单独处理（…/api/anthropic -> /v1/messages）。

    static func chatURL(_ rawBase: String, kind: APIKind) -> String {
        let b = rawBase.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        let segs = b.split(separator: "/").map(String.init)
        guard let last = segs.last?.lowercased() else { return b }
        switch kind {
        case .openai:
            if last == "completions" { return b }
            return b + "/chat/completions"
        case .anthropic:
            if last == "messages" { return b }
            if last.range(of: #"^v\d+$"#, options: .regularExpression) != nil { return b + "/messages" }
            return b + "/v1/messages"
        }
    }

    // MARK: 起草

    /// 一次调用返回 2 条候选（前稳后放）。judgeGuide=判断层给的意图/动作/风险参考。
    func draft(message: String, judgeGuide: String = "", context: String?,
               knowledge: String = "",
               tone: String, instruction: String) async throws -> [String] {
        let system = Self.systemPrompt(tone: tone, instruction: instruction)
        let user = Self.userPrompt(message: message, judgeGuide: judgeGuide,
                                   context: context, knowledge: knowledge)
        let raw = try await call(system: system, user: user)
        let lines = Self.parseCandidates(raw)
        if lines.isEmpty { throw JevError.emptyReply }
        return lines
    }

    /// 系统提示：人设 + 官方军师规则 + JSON 数组输出约束（对齐 GoutouGuidance.draftRules）。
    private static func systemPrompt(tone: String, instruction: String) -> String {
        """
        你是狗头军师 Jev Chat 的即时通讯回复助手。
        当前话术人设：「\(tone)」\(instruction)
        狗头军师规则：
        - 先区分可见事实、暂定推测与仍未知；一轮回复只做一个主动作
        - 对方意图只是可能的解释，别在回复里宣称看穿了 TA
        - 尊重拒绝与边界，不使用操控、施压、贬低或虚假时间限制
        - 不编造见面时间、共同经历、自己做过的事或做不到的承诺
        - 回复像用户平时发的一句话；不把分析术语、理由、代价塞进可发送文本
        只输出一个 JSON 数组，包含 \(PER_TONE) 条候选：前一条稳妥周全可直接发，后一条更直接或更轻松；每条不超过 40 字，口语自然。不要解释，不要输出数组以外的任何内容。
        """
    }

    /// 用户消息：知识依据 + 判断参考 + 最近对话 + 待回消息。
    private static func userPrompt(message: String, judgeGuide: String,
                                   context: String?, knowledge: String) -> String {
        var p = ""
        if !knowledge.isEmpty {
            p += "以下关系原则与方法是回复依据：回复必须与之一致，可直接化用其中的事实与做法；不要编造这里没有的东西，也不要照抄或提及资料本身。\n\(knowledge)\n\n"
        }
        if !judgeGuide.isEmpty { p += judgeGuide + "\n" }
        if let c = context, !c.isEmpty { p += "最近的对话：\n\(c)\n\n" }
        p += "消息：「\(message)」\n请给出 \(PER_TONE) 条候选回复的 JSON 数组。"
        return p
    }

    /// 解析候选：优先 JSON 数组，失败再按行解析（对齐官方 parseThree）。
    static func parseCandidates(_ raw: String) -> [String] {
        if let lb = raw.range(of: "["),
           let rb = raw.range(of: "]", range: lb.upperBound..<raw.endIndex) {
            let piece = String(raw[lb.lowerBound...rb.upperBound])
            if let data = piece.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                let texts = arr.compactMap { $0 as? String }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !texts.isEmpty { return Array(texts.prefix(PER_TONE)) }
            }
        }
        return CandidateParser.parse(raw)
    }

    /// 连通性测试用：单轮对话。
    func call(prompt: String) async throws -> String {
        try await call(system: "你是连通性测试助手，只按要求回答，不要解释。", user: prompt)
    }

    func call(system: String, user: String) async throws -> String {
        let g = cfg.generation
        let url = Self.chatURL(g.base, kind: g.kind)
        var body: [String: Any]
        var headers = ["Content-Type": "application/json"]
        switch g.kind {
        case .openai:
            body = [
                "model": g.model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
                "max_tokens": 500,
                "temperature": 0.8,
                "stream": false,
            ]
            headers["Authorization"] = "Bearer \(g.key)"
        case .anthropic:
            body = [
                "model": g.model,
                "system": system,
                "max_tokens": 500,
                "temperature": 0.8,
                "messages": [["role": "user", "content": user]],
            ]
            headers["x-api-key"] = g.key
            headers["anthropic-version"] = "2023-06-01"
        }
        // 额外字段（关思考模式等）。非法 JSON 直接忽略——不该让一个可选配置打断整条链路。
        let extra = g.extraJSON.trimmingCharacters(in: .whitespaces)
        if !extra.isEmpty, let data = extra.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj { body[k] = v }
        }
        let data = try await JevHTTP.postJSON(body, url: url, headers: headers,
                                              budget: 35, stage: "生成")
        return try Self.extractText(data, kind: g.kind, model: g.model)
    }

    /// 两种响应形状的正文抽取 + 「思考型模型吃光额度」识别。
    static func extractText(_ data: [String: Any], kind: APIKind, model: String) throws -> String {
        switch kind {
        case .openai:
            let choices = data["choices"] as? [[String: Any]] ?? []
            let msg = choices.first?["message"] as? [String: Any] ?? [:]
            if let text = msg["content"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return text
            }
            let reasoning = (msg["reasoning_content"] ?? msg["reasoning"]) as? String
            if let r = reasoning, !r.isEmpty {
                throw JevError.thinkingOnly(
                    "「\(model)」是思考型模型：思考占满了额度，正文 0 条；请换非思考模型（如 deepseek-chat、glm-4-flash）")
            }
            throw JevError.emptyReply
        case .anthropic:
            let content = data["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text }
            throw JevError.emptyReply
        }
    }
}
