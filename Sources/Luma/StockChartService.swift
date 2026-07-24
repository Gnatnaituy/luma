import Foundation

enum StockChartPeriod: String, CaseIterable, Identifiable {
    case intraday
    case fiveDay
    case daily
    case weekly
    case monthly

    static let defaultSelection: StockChartPeriod = .intraday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intraday: "分时"
        case .fiveDay: "五日"
        case .daily: "日K"
        case .weekly: "周K"
        case .monthly: "月K"
        }
    }

    var isCandlestick: Bool {
        switch self {
        case .intraday, .fiveDay: false
        case .daily, .weekly, .monthly: true
        }
    }
}

enum StockChartSampler {
    static func downsample(_ points: [StockPoint], maximumCount: Int) -> [StockPoint] {
        guard maximumCount >= 2, points.count > maximumCount else { return points }
        let step = Double(points.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { offset in
            points[min(Int((Double(offset) * step).rounded()), points.count - 1)]
        }
    }
}

enum StockTradingTimeline {
    static let startMinute = 9 * 60 + 15
    static let endMinute = 15 * 60 + 30
    static let gridRatios = [0.0, ratio(minute: 11 * 60 + 30), ratio(minute: 13 * 60), 1.0]

    static func ratio(for label: String) -> Double? {
        guard let minute = minuteValue(from: label) else { return nil }
        return ratio(minute: minute)
    }

    private static func ratio(minute: Int) -> Double {
        let span = Double(endMinute - startMinute)
        return min(max(Double(minute - startMinute) / span, 0), 1)
    }

    private static func minuteValue(from label: String) -> Int? {
        guard let time = label.split(separator: " ").last else { return nil }
        if time.contains(":") {
            let fields = time.split(separator: ":")
            guard fields.count >= 2, let hour = Int(fields[0]), let minute = Int(fields[1]) else { return nil }
            return hour * 60 + minute
        }
        let digits = time.filter(\.isNumber)
        guard digits.count >= 4,
              let hour = Int(digits.prefix(2)),
              let minute = Int(digits.dropFirst(2).prefix(2)) else { return nil }
        return hour * 60 + minute
    }
}

struct StockChartService {
    func fetch(symbol: StockSymbol, period: StockChartPeriod, source: StockDataSource) async throws -> [StockPoint] {
        do {
            let points: [StockPoint]
            switch source {
            case .tencent:
                points = try await TencentStockChartService().fetch(symbol: symbol, period: period)
            case .eastMoney:
                points = try await EastMoneyStockChartService().fetch(symbol: symbol, period: period)
            case .sina:
                points = try await SinaStockChartService().fetch(symbol: symbol, period: period)
            }
            guard points.count > 1 else { throw StockServiceError.malformedData }
            return points
        } catch {
            guard source != .tencent else { throw error }
            return try await TencentStockChartService().fetch(symbol: symbol, period: period)
        }
    }
}

struct TencentStockChartService {
    func fetch(symbol: StockSymbol, period: StockChartPeriod) async throws -> [StockPoint] {
        switch period {
        case .intraday:
            return try await fetchMinutes(symbol: symbol, fiveDays: false)
        case .fiveDay:
            return try await fetchMinutes(symbol: symbol, fiveDays: true)
        case .daily, .weekly, .monthly:
            return try await fetchKLine(symbol: symbol, period: period)
        }
    }

    static func parseMinutes(data: Data, symbol: StockSymbol, fiveDays: Bool) throws -> [StockPoint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataRoot = root["data"] as? [String: Any],
              let payload = dataRoot[symbol.providerCode] as? [String: Any] else {
            throw StockServiceError.malformedData
        }
        var points: [StockPoint] = []
        if fiveDays, let days = payload["data"] as? [[String: Any]] {
            for day in days {
                let date = day["date"] as? String ?? ""
                points.append(contentsOf: parseMinuteRows(day["data"] as? [String] ?? [], date: date))
            }
            points.sort { $0.date < $1.date }
        } else if let minuteData = payload["data"] as? [String: Any] {
            let date = minuteData["date"] as? String ?? ""
            points = parseMinuteRows(minuteData["data"] as? [String] ?? [], date: date)
        }
        guard points.count > 1 else { throw StockServiceError.malformedData }
        return points
    }

