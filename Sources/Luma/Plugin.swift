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
        case .clipboard: .init(L10n.text("剪贴板", "Clipboard"), L10n.text("文本、图片、文件与链接历史", "Text, image, file, and link history"), "clipboard", .indigo, ["clipboard", "copy", "粘贴", "复制", "剪贴板"])
        case .calculator: .init(L10n.text("计算器", "Calculator"), L10n.text("安全解析数学表达式", "Safely evaluate mathematical expressions"), "function", .purple, ["calc", "calculator", "计算", "公式", "数学"])
        case .json: .init(L10n.text("JSON 编辑器", "JSON Editor"), L10n.text("语法高亮、格式化与校验 JSON", "Highlight, format, and validate JSON"), "curlybraces.square", .gray, ["json", "format", "格式化", "压缩", "校验"])
        case .password: .init(L10n.text("随机密码", "Password Generator"), L10n.text("使用系统安全随机数生成密码", "Generate passwords with secure system randomness"), "lock.shield", .blue, ["password", "passwd", "密码", "随机"])
        case .translate: .init(L10n.text("翻译", "Translate"), L10n.text("支持 Apple 系统翻译与自定义 AI 模型", "Use Apple Translation or a custom AI model"), "character.book.closed", .teal, ["translate", "fy", "翻译", "中英"])
        case .code: .init(L10n.text("编码小助手", "Encoding Tools"), L10n.text("Base64、URL 编码与 SHA-256", "Base64, URL encoding, and SHA-256"), "chevron.left.forwardslash.chevron.right", .cyan, ["base64", "url", "sha256", "encode", "decode", "编码", "解码"])
        case .stocks: .init(L10n.text("股票盯盘", "Stocks"), L10n.text("按代码查询公网延迟行情", "Look up delayed market quotes by symbol"), "chart.xyaxis.line", .orange, ["stock", "股票", "盯盘", "行情"])
        case .weather: .init(L10n.text("天气", "Weather"), L10n.text("添加地点并查看逐小时与七日预报", "Add locations and view hourly and 7-day forecasts"), "cloud.sun.fill", .blue, ["weather", "天气", "气温", "预报", "城市"])
        case .calendar: .init(L10n.text("日历", "Calendar"), L10n.text("查看公历、农历、节气与节假日", "View solar and lunar dates, solar terms, and holidays"), "calendar", .red, ["calendar", "date", "lunar", "holiday", "festival", "solar", "solar term", "农历", "节气", "节假日", "日历", "星期"])
        case .windows: .init(L10n.text("窗口管理", "Window Management"), L10n.text("在当前屏幕排列与移动窗口", "Arrange and move windows on the current display"), "macwindow.on.rectangle", .indigo, ["window", "窗口", "分屏", "布局"])
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
