import Foundation

// MARK: - 恋爱大师（Love Coach）
//
// 在「狗头军师」总纲下，专门管恋爱关系：先判阶段，再做四维体检，然后定本轮唯一动作、给可发话术。
// 方法蒸馏自开源「恋爱大师 / qingsheng-skill」（github.com/tomwong001/qingsheng-skill，MIT），
// 与安卓融合版 assets/skills/lianaidashi_core.md 同口径。
// 注意：它只提供「方法与判断」，不替用户做决定、不产出操控话术。

enum LoveCoach {
    /// 字符预算：和 GoutouKnowledge 共用 prompt 空间，控制在 1200 以内。
    private static let budgetChars = 1200

    /// 关系七阶段
    private static let stages: [String] = [
        "陌生", "认识", "暧昧", "升温", "确立", "矛盾", "冷淡",
    ]

    /// 四维体检
    private static let dimensions: String = """
    主动度（谁先开口、谁约谁）、投入度（回得快不快、用不用心）、边界感（是否尊重拒绝与节奏）、\
    言行一致性（说的和做的是否对得上）
    """

    /// 常驻核心方法
    static let framework: String = """
    【恋爱大师·方法】①先判当前关系阶段（\(stages.joined(separator: "/"))）；\
    ②四维体检：\(dimensions)；③据此定本轮唯一动作（推进/接住/澄清/后撤/拒绝），再给可直接发的一句话。\
    原则：不讨好、不查岗、不操控、不施压、不写小作文、不发长段表白；对方没问就不解释；\
    拿不准先轻松接住，绝不越级推进（没到暧昧不暧昧、没确立不越界）。
    """

    /// 阶段路由：命中关键词 → 该阶段的具体打法
    private static let routes: [(keys: [String], guide: String)] = [
        (["在吗", "你好", "认识", "加个", "自我介绍", "哪位"],
         "陌生/认识阶段：先轻松开场或回应，别急着暧昧、别查户口；一次只问一个轻松的问题。"),
        (["哈哈", "嘻嘻", "晚安", "早安", "想你", "约吗", "出来玩", "吃饭", "看电影", "抱抱"],
         "暧昧阶段：可以给一点情绪甜头但留分寸，推拉一次即可；不约第二次、不逼对方表态。"),
        (["男朋友", "女朋友", "对象", "在一起", "官宣", "恋爱", "纪念日"],
         "确立阶段：自然亲近、给确定性；不端着也不控制，有需求直接说不绕弯。"),
        (["生气", "吵架", "分手", "不理我", "冷战", "误会", "对不起", "错了", "敷衍"],
         "矛盾阶段：先接住情绪、就事论事，不翻旧账、不逼对方立刻原谅；该道歉就具体道歉，再给一个台阶。"),
        (["忙", "改天", "再说", "呵呵", "随便", "嗯", "哦", "回得慢", "冷淡"],
         "冷淡阶段：别连环追问、别自我贬低；把球轻轻递过去，对方不接就后撤过好自己，不卑微。"),
        (["拒绝", "不合适", "没感觉", "别联系", "拉黑", "算了"],
         "边界/拒绝：体面接受、不纠缠不质问，留一句大方的话收尾，尊重对方也是尊重自己。"),
    ]

    /// 生成恋爱大师方法块。命中阶段关键词时追加该阶段打法；否则只给核心框架。
    static func snippet(for message: String, context: String?) -> String {
        let haystack = "\(context ?? "")\n\(message)".lowercased()
        var guide = ""
        for route in routes where route.keys.contains(where: { haystack.contains($0.lowercased()) }) {
            guide = route.guide
            break
        }
        var out = framework
        if !guide.isEmpty { out += "\n" + guide }
        return out.count <= budgetChars ? out : String(out.prefix(budgetChars))
    }
}
