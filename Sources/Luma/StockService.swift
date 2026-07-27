import Combine
import CoreFoundation
import Foundation

struct StockSymbol: Equatable {
    let canonical: String
    let providerCode: String
    let marketName: String
    let currency: String
}

enum StockSymbolError: LocalizedError, Equatable {
    case empty
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .empty: "请输入股票代码"
        case .unsupported(let value): "无法识别“\(value)”，示例：AAPL、600115.SS、002594.SZ、0700.HK"
        }
    }
}

enum StockSymbolParser {
    static func parse(_ input: String) throws -> StockSymbol {
        let value = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !value.isEmpty else { throw StockSymbolError.empty }

        let parts = value.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].allSatisfy(\.isNumber) {
            let code = parts[0]
            switch parts[1] {
            case "SS", "SH":
                guard code.count == 6 else { throw StockSymbolError.unsupported(value) }
                return StockSymbol(canonical: "\(code).SS", providerCode: "sh\(code)", marketName: "上海", currency: "CNY")
            case "SZ":
                guard code.count == 6 else { throw StockSymbolError.unsupported(value) }
                return StockSymbol(canonical: "\(code).SZ", providerCode: "sz\(code)", marketName: "深圳", currency: "CNY")
            case "HK":
                guard (1...5).contains(code.count) else { throw StockSymbolError.unsupported(value) }
                let padded = String(repeating: "0", count: 5 - code.count) + code
                return StockSymbol(canonical: "\(padded).HK", providerCode: "hk\(padded)", marketName: "香港", currency: "HKD")
            default:
                throw StockSymbolError.unsupported(value)
            }
        }

        if value.count == 6, value.allSatisfy(\.isNumber) {
            let isShanghai = value.hasPrefix("5") || value.hasPrefix("6") || value.hasPrefix("9")
            let suffix = isShanghai ? "SS" : "SZ"
            let prefix = isShanghai ? "sh" : "sz"
            let market = isShanghai ? "上海" : "深圳"
            return StockSymbol(canonical: "\(value).\(suffix)", providerCode: "\(prefix)\(value)", marketName: market, currency: "CNY")
        }

        let usPattern = try! NSRegularExpression(pattern: #"^[A-Z][A-Z0-9.-]{0,11}(?:\.US)?$"#)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if usPattern.firstMatch(in: value, range: range) != nil {
            let symbol = value.hasSuffix(".US") ? String(value.dropLast(3)) : value
            return StockSymbol(canonical: symbol, providerCode: "us\(symbol)", marketName: "美国", currency: "USD")
        }

        throw StockSymbolError.unsupported(value)
    }
}

struct StockPoint: Codable, Equatable, Identifiable {
    let date: String
    let close: Double
    let open: Double?
    let high: Double?
    let low: Double?
    let volume: Double?

    init(
        date: String,
        close: Double,
        open: Double? = nil,
        high: Double? = nil,
        low: Double? = nil,
        volume: Double? = nil
    ) {
        self.date = date
        self.close = close
        self.open = open
        self.high = high
        self.low = low
        self.volume = volume
    }

    var id: String { date }
    var hasOHLC: Bool { open != nil && high != nil && low != nil }
}

struct StockSnapshot: Codable, Equatable, Identifiable {
    let symbol: String
    let providerCode: String
    let name: String
    let marketName: String
    let currency: String
    let price: Double
    let change: Double
    let changePercent: Double
    let previousClose: Double
    let open: Double
    let high: Double
    let low: Double
    let volume: Double
    let quoteTime: String
    let points: [StockPoint]
    let fetchedAt: Date
    var totalMarketValue: Double? = nil
    var circulatingMarketValue: Double? = nil
    var priceEarningsRatio: Double? = nil
    var industry: String? = nil