    static func parseKLine(data: Data, symbol: StockSymbol, period: StockChartPeriod) throws -> [StockPoint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataRoot = root["data"] as? [String: Any],
              let payload = dataRoot[symbol.providerCode] as? [String: Any] else {
            throw StockServiceError.malformedData
        }
        let key: String
        switch period {
        case .daily: key = "qfqday"
        case .weekly: key = "qfqweek"
        case .monthly: key = "qfqmonth"
        default: throw StockServiceError.malformedData
        }
        let rows = payload[key] as? [[Any]] ?? []
        let points = rows.compactMap(parseOHLCRow)
        guard points.count > 1 else { throw StockServiceError.malformedData }
        return points
    }

    private func fetchMinutes(symbol: StockSymbol, fiveDays: Bool) async throws -> [StockPoint] {
        let endpoint = fiveDays ? "day" : "minute"
        var components = URLComponents(string: "https://web.ifzq.gtimg.cn/appstock/app/\(endpoint)/query")!
        components.queryItems = [URLQueryItem(name: "code", value: symbol.providerCode)]
        let data = try await request(components)
        return try Self.parseMinutes(data: data, symbol: symbol, fiveDays: fiveDays)
    }

    private func fetchKLine(symbol: StockSymbol, period: StockChartPeriod) async throws -> [StockPoint] {
        let type: String
        switch period {
        case .daily: type = "day"
        case .weekly: type = "week"
        case .monthly: type = "month"
        default: throw StockServiceError.malformedData
        }
        var components = URLComponents(string: "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get")!
        components.queryItems = [URLQueryItem(name: "param", value: "\(symbol.providerCode),\(type),,,60,qfq")]
        let data = try await request(components)
        return try Self.parseKLine(data: data, symbol: symbol, period: period)
    }

    private func request(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else { throw StockServiceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StockServiceError.invalidResponse
        }
        return data
    }

    private static func parseMinuteRows(_ rows: [String], date: String) -> [StockPoint] {
        rows.compactMap { row in
            let fields = row.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count > 1, let price = Double(fields[1]) else { return nil }
            let label = date.isEmpty ? String(fields[0]) : "\(date) \(fields[0])"
            return StockPoint(date: label, close: price)
        }
    }

    private static func parseOHLCRow(_ row: [Any]) -> StockPoint? {
        guard row.count > 4,
              let date = row[0] as? String,
              let open = double(row[1]),
              let close = double(row[2]),
              let high = double(row[3]),
              let low = double(row[4]) else { return nil }
        return StockPoint(
            date: date,
            close: close,
            open: open,
            high: high,
            low: low,
            volume: row.count > 5 ? double(row[5]) : nil
        )
    }

