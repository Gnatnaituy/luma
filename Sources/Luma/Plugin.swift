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
    case calendar
    case quicklinks
    case snippets
    case windows

    var id: String { rawValue }

    var descriptor: PluginDescriptor {
        CommandCatalog.descriptor(for: self)
    }

    var title: String { descriptor.title }
    var subtitle: String { descriptor.subtitle }
    var symbol: String { descriptor.symbol }
    var tint: Color { descriptor.tint }
    var keywords: [String] { descriptor.keywords }

    func matches(_ query: String, keywords configuredKeywords: [String]? = nil) -> Bool {
        let value = query.lowercased()
        let searchableKeywords = configuredKeywords ?? keywords
        return title.lowercased().contains(value)
            || searchableKeywords.contains(where: { $0.lowercased().contains(value) })
    }
}

enum CommandCatalog {
    static func descriptor(for plugin: Plugin) -> PluginDescriptor {
        switch plugin {
        case .clipboard: .init("剪贴板", "文本、图片、文件与链接历史", "clipboard", .indigo, ["clipboard", "copy", "粘贴", "复制", "剪贴板"])
        case .calculator: .init("计算器", "安全解析数学表达式", "function", .purple, ["calc", "calculator", "计算", "公式", "数学"])
        case .json: .init("JSON 编辑器", "语法高亮、格式化与校验 JSON", "curlybraces.square", .gray, ["json", "format", "格式化", "压缩", "校验"])
        case .password: .init("随机密码", "使用系统安全随机数生成密码", "lock.shield", .blue, ["password", "passwd", "密码", "随机"])
        case .translate: .init("翻译", "支持 Apple 系统翻译与自定义 AI 模型", "character.book.closed", .teal, ["translate", "fy", "翻译", "中英"])
        case .code: .init("编码小助手", "Base64、URL 编码与 SHA-256", "chevron.left.forwardslash.chevron.right", .cyan, ["base64", "url", "sha256", "encode", "decode", "编码", "解码"])
        case .stocks: .init("股票盯盘", "按代码查询公网延迟行情", "chart.xyaxis.line", .orange, ["stock", "股票", "盯盘", "行情"])
        case .weather: .init("天气", "添加地点并查看逐小时与七日预报", "cloud.sun.fill", .blue, ["weather", "天气", "气温", "预报", "城市"])
        case .calendar: .init("日历", "查看公历、农历、节气与节假日", "calendar", .red, ["calendar", "date", "lunar", "holiday", "festival", "solar", "solar term", "农历", "节气", "节假日", "日历", "星期"])
        case .quicklinks: .init("Quicklinks", "用关键词打开网页、文件与自定义搜索", "link.badge.plus", .mint, ["quicklink", "link", "网页", "网址", "搜索"])
        case .snippets: .init("片段", "保存并快速粘贴常用文本", "text.quote", .pink, ["snippet", "片段", "短语", "模板", "粘贴"])
        case .windows: .init("窗口管理", "在当前屏幕排列与移动窗口", "macwindow.on.rectangle", .indigo, ["window", "窗口", "分屏", "布局"])
        }
    }
}

struct PluginDescriptor {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let keywords: [String]

    init(_ title: String, _ subtitle: String, _ symbol: String, _ tint: Color, _ keywords: [String]) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.keywords = keywords
    }
}