    var id: String { symbol }
    var isRising: Bool { change >= 0 }
    var amplitudePercent: Double {
        guard previousClose != 0 else { return 0 }
        return (high - low) / previousClose * 100
    }
    var openChangePercent: Double {
        guard previousClose != 0 else { return 0 }
        return (open - previousClose) / previousClose * 100
    }
    var dayPosition: Double? {
        guard high > low else { return nil }
        return min(max((price - low) / (high - low), 0), 1)
    }
    var periodHigh: Double? { points.map(\.close).max() }
    var periodLow: Double? { points.map(\.close).min() }
    var periodChangePercent: Double? {
        guard let first = points.first?.close, first != 0, let last = points.last?.close else { return nil }
        return (last - first) / first * 100
    }
}

struct StockFundamentals: Equatable {
    let totalMarketValue: Double?
    let circulatingMarketValue: Double?
    let priceEarningsRatio: Double?
    let industry: String?
}

enum StockColorTheme: String, CaseIterable, Codable, Identifiable {
    case greenUpRedDown
    case redUpGreenDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .greenUpRedDown: "绿涨红跌"
        case .redUpGreenDown: "红涨绿跌"
        }
    }
}

enum StockDataSource: String, CaseIterable, Codable, Identifiable {
    case automatic
    case tencent
    case eastMoney
    case sina

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .tencent: "腾讯财经"
        case .eastMoney: "东方财富"
        case .sina: "新浪财经"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: "按腾讯、东方财富、新浪顺序自动切换故障数据源"
        case .tencent: "免密钥，支持 A 股、港股、美股与近 30 日走势"
        case .eastMoney: "免密钥，支持 A 股、港股、美股；走势数据尽力获取"
        case .sina: "免密钥，支持 A 股、港股、美股实时报价"
        }
    }
}

enum StockServiceError: LocalizedError {
    case invalidResponse
    case provider(String)
    case symbolNotFound
    case malformedData

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "行情服务响应异常"
        case .provider(let message): "行情服务错误：\(message)"
        case .symbolNotFound: "未找到该股票代码"
        case .malformedData: "行情数据格式无法解析"
        }
    }
}

struct StockSearchResult: Equatable, Identifiable {
    let symbol: String
    let name: String
    let market: String

    var id: String { symbol }
}

struct EastMoneyStockSearchService {
    func search(_ query: String, count: Int = 8) async throws -> [StockSearchResult] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        var components = URLComponents(string: "https://searchapi.eastmoney.com/api/suggest/get")!
        components.queryItems = [
            URLQueryItem(name: "input", value: value),
            URLQueryItem(name: "type", value: "14"),
            URLQueryItem(name: "count", value: String(min(max(count, 1), 20)))
        ]
        guard let url = components.url else { throw StockServiceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StockServiceError.invalidResponse
        }
        return try Self.parse(data: data)
    }

    static func parse(data: Data) throws -> [StockSearchResult] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        return (response.table.data ?? []).compactMap { item in
            let symbol: String
            let market: String
            switch item.classify {
            case "AStock":
                symbol = item.quoteID.hasPrefix("1.") ? "\(item.code).SS" : "\(item.code).SZ"
                market = item.securityTypeName ?? (item.quoteID.hasPrefix("1.") ? "沪A" : "深A")
            case "HK":
                symbol = "\(item.code).HK"
                market = item.securityTypeName ?? "港股"
            case "UsStock":
                symbol = item.code.uppercased()
                market = item.securityTypeName ?? "美股"
            default:
                return nil
            }
            guard (try? StockSymbolParser.parse(symbol)) != nil, seen.insert(symbol).inserted else { return nil }
            return StockSearchResult(symbol: symbol, name: item.name, market: market)
        }
    }

    private struct Response: Decodable {
        let table: Table

        private enum CodingKeys: String, CodingKey {
            case table = "QuotationCodeTable"
        }
    }

    private struct Table: Decodable {
        let data: [Item]?

        private enum CodingKeys: String, CodingKey {
            case data = "Data"
        }
    }

    private struct Item: Decodable {
        let code: String
        let name: String
        let classify: String
        let quoteID: String
        let securityTypeName: String?

        private enum CodingKeys: String, CodingKey {
            case code = "Code"
            case name = "Name"
            case classify = "Classify"
            case quoteID = "QuoteID"
            case securityTypeName = "SecurityTypeName"
        }
    }
}