    private static func double(_ value: Any) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

struct EastMoneyStockChartService {
    func fetch(symbol: StockSymbol, period: StockChartPeriod) async throws -> [StockPoint] {
        var lastError: Error = StockServiceError.symbolNotFound
        for securityID in securityIDs(for: symbol) {
            do {
                if period == .intraday || period == .fiveDay {
                    return try await fetchTrends(securityID: securityID, days: period == .intraday ? 1 : 5)
                }
                return try await fetchKLine(securityID: securityID, period: period)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func parseTrends(data: Data) throws -> [StockPoint] {
        let response = try JSONDecoder().decode(TrendResponse.self, from: data)
        let points = response.data?.trends.compactMap { row -> StockPoint? in
            let fields = row.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > 2, let close = Double(fields[2]) else { return nil }
            return StockPoint(date: String(fields[0]), close: close)
        } ?? []
        guard points.count > 1 else { throw StockServiceError.malformedData }
        return points
    }

    static func parseKLine(data: Data) throws -> [StockPoint] {
        let response = try JSONDecoder().decode(KLineResponse.self, from: data)
        let points = response.data?.klines.compactMap { row -> StockPoint? in
            let fields = row.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > 5,
                  let open = Double(fields[1]), let close = Double(fields[2]),
                  let high = Double(fields[3]), let low = Double(fields[4]) else { return nil }
            return StockPoint(
                date: String(fields[0]), close: close, open: open, high: high, low: low,
                volume: Double(fields[5])
            )
        } ?? []
        guard points.count > 1 else { throw StockServiceError.malformedData }
        return points
    }

    private func fetchTrends(securityID: String, days: Int) async throws -> [StockPoint] {
        var components = URLComponents(string: "https://push2his.eastmoney.com/api/qt/stock/trends2/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: securityID),
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58"),
            URLQueryItem(name: "ndays", value: String(days))
        ]
        let data = try await request(components)
        return try Self.parseTrends(data: data)
    }

    private func fetchKLine(securityID: String, period: StockChartPeriod) async throws -> [StockPoint] {
        let klt: String
        switch period {
        case .daily: klt = "101"
        case .weekly: klt = "102"
        case .monthly: klt = "103"
        default: throw StockServiceError.malformedData
        }
        var components = URLComponents(string: "https://push2his.eastmoney.com/api/qt/stock/kline/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: securityID),
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"),
            URLQueryItem(name: "klt", value: klt),
            URLQueryItem(name: "fqt", value: "1"),
            URLQueryItem(name: "end", value: "20500101"),
            URLQueryItem(name: "lmt", value: "60")
        ]
        let data = try await request(components)
        return try Self.parseKLine(data: data)
    }

    private func request(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else { throw StockServiceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StockServiceError.invalidResponse
        }
        return data
    }

    private func securityIDs(for symbol: StockSymbol) -> [String] {
        if symbol.providerCode.hasPrefix("sh") { return ["1." + String(symbol.providerCode.dropFirst(2))] }
        if symbol.providerCode.hasPrefix("sz") { return ["0." + String(symbol.providerCode.dropFirst(2))] }
        if symbol.providerCode.hasPrefix("hk") { return ["116." + String(symbol.providerCode.dropFirst(2))] }
        return ["105.\(symbol.canonical)", "106.\(symbol.canonical)", "107.\(symbol.canonical)"]
    }

    private struct TrendResponse: Decodable {
        let data: TrendData?
    }
    private struct TrendData: Decodable {
        let trends: [String]
    }
    private struct KLineResponse: Decodable {
        let data: KLineData?
    }
    private struct KLineData: Decodable {
        let klines: [String]
    }
}

struct SinaStockChartService {
    func fetch(symbol: StockSymbol, period: StockChartPeriod) async throws -> [StockPoint] {
        guard symbol.marketName == "上海" || symbol.marketName == "深圳" else {
            throw StockServiceError.symbolNotFound
        }
        let scale: Int
        let length: Int
        switch period {
        case .intraday: (scale, length) = (1, 242)
        case .fiveDay: (scale, length) = (5, 300)
        case .daily, .weekly, .monthly: (scale, length) = (240, period == .monthly ? 1000 : 360)
        }
        var components = URLComponents(
            string: "https://quotes.sina.cn/cn/api/openapi.php/CN_MarketDataService.getKLineData"
        )!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol.providerCode),
            URLQueryItem(name: "scale", value: String(scale)),
            URLQueryItem(name: "ma", value: "no"),
            URLQueryItem(name: "datalen", value: String(length))
        ]
        guard let url = components.url else { throw StockServiceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StockServiceError.invalidResponse
        }
        var points = try Self.parse(data: data)
        if period == .weekly { points = aggregate(points, component: .weekOfYear) }
        if period == .monthly { points = aggregate(points, component: .month) }
        guard points.count > 1 else { throw StockServiceError.malformedData }
        return points
    }

    static func parse(data: Data) throws -> [StockPoint] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result.status.code == 0 else { throw StockServiceError.invalidResponse }
        return response.result.data.compactMap { row in
            guard let close = Double(row.close), let open = Double(row.open),
                  let high = Double(row.high), let low = Double(row.low) else { return nil }
            return StockPoint(
                date: row.day, close: close, open: open, high: high, low: low,
                volume: Double(row.volume)
            )
        }
    }

    private func aggregate(_ points: [StockPoint], component: Calendar.Component) -> [StockPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar(identifier: .iso8601)
        var grouped: [String: [StockPoint]] = [:]
        var order: [String] = []
        for point in points {
            guard let date = formatter.date(from: String(point.date.prefix(10))) else { continue }
            let yearComponent: Calendar.Component = component == .month ? .year : .yearForWeekOfYear
            let year = calendar.component(yearComponent, from: date)
            let value = calendar.component(component, from: date)
            let key = "\(year)-\(value)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(point)
        }
        return order.compactMap { key in
            guard let rows = grouped[key], let first = rows.first, let last = rows.last else { return nil }
            let highs = rows.compactMap(\.high)
            let lows = rows.compactMap(\.low)
            return StockPoint(
                date: String(last.date.prefix(10)), close: last.close, open: first.open,
                high: highs.max(), low: lows.min(), volume: rows.compactMap(\.volume).reduce(0, +)
            )
        }
    }

    private struct Response: Decodable {
        let result: Result
    }
    private struct Result: Decodable {
        let status: Status
        let data: [Row]
    }
    private struct Status: Decodable {
        let code: Int
    }
    private struct Row: Decodable {
        let day: String
        let open: String
        let high: String
        let low: String
        let close: String
        let volume: String
    }
}
