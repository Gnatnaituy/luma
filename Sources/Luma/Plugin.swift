import SwiftUI

enum Plugin: String, CaseIterable, Identifiable {
    case clipboard
    case calculator
    case json
    case password
    case translate
    case code
    case stocks
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: "剪贴板"
        case .calculator: "计算器"
        case .json: "JSON 编辑器"
        case .password: "随机密码"
        case .translate: "翻译"
        case .code: "编码小助手"
        case .stocks: "股票盯盘"
        case .weather: "天气"
        }
    }

    var subtitle: String {
        switch self {
        case .clipboard: "文本、图片、文件与链接历史"
        case .calculator: "安全解析数学表达式"
        case .json: "语法高亮、格式化与校验 JSON"
        case .password: "使用系统安全随机数生成密码"
        case .translate: "支持 Apple 系统翻译与自定义 AI 模型"
        case .code: "Base64、URL 编码与 SHA-256"
        case .stocks: "按代码查询公网延迟行情"
        case .weather: "添加地点并查看逐小时与七日预报"
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: "clipboard"
        case .calculator: "function"
        case .json: "curlybraces.square"
        case .password: "lock.shield"
        case .translate: "character.book.closed"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .stocks: "chart.xyaxis.line"
        case .weather: "cloud.sun.fill"
        }
    }

    var tint: Color {
        switch self {
        case .clipboard: .indigo
        case .calculator: .purple
        case .json: .gray
        case .password: .blue
        case .translate: .teal
        case .code: .cyan
        case .stocks: .orange
        case .weather: .blue
        }
    }

    var keywords: [String] {
        switch self {
        case .clipboard: ["clipboard", "copy", "粘贴", "复制", "剪贴板"]
        case .calculator: ["calc", "calculator", "计算", "公式", "数学"]
        case .json: ["json", "format", "格式化", "压缩", "校验"]
        case .password: ["password", "passwd", "密码", "随机"]
        case .translate: ["translate", "fy", "翻译", "中英"]
        case .code: ["base64", "url", "sha256", "encode", "decode", "编码", "解码"]
        case .stocks: ["stock", "股票", "盯盘", "行情"]
        case .weather: ["weather", "天气", "气温", "预报", "城市"]
        }
    }

    func matches(_ query: String, keywords configuredKeywords: [String]? = nil) -> Bool {
        let value = query.lowercased()
        let searchableKeywords = configuredKeywords ?? keywords
        return title.lowercased().contains(value)
            || searchableKeywords.contains(where: { $0.lowercased().contains(value) })
    }
}