struct TencentStockService {
    func fetch(_ symbol: StockSymbol) async throws -> StockSnapshot {
        var components = URLComponents(string: "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get")!
        components.queryItems = [URLQueryItem(name: "param", value: "\(symbol.providerCode),day,,,30,qfq")]
        guard let url = components.url else { throw StockServiceError.invalidResponse }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StockServiceError.invalidResponse
        }
        return try Self.parse(data: data, symbol: symbol)
    }

    static func parse(data: Data, symbol: StockSymbol) throws -> StockSnapshot {
        let response = try JSONDecoder().decode(TencentResponse.self, from: data)
        guard response.code == 0 else { throw StockServiceError.provider(response.msg) }
        guard let payload = response.data[symbol.providerCode] else { throw StockServiceError.symbolNotFound }
        let quote = payload.qt
        guard quote.count > 34,
              let price = Double(quote[3]),
              let previousClose = Double(quote[4]),
              let open = Double(quote[5]),
              let high = Double(quote[33]),
              let low = Double(quote[34]) else {
            throw StockServiceError.malformedData
        }

        let shortName = quote[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let longName = quote[safe: 46]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredName = symbol.marketName == "美国" && longName?.isEmpty == false ? longName : shortName
        let name = preferredName ?? symbol.canonical
        let change = Double(quote[safe: 31] ?? "") ?? (price - previousClose)
        let percent = Double(quote[safe: 32] ?? "") ?? (previousClose == 0 ? 0 : change / previousClose * 100)
        let volume = Double(quote[safe: 6] ?? "") ?? 0
        let rows = payload.qfqday ?? payload.day ?? []
        let points = rows.compactMap { row -> StockPoint? in
            guard let close = Double(row.close) else { return nil }
            return StockPoint(date: row.date, close: close)
        }

        return StockSnapshot(
            symbol: symbol.canonical,
            providerCode: symbol.providerCode,
            name: name,
            marketName: symbol.marketName,
            currency: symbol.currency,
            price: price,
            change: change,
            changePercent: percent,
            previousClose: previousClose,
            open: open,
            high: high,
            low: low,
            volume: volume,
            quoteTime: quote[safe: 30] ?? "",
            points: points,
            fetchedAt: Date()
        )
    }

    private struct TencentResponse: Decodable {
        let code: Int
        let msg: String
        let data: [String: TencentPayload]
    }

    private struct TencentPayload: Decodable {
        let qfqday: [TencentHistoryRow]?
        let day: [TencentHistoryRow]?
        let qt: [String]

        private enum CodingKeys: String, CodingKey {
            case qfqday
            case day
            case qt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            qfqday = try container.decodeIfPresent([TencentHistoryRow].self, forKey: .qfqday)
            day = try container.decodeIfPresent([TencentHistoryRow].self, forKey: .day)
            if let direct = try? container.decode([String].self, forKey: .qt) {
                qt = direct
            } else {
                let nested = try container.decode([String: [String]].self, forKey: .qt)
                guard let quote = nested.values.first(where: { $0.count > 34 }) else {
                    throw StockServiceError.malformedData
                }
                qt = quote
            }
        }
    }

    private struct TencentHistoryRow: Decodable {
        let date: String
        let close: String

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            date = try container.decode(String.self)
            _ = try container.decode(String.self)
            close = try container.decode(String.self)
        }
    }
}

struct EastMoneyStockService {
    func fetch(_ symbol: StockSymbol) async throws -> StockSnapshot {
        for securityID in securityIDs(for: symbol) {
            if let snapshot = try await fetchQuote(symbol: symbol, securityID: securityID) {
                return snapshot
            }
        }
        throw StockServiceError.symbolNotFound
    }

    private func fetchQuote(symbol: StockSymbol, securityID: String) async throws -> StockSnapshot? {
        var components = URLComponents(string: "https://push2delay.eastmoney.com/api/qt/stock/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: securityID),
            URLQueryItem(
                name: "fields",
                value: "f43,f44,f45,f46,f47,f57,f58,f59,f60,f86,f116,f117,f127,f152,f162,f169,f170"
            )
        ]
        guard let url = components.url else { throw StockServiceError.invalidResponse }
        let data = try await request(url)
        let response = try JSONDecoder().decode(EastMoneyQuoteResponse.self, from: data)
        guard response.rc == 0 else { throw StockServiceError.invalidResponse }
        guard let quote = response.data else { return nil }
        let points = (try? await fetchPoints(securityID: securityID)) ?? []
        return Self.snapshot(quote: quote, points: points, symbol: symbol)
    }

    func fetchFundamentals(_ symbol: StockSymbol) async throws -> StockFundamentals {
        for securityID in securityIDs(for: symbol) {
            var components = URLComponents(string: "https://push2delay.eastmoney.com/api/qt/stock/get")!
            components.queryItems = [
                URLQueryItem(name: "secid", value: securityID),
                URLQueryItem(name: "fields", value: "f116,f117,f127,f152,f162")
            ]
            guard let url = components.url else { continue }
            let data = try await request(url, attempts: 1)
            let response = try JSONDecoder().decode(EastMoneyFundamentalsResponse.self, from: data)
            if response.rc == 0, let quote = response.data {
                return Self.fundamentals(
                    totalMarketValue: quote.f116?.value,
                    circulatingMarketValue: quote.f117?.value,
                    priceEarningsRatio: quote.f162?.value,
                    industry: quote.f127,
                    precision: quote.f152
                )
            }
        }
        throw StockServiceError.symbolNotFound
    }

    private func fetchPoints(securityID: String) async throws -> [StockPoint] {
        var components = URLComponents(string: "https://push2his.eastmoney.com/api/qt/stock/kline/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: securityID),
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"),
            URLQueryItem(name: "klt", value: "101"),
            URLQueryItem(name: "fqt", value: "1"),
            URLQueryItem(name: "end", value: "20500101"),
            URLQueryItem(name: "lmt", value: "30")
        ]
        guard let url = components.url else { return [] }
        let data = try await request(url, attempts: 1)
        let response = try JSONDecoder().decode(EastMoneyHistoryResponse.self, from: data)
        return response.data?.klines.compactMap { row in
            let fields = row.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > 2, let close = Double(fields[2]) else { return nil }
            return StockPoint(date: String(fields[0]), close: close)
        } ?? []
    }

    private func request(_ url: URL, attempts: Int = 3) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        var lastError: Error = StockServiceError.invalidResponse
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw StockServiceError.invalidResponse
                }
                return data
            } catch {
                lastError = error
                guard attempt < attempts - 1 else { break }
                try? await Task.sleep(nanoseconds: UInt64(350 + attempt * 450) * 1_000_000)
            }
        }
        throw lastError
    }

    private func securityIDs(for symbol: StockSymbol) -> [String] {
        if symbol.providerCode.hasPrefix("sh") { return ["1." + String(symbol.providerCode.dropFirst(2))] }
        if symbol.providerCode.hasPrefix("sz") { return ["0." + String(symbol.providerCode.dropFirst(2))] }
        if symbol.providerCode.hasPrefix("hk") { return ["116." + String(symbol.providerCode.dropFirst(2))] }
        let ticker = symbol.canonical
        return ["105.\(ticker)", "106.\(ticker)", "107.\(ticker)"]
    }

    static func parse(data: Data, symbol: StockSymbol) throws -> StockSnapshot {
        let response = try JSONDecoder().decode(EastMoneyQuoteResponse.self, from: data)
        guard response.rc == 0, let quote = response.data else { throw StockServiceError.symbolNotFound }
        return snapshot(quote: quote, points: [], symbol: symbol)
    }

    static func parseFundamentals(data: Data) throws -> StockFundamentals {
        let response = try JSONDecoder().decode(EastMoneyFundamentalsResponse.self, from: data)
        guard response.rc == 0, let quote = response.data else {
            throw StockServiceError.symbolNotFound
        }
        return fundamentals(
            totalMarketValue: quote.f116?.value,
            circulatingMarketValue: quote.f117?.value,
            priceEarningsRatio: quote.f162?.value,
            industry: quote.f127,
            precision: quote.f152
        )
    }

    private static func snapshot(
        quote: EastMoneyQuote,
        points: [StockPoint],
        symbol: StockSymbol
    ) -> StockSnapshot {
        let divisor = pow(10.0, Double(quote.f59 ?? 2))
        let timestamp = quote.f86.map { Date(timeIntervalSince1970: $0) }
        var snapshot = StockSnapshot(
            symbol: symbol.canonical,
            providerCode: symbol.providerCode,
            name: quote.f58,
            marketName: symbol.marketName,
            currency: symbol.currency,
            price: quote.f43 / divisor,
            change: quote.f169 / divisor,
            changePercent: quote.f170 / 100,
            previousClose: quote.f60 / divisor,
            open: quote.f46 / divisor,
            high: quote.f44 / divisor,
            low: quote.f45 / divisor,
            volume: quote.f47,
            quoteTime: timestamp?.formatted(date: .numeric, time: .shortened) ?? "",
            points: points,
            fetchedAt: Date()
        )
        let fundamentals = fundamentals(
            totalMarketValue: quote.f116?.value,
            circulatingMarketValue: quote.f117?.value,
            priceEarningsRatio: quote.f162?.value,
            industry: quote.f127,
            precision: quote.f152
        )
        snapshot.totalMarketValue = fundamentals.totalMarketValue
        snapshot.circulatingMarketValue = fundamentals.circulatingMarketValue
        snapshot.priceEarningsRatio = fundamentals.priceEarningsRatio
        snapshot.industry = fundamentals.industry
        return snapshot
    }

    private static func fundamentals(
        totalMarketValue: Double?,
        circulatingMarketValue: Double?,
        priceEarningsRatio: Double?,
        industry: String?,
        precision: Int?
    ) -> StockFundamentals {
        let divisor = pow(10.0, Double(precision ?? 2))
        return StockFundamentals(
            totalMarketValue: totalMarketValue,
            circulatingMarketValue: circulatingMarketValue,
            priceEarningsRatio: priceEarningsRatio.map { $0 / divisor },
            industry: industry?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfPlaceholder
        )
    }

    private struct EastMoneyQuoteResponse: Decodable {
        let rc: Int
        let data: EastMoneyQuote?
    }

    private struct EastMoneyFundamentalsResponse: Decodable {
        let rc: Int
        let data: EastMoneyFundamentalsQuote?
    }

    private struct EastMoneyFundamentalsQuote: Decodable {
        let f116: EastMoneyOptionalDouble?
        let f117: EastMoneyOptionalDouble?
        let f127: String?
        let f152: Int?
        let f162: EastMoneyOptionalDouble?
    }

    private struct EastMoneyQuote: Decodable {
        let f43: Double
        let f44: Double
        let f45: Double
        let f46: Double
        let f47: Double
        let f58: String
        let f59: Int?
        let f60: Double
        let f169: Double
        let f170: Double
        let f86: Double?
        let f116: EastMoneyOptionalDouble?
        let f117: EastMoneyOptionalDouble?
        let f127: String?
        let f152: Int?
        let f162: EastMoneyOptionalDouble?
    }

    private struct EastMoneyOptionalDouble: Decodable {
        let value: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                value = nil
            } else if let number = try? container.decode(Double.self) {
                value = number
            } else if let text = try? container.decode(String.self) {
                value = Double(text)
            } else {
                value = nil
            }
        }
    }

    private struct EastMoneyHistoryResponse: Decodable {
        let data: EastMoneyHistory?
    }

    private struct EastMoneyHistory: Decodable {
        let klines: [String]
    }
}

struct SinaStockService {
    private static let responseEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    func fetch(_ symbol: StockSymbol) async throws -> StockSnapshot {
        var components = URLComponents(string: "https://hq.sinajs.cn/")!
        components.queryItems = [URLQueryItem(name: "list", value: requestCode(for: symbol))]
        guard let url = components.url else { throw StockServiceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: Self.responseEncoding)
                ?? String(data: data, encoding: .utf8) else {
            throw StockServiceError.invalidResponse
        }
        return try Self.parse(text: text, symbol: symbol)
    }

    static func parse(text: String, symbol: StockSymbol) throws -> StockSnapshot {
        guard let openingQuote = text.firstIndex(of: "\""),
              let closingQuote = text.lastIndex(of: "\""),
              openingQuote < closingQuote else { throw StockServiceError.malformedData }
        let values = text[text.index(after: openingQuote)..<closingQuote]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        guard !values.isEmpty, !values[0].isEmpty else { throw StockServiceError.symbolNotFound }

        switch symbol.marketName {
        case "上海", "深圳":
            guard values.count > 31 else { throw StockServiceError.malformedData }
            return snapshot(
                symbol: symbol, name: values[0], price: values.double(at: 3),
                previousClose: values.double(at: 2), open: values.double(at: 1),
                high: values.double(at: 4), low: values.double(at: 5),
                volume: values.double(at: 8), quoteTime: "\(values[30]) \(values[31])"
            )
        case "香港":
            guard values.count > 18 else { throw StockServiceError.malformedData }
            return snapshot(
                symbol: symbol, name: values[1].isEmpty ? values[0] : values[1],
                price: values.double(at: 6), previousClose: values.double(at: 3),
                open: values.double(at: 2), high: values.double(at: 4),
                low: values.double(at: 5), volume: values.double(at: 11),
                quoteTime: "\(values[17]) \(values[18])"
            )
        default:
            guard values.count > 26 else { throw StockServiceError.malformedData }
            return snapshot(
                symbol: symbol, name: values[0], price: values.double(at: 1),
                previousClose: values.double(at: 26), open: values.double(at: 5),
                high: values.double(at: 6), low: values.double(at: 7),
                volume: values.double(at: 10), quoteTime: values[3]
            )
        }
    }

    private static func snapshot(
        symbol: StockSymbol,
        name: String,
        price: Double,
        previousClose: Double,
        open: Double,
        high: Double,
        low: Double,
        volume: Double,
        quoteTime: String
    ) -> StockSnapshot {
        let change = price - previousClose
        return StockSnapshot(
            symbol: symbol.canonical,
            providerCode: symbol.providerCode,
            name: name,
            marketName: symbol.marketName,
            currency: symbol.currency,
            price: price,
            change: change,
            changePercent: previousClose == 0 ? 0 : change / previousClose * 100,
            previousClose: previousClose,
            open: open,
            high: high,
            low: low,
            volume: volume,
            quoteTime: quoteTime,
            points: [],
            fetchedAt: Date()
        )
    }

    private func requestCode(for symbol: StockSymbol) -> String {
        if symbol.marketName == "香港" { return "rt_\(symbol.providerCode)" }
        if symbol.marketName == "美国" { return "gb_\(symbol.canonical.lowercased())" }
        return symbol.providerCode
    }
}

@MainActor
final class StockStore: ObservableObject {
    @Published private(set) var records: [StockSnapshot] = []
    @Published var selectedSymbol: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingAll = false
    @Published var errorMessage = ""
    @Published private(set) var colorTheme: StockColorTheme
    @Published private(set) var dataSource: StockDataSource
    @Published private(set) var chartPoints: [StockPoint] = []
    @Published private(set) var chartPeriod: StockChartPeriod = .defaultSelection
    @Published private(set) var isLoadingChart = false
    @Published private(set) var chartErrorMessage = ""

    typealias QuoteFetcher = (StockSymbol) async throws -> StockSnapshot
    typealias ChartFetcher = (StockSymbol, StockChartPeriod, StockDataSource) async throws -> [StockPoint]

    private let customFetcher: QuoteFetcher?
    private let customChartFetcher: ChartFetcher?
    private let defaults: UserDefaults
    private let defaultsKey = "luma.stock.query-records.v1"
    private let colorThemeKey = "luma.stock.color-theme.v1"
    private let dataSourceKey = "luma.stock.data-source.v1"
    private var chartCache: [String: [StockChartPeriod: [StockPoint]]] = [:]
    private var chartRequestID: UUID?

    init(
        records preloadedRecords: [StockSnapshot]? = nil,
        defaults: UserDefaults = .standard,
        fetcher: QuoteFetcher? = nil,
        chartFetcher: ChartFetcher? = nil
    ) {
        self.defaults = defaults
        customFetcher = fetcher
        customChartFetcher = chartFetcher
        colorTheme = StockColorTheme(rawValue: defaults.string(forKey: colorThemeKey) ?? "")
            ?? .greenUpRedDown
        dataSource = StockDataSource(rawValue: defaults.string(forKey: dataSourceKey) ?? "")
            ?? .automatic
        if let preloadedRecords {
            records = preloadedRecords
            selectedSymbol = preloadedRecords.first?.symbol
            return
        }
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([StockSnapshot].self, from: data) {
            records = saved
            selectedSymbol = saved.first?.symbol
        }
    }

    var selected: StockSnapshot? {
        records.first { $0.symbol == selectedSymbol } ?? records.first
    }

    var isBusy: Bool { isLoading || isRefreshingAll }

    func query(_ input: String) async {
        guard !isBusy else { return }
        do {
            let symbol = try StockSymbolParser.parse(input)
            isLoading = true
            errorMessage = ""
            defer { isLoading = false }
            let snapshot = try await fetch(symbol)
            upsert(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSelected() async {
        guard let selected else { return }
        invalidateChart(for: selected.symbol)
        await query(selected.symbol)
    }

    func refreshAll() async {
        guard !isBusy, !records.isEmpty else { return }
        let symbols = records.map(\.symbol)
        let source = dataSource
        let customFetcher = customFetcher
        isRefreshingAll = true
        errorMessage = ""
        defer { isRefreshingAll = false }

        var failures = 0
        await withTaskGroup(of: StockSnapshot?.self) { group in
            let initialCount = min(4, symbols.count)
            for value in symbols.prefix(initialCount) {
                group.addTask {
                    guard let symbol = try? StockSymbolParser.parse(value) else { return nil }
                    return try? await Self.fetchSnapshot(
                        symbol,
                        source: source,
                        customFetcher: customFetcher
                    )
                }
            }
            var nextIndex = initialCount
            while let snapshot = await group.next() {
                if let snapshot {
                    if let index = records.firstIndex(where: { $0.symbol == snapshot.symbol }) {
                        records[index] = snapshot
                        invalidateChart(for: snapshot.symbol)
                    }
                } else {
                    failures += 1
                }
                if nextIndex < symbols.count {
                    let value = symbols[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        guard let symbol = try? StockSymbolParser.parse(value) else { return nil }
                        return try? await Self.fetchSnapshot(
                            symbol,
                            source: source,
                            customFetcher: customFetcher
                        )
                    }
                }
            }
        }
        save()
        if failures > 0 {
            errorMessage = "已刷新 \(symbols.count - failures)/\(symbols.count) 个标的，\(failures) 个失败"
        }
    }

    func setColorTheme(_ theme: StockColorTheme) {
        guard colorTheme != theme else { return }
        colorTheme = theme
        defaults.set(theme.rawValue, forKey: colorThemeKey)
    }

    func setDataSource(_ source: StockDataSource) {
        guard dataSource != source else { return }
        dataSource = source
        chartCache.removeAll()
        chartPoints = []
        chartErrorMessage = ""
        defaults.set(source.rawValue, forKey: dataSourceKey)
    }

    func select(_ snapshot: StockSnapshot) {
        guard records.contains(where: { $0.symbol == snapshot.symbol }) else { return }
        selectedSymbol = snapshot.symbol
        chartPoints = []
        chartErrorMessage = ""
    }

    func remove(_ snapshot: StockSnapshot) {
        records.removeAll { $0.symbol == snapshot.symbol }
        invalidateChart(for: snapshot.symbol)
        if selectedSymbol == snapshot.symbol { selectedSymbol = records.first?.symbol }
        save()
    }

    func loadChart(for snapshot: StockSnapshot, period: StockChartPeriod, force: Bool = false) async {
        if chartPeriod != period { chartPoints = [] }
        chartPeriod = period
        chartErrorMessage = ""
        let source = dataSource
        let cacheKey = "\(source.rawValue):\(snapshot.symbol)"
        if !force, let cached = chartCache[cacheKey]?[period] {
            chartPoints = cached
            return
        }

        let requestID = UUID()
        chartRequestID = requestID
        isLoadingChart = true
        defer {
            if chartRequestID == requestID { isLoadingChart = false }
        }

        do {
            let symbol = try StockSymbolParser.parse(snapshot.symbol)
            let points: [StockPoint]
            if let customChartFetcher {
                points = try await customChartFetcher(symbol, period, source)
            } else {
                points = try await StockChartService().fetch(symbol: symbol, period: period, source: source)
            }
            var periods = chartCache[cacheKey] ?? [:]
            periods[period] = points
            chartCache[cacheKey] = periods
            guard chartRequestID == requestID,
                  selectedSymbol == snapshot.symbol,
                  chartPeriod == period else { return }
            chartPoints = points
        } catch {
            guard chartRequestID == requestID else { return }
            chartPoints = []
            chartErrorMessage = error.localizedDescription
        }
    }

    private func upsert(_ snapshot: StockSnapshot) {
        invalidateChart(for: snapshot.symbol)
        records.removeAll { $0.symbol == snapshot.symbol }
        records.insert(snapshot, at: 0)
        if records.count > 20 { records.removeLast(records.count - 20) }
        selectedSymbol = snapshot.symbol
        save()
    }

    private func fetch(_ symbol: StockSymbol) async throws -> StockSnapshot {
        try await Self.fetchSnapshot(symbol, source: dataSource, customFetcher: customFetcher)
    }

    private nonisolated static func fetchSnapshot(
        _ symbol: StockSymbol,
        source: StockDataSource,
        customFetcher: QuoteFetcher?
    ) async throws -> StockSnapshot {
        if let customFetcher { return try await customFetcher(symbol) }
        switch source {
        case .automatic:
            var lastError: Error = StockServiceError.invalidResponse
            for candidate in [StockDataSource.tencent, .eastMoney, .sina] {
                do { return try await fetchSnapshot(symbol, source: candidate, customFetcher: nil) }
                catch { lastError = error }
            }
            throw lastError
        case .tencent:
            return await enrich(
                try await TencentStockService().fetch(symbol),
                symbol: symbol
            )
        case .eastMoney: return try await EastMoneyStockService().fetch(symbol)
        case .sina:
            return await enrich(
                try await SinaStockService().fetch(symbol),
                symbol: symbol
            )
        }
    }

    private nonisolated static func enrich(
        _ snapshot: StockSnapshot,
        symbol: StockSymbol
    ) async -> StockSnapshot {
        guard let fundamentals = try? await EastMoneyStockService().fetchFundamentals(symbol) else {
            return snapshot
        }
        var result = snapshot
        result.totalMarketValue = fundamentals.totalMarketValue
        result.circulatingMarketValue = fundamentals.circulatingMarketValue
        result.priceEarningsRatio = fundamentals.priceEarningsRatio
        result.industry = fundamentals.industry
        return result
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func invalidateChart(for symbol: String) {
        chartCache.keys.filter { $0.hasSuffix(":\(symbol)") }.forEach { chartCache.removeValue(forKey: $0) }
        if selectedSymbol == symbol { chartPoints = [] }
    }
}

private extension String {
    var nilIfPlaceholder: String? { isEmpty || self == "-" ? nil : self }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == String {
    func double(at index: Int) -> Double {
        guard indices.contains(index) else { return 0 }
        return Double(self[index]) ?? 0
    }
}
