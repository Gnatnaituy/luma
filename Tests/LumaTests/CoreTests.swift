import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
import Testing

@testable import Luma

@Suite(.serialized)
struct CoreTests {
    @Test
    @MainActor
    func testCoreBehavior() async throws {
        try expect(ExpressionEvaluator.evaluate("2 + 3 * 4") == 14, "operator precedence")
        try expect(ExpressionEvaluator.evaluate("2 ^ 3 ^ 2") == 512, "right-associative power")
        try expect(ExpressionEvaluator.evaluate("sqrt(81) + abs(-4)") == 13, "functions")

        do {
            _ = try ExpressionEvaluator.evaluate("4 / 0")
            throw TestFailure("division by zero must fail")
        } catch ExpressionError.divisionByZero {
            // Expected.
        }
        let calculationRecords = (0..<17).reduce(into: [CalculationRecord]()) { records, index in
            records = CalculationHistory.appending(
                expression: "\(index) + 1",
                result: "\(index + 1)",
                to: records
            )
        }
        try expect(
            CalculationHistory.maximumCount == 15
                && calculationRecords.count == 15
                && calculationRecords.first?.expression == "2 + 1"
                && calculationRecords.last?.expression == "16 + 1",
            "calculator keeps the newest fifteen submitted calculations"
        )
        let calculationSuiteName = "app.luma.calculator-tests." + UUID().uuidString
        let calculationDefaults = UserDefaults(suiteName: calculationSuiteName)!
        calculationDefaults.removePersistentDomain(forName: calculationSuiteName)
        defer { calculationDefaults.removePersistentDomain(forName: calculationSuiteName) }
        let calculationStore = CalculationHistoryStore(defaults: calculationDefaults)
        for index in 0..<17 {
            calculationStore.append(expression: "\(index) × 2", result: "\(index * 2)")
        }
        let restoredCalculationStore = CalculationHistoryStore(defaults: calculationDefaults)
        try expect(
            restoredCalculationStore.records.count == 15
                && restoredCalculationStore.records.first?.expression == "2 × 2"
                && restoredCalculationStore.records.last?.result == "32",
            "calculator history persists across app launches"
        )
        try expect(Plugin.calculator.title == "计算器", "calculator uses its Chinese plugin name")

        let formatted = try JSONTool.format("{\"b\":2,\"a\":1}", pretty: true)
        try expect(formatted.contains("\n"), "pretty JSON")
        try expect(try JSONTool.format("\"Luma\"", pretty: false) == "\"Luma\"", "JSON fragments")
        let stringToEscape = "He said \"你好\"\nLuma"
        let escapedString = try JSONTool.escape(stringToEscape)
        try expect(escapedString == "He said \\\"你好\\\"\\nLuma", "JSON string escape")
        try expect(try JSONTool.unescape(escapedString) == stringToEscape, "JSON string unescape round trip")
        try expect(try JSONTool.unescape("\"Luma\\n原生\"") == "Luma\n原生", "quoted JSON string unescape")

        try expect(TranslationLanguageDetector.target(for: "你好，Luma") == .english, "Chinese input targets English")
        try expect(TranslationLanguageDetector.target(for: "Hello, Luma") == .simplifiedChinese, "English input targets Chinese")
        try expect(TranslationLanguageDetector.target(for: "  \n") == nil, "blank translation input keeps target")

        var highlightedJSON = "{\"name\":\"Luma\",\"native\":true,\"count\":7}"
        let editor = JSONSyntaxEditor(text: Binding(get: { highlightedJSON }, set: { highlightedJSON = $0 }))
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView()
        textView.string = highlightedJSON
        coordinator.applyHighlighting(to: textView)
        let source = highlightedJSON as NSString
        let keyIndex = source.range(of: "name").location
        let stringIndex = source.range(of: "Luma").location
        let literalIndex = source.range(of: "true").location
        let keyColor = textView.textStorage?.attribute(.foregroundColor, at: keyIndex, effectiveRange: nil) as? NSColor
        let stringColor = textView.textStorage?.attribute(.foregroundColor, at: stringIndex, effectiveRange: nil) as? NSColor
        let literalColor = textView.textStorage?.attribute(.foregroundColor, at: literalIndex, effectiveRange: nil) as? NSColor
        try expect(keyColor != nil && stringColor != nil && literalColor != nil, "JSON syntax colors present")
        try expect(keyColor != stringColor && stringColor != literalColor, "JSON syntax token colors differ")

        let encoded = CodeTool.base64Encode("Luma 原生")
        try expect(CodeTool.base64Decode(encoded) == "Luma 原生", "Base64 round trip")
        try expect(
            CodeTool.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "SHA-256"
        )

        let password = PasswordTool.generate(length: 32, uppercase: true, digits: true, symbols: true)
        try expect(password.count == 32, "password length")
        try expect(password.allSatisfy { !$0.isWhitespace }, "password alphabet")
        try expect(PasswordTool.generate(length: 4, uppercase: false, digits: false, symbols: false).count == 6, "password minimum")
        try expect(PasswordTool.generate(length: 99, uppercase: true, digits: true, symbols: true).count == 32, "password maximum")

        try expect(try StockSymbolParser.parse("AAPL").providerCode == "usAAPL", "US stock symbol")
        try expect(try StockSymbolParser.parse("600115.SS").providerCode == "sh600115", "Shanghai stock symbol")
        try expect(try StockSymbolParser.parse("002594").canonical == "002594.SZ", "Shenzhen stock inference")
        try expect(try StockSymbolParser.parse("700.HK").canonical == "00700.HK", "Hong Kong stock padding")
        let stockSearchFixture = Data("""
        {"QuotationCodeTable":{"Data":[
          {"Code":"600519","Name":"贵州茅台","Classify":"AStock","QuoteID":"1.600519","SecurityTypeName":"沪A"},
          {"Code":"00700","Name":"腾讯控股","Classify":"HK","QuoteID":"116.00700","SecurityTypeName":"港股"},
          {"Code":"AAPL","Name":"苹果","Classify":"UsStock","QuoteID":"105.AAPL","SecurityTypeName":"美股"},
          {"Code":"BK0666","Name":"苹果概念","Classify":"BK","QuoteID":"90.BK0666","SecurityTypeName":"板块"}
        ]}}
        """.utf8)
        let stockSuggestions = try EastMoneyStockSearchService.parse(data: stockSearchFixture)
        try expect(
            stockSuggestions.map(\.symbol) == ["600519.SS", "00700.HK", "AAPL"]
                && stockSuggestions.map(\.name) == ["贵州茅台", "腾讯控股", "苹果"],
            "stock name search maps supported markets and filters non-stock results"
        )

        var quote = Array(repeating: "", count: 48)
        quote[1] = "中国东航"
        quote[2] = "600115"
        quote[3] = "3.51"
        quote[4] = "3.46"
        quote[5] = "3.48"
        quote[6] = "1000"
        quote[30] = "20260720114041"
        quote[31] = "0.05"
        quote[32] = "1.45"
        quote[33] = "3.53"
        quote[34] = "3.45"
        let fixture: [String: Any] = [
            "code": 0,
            "msg": "",
            "data": [
                "sh600115": [
                    "qfqday": [["2026-07-17", "3.46", "3.50"], ["2026-07-20", "3.48", "3.51"]],
                    "qt": quote
                ]
            ]
        ]
        let fixtureData = try JSONSerialization.data(withJSONObject: fixture)
        let stock = try TencentStockService.parse(data: fixtureData, symbol: StockSymbolParser.parse("600115.SS"))
        try expect(stock.name == "中国东航" && stock.points.count == 2, "stock response parsing")
        try expect(abs(stock.amplitudePercent - 2.31) < 0.01, "stock daily amplitude calculation")
        try expect(abs(stock.openChangePercent - 0.58) < 0.01, "stock opening change calculation")
        try expect(abs((stock.dayPosition ?? 0) - 0.75) < 0.001, "stock intraday position calculation")
        try expect(stock.periodHigh == 3.51 && stock.periodLow == 3.50, "stock period range calculation")
        try expect(abs((stock.periodChangePercent ?? 0) - 0.2857) < 0.001, "stock period return calculation")
        let savedStock = try JSONDecoder().decode(StockSnapshot.self, from: JSONEncoder().encode(stock))
        try expect(savedStock == stock, "stock query record persistence")
        try expect(
            StockDataSource.allCases.map(\.title) == ["自动", "腾讯财经", "东方财富", "新浪财经"],
            "stock settings exposes automatic fallback and three selectable data sources"
        )
        try expect(
            StockChartPeriod.allCases.map(\.title) == ["分时", "五日", "日K", "周K", "月K"],
            "stock chart exposes all requested periods"
        )
        try expect(
            StockChartPeriod.defaultSelection == .intraday,
            "stock details default to the intraday chart"
        )
        let denseChart = (0..<1_335).map { StockPoint(date: String($0), close: Double($0)) }
        let sampledChart = StockChartSampler.downsample(denseChart, maximumCount: 360)
        try expect(
            sampledChart.count == 360
                && sampledChart.first == denseChart.first
                && sampledChart.last == denseChart.last,
            "dense stock lines are downsampled while preserving endpoints"
        )
        try expect(StockTradingTimeline.ratio(for: "20260723 0915") == 0, "intraday timeline starts at 09:15")
        try expect(StockTradingTimeline.ratio(for: "2026-07-23 15:30") == 1, "intraday timeline ends at 15:30")
        try expect(
            abs((StockTradingTimeline.ratio(for: "20260723 0930") ?? 0) - 0.04) < 0.0001,
            "intraday points use fixed clock coordinates"
        )
        let tencentMinuteFixture: [String: Any] = [
            "data": [
                "sh600115": [
                    "data": ["date": "20260722", "data": ["0930 3.50 10", "0931 3.52 20"]]
                ]
            ]
        ]
        let tencentMinuteData = try JSONSerialization.data(withJSONObject: tencentMinuteFixture)
        let minutePoints = try TencentStockChartService.parseMinutes(
            data: tencentMinuteData,
            symbol: StockSymbolParser.parse("600115.SS"),
            fiveDays: false
        )
        try expect(
            minutePoints.map(\.close) == [3.50, 3.52] && minutePoints.last?.date == "20260722 0931",
            "Tencent intraday chart parsing"
        )
        let tencentFiveDayFixture: [String: Any] = [
            "data": [
                "sh600115": [
                    "data": [
                        ["date": "20260722", "data": ["0930 3.52 10"]],
                        ["date": "20260721", "data": ["0930 3.48 10"]]
                    ]
                ]
            ]
        ]
        let tencentFiveDayData = try JSONSerialization.data(withJSONObject: tencentFiveDayFixture)
        let fiveDayPoints = try TencentStockChartService.parseMinutes(
            data: tencentFiveDayData,
            symbol: StockSymbolParser.parse("600115.SS"),
            fiveDays: true
        )
        try expect(
            fiveDayPoints.first?.date == "20260721 0930" && fiveDayPoints.last?.date == "20260722 0930",
            "Tencent five-day chart sorts trading days chronologically"
        )
        let tencentKFixture: [String: Any] = [
            "data": [
                "sh600115": [
                    "qfqweek": [
                        ["2026-07-17", "3.40", "3.50", "3.55", "3.38", "1000"],
                        ["2026-07-22", "3.50", "3.59", "3.62", "3.48", "1200"]
                    ]
                ]
            ]
        ]
        let tencentKData = try JSONSerialization.data(withJSONObject: tencentKFixture)
        let weeklyPoints = try TencentStockChartService.parseKLine(
            data: tencentKData,
            symbol: StockSymbolParser.parse("600115.SS"),
            period: .weekly
        )
        try expect(
            weeklyPoints.count == 2 && weeklyPoints.last?.open == 3.50 && weeklyPoints.last?.high == 3.62,
            "Tencent candlestick chart parsing"
        )
        let eastTrendData = Data("""
        {"data":{"trends":["2026-07-22 09:30,0,3.50,3.50,3.50,10","2026-07-22 09:31,0,3.52,3.53,3.49,20"]}}
        """.utf8)
        let eastTrendPoints = try EastMoneyStockChartService.parseTrends(data: eastTrendData)
        try expect(eastTrendPoints.map(\.close) == [3.50, 3.52], "East Money intraday chart parsing")
        let eastKData = Data("""
        {"data":{"klines":["2026-07-21,3.40,3.50,3.55,3.38,1000","2026-07-22,3.50,3.59,3.62,3.48,1200"]}}
        """.utf8)
        let eastKPoints = try EastMoneyStockChartService.parseKLine(data: eastKData)
        try expect(eastKPoints.last?.low == 3.48 && eastKPoints.last?.volume == 1200, "East Money K-line parsing")
        let sinaChartData = Data("""
        {"result":{"status":{"code":0},"data":[{"day":"2026-07-22","open":"3.50","high":"3.62","low":"3.48","close":"3.59","volume":"1200"},{"day":"2026-07-23","open":"3.59","high":"3.66","low":"3.55","close":"3.63","volume":"1300"}]}}
        """.utf8)
        let sinaChartPoints = try SinaStockChartService.parse(data: sinaChartData)
        try expect(sinaChartPoints.count == 2 && sinaChartPoints.last?.close == 3.63, "Sina K-line parsing")
        try expect(
            !LauncherPanelDismissalPolicy.shouldDismissOnResignKey(
                isPresentingSheet: true,
                hasAttachedSheet: true
            ),
            "launcher remains visible while a sheet is presented"
        )
        try expect(
            LauncherPanelDismissalPolicy.shouldDismissOnResignKey(
                isPresentingSheet: false,
                hasAttachedSheet: false
            ),
            "launcher dismisses after genuinely losing focus"
        )

        let eastMoneyFixture: [String: Any] = [
            "rc": 0,
            "data": [
                "f43": 352, "f44": 353, "f45": 346, "f46": 351, "f47": 177_773_264,
                "f58": "中国东航", "f59": 2, "f60": 351, "f169": 1, "f170": 28,
                "f86": 1_784_534_899
            ]
        ]
        let eastMoneyData = try JSONSerialization.data(withJSONObject: eastMoneyFixture)
        let eastMoneyStock = try EastMoneyStockService.parse(
            data: eastMoneyData,
            symbol: StockSymbolParser.parse("600115.SS")
        )
        try expect(
            eastMoneyStock.name == "中国东航"
                && eastMoneyStock.price == 3.52
                && eastMoneyStock.previousClose == 3.51
                && abs(eastMoneyStock.changePercent - 0.28) < 0.0001,
            "East Money quote parsing respects provider precision"
        )
        let fundamentalsData = Data("""
        {"rc":0,"data":{"f116":1610992660024.71,"f117":1250992660024.71,"f127":"白酒Ⅱ","f152":2,"f162":1478}}
        """.utf8)
        let fundamentals = try EastMoneyStockService.parseFundamentals(data: fundamentalsData)
        try expect(
            fundamentals.totalMarketValue == 1_610_992_660_024.71
                && fundamentals.circulatingMarketValue == 1_250_992_660_024.71
                && fundamentals.priceEarningsRatio == 14.78
                && fundamentals.industry == "白酒Ⅱ",
            "East Money fundamentals parsing supports valuation and industry fields"
        )
        let unavailableFundamentals = try EastMoneyStockService.parseFundamentals(
            data: Data(#"{"rc":0,"data":{"f116":"-","f117":"-","f127":"-","f152":2,"f162":"-"}}"#.utf8)
        )
        try expect(
            unavailableFundamentals.totalMarketValue == nil
                && unavailableFundamentals.circulatingMarketValue == nil
                && unavailableFundamentals.priceEarningsRatio == nil
                && unavailableFundamentals.industry == nil,
            "East Money placeholder fundamentals remain optional"
        )

        let sinaLine = "var hq_str_sh600115=\"中国东航,3.510,3.510,3.520,3.530,3.460,0,0,177773264,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2026-07-20,15:34:59\";"
        let sinaStock = try SinaStockService.parse(
            text: sinaLine,
            symbol: StockSymbolParser.parse("600115.SS")
        )
        try expect(
            sinaStock.name == "中国东航"
                && sinaStock.price == 3.52
                && sinaStock.quoteTime == "2026-07-20 15:34:59",
            "Sina quote parsing supports mainland market responses"
        )

        let stockSuiteName = "app.luma.stock-tests." + UUID().uuidString
        let stockDefaults = UserDefaults(suiteName: stockSuiteName)!
        stockDefaults.removePersistentDomain(forName: stockSuiteName)
        defer { stockDefaults.removePersistentDomain(forName: stockSuiteName) }
        let stockThemeStore = StockStore(records: [], defaults: stockDefaults)
        try expect(stockThemeStore.colorTheme == .greenUpRedDown, "default stock color theme")
        stockThemeStore.setColorTheme(.redUpGreenDown)
        stockThemeStore.setDataSource(.eastMoney)
        let restoredStockTheme = StockStore(records: [], defaults: stockDefaults)
        try expect(
            restoredStockTheme.colorTheme == .redUpGreenDown
                && restoredStockTheme.dataSource == .eastMoney,
            "stock color theme and selected data source persist"
        )

        let secondStock = StockSnapshot(
            symbol: "AAPL",
            providerCode: "usAAPL",
            name: "Apple",
            marketName: "美国",
            currency: "USD",
            price: 210,
            change: -1,
            changePercent: -0.47,
            previousClose: 211,
            open: 211,
            high: 212,
            low: 209,
            volume: 1_000,
            quoteTime: "20260720120000",
            points: [],
            fetchedAt: Date()
        )
        var chartFetchCount = 0
        let chartStore = StockStore(
            records: [stock],
            defaults: stockDefaults,
            chartFetcher: { _, period, _ in
                chartFetchCount += 1
                return period == .intraday ? minutePoints : weeklyPoints
            }
        )
        await chartStore.loadChart(for: stock, period: .intraday)
        await chartStore.loadChart(for: stock, period: .intraday)
        try expect(
            chartFetchCount == 1 && chartStore.chartPoints == minutePoints,
            "stock chart cache avoids duplicate period requests"
        )
        var refreshedSymbols: [String] = []
        var queryLoadingStatesDuringRefresh: [Bool] = []
        var refreshingStockStore: StockStore!
        refreshingStockStore = StockStore(
            records: [stock, secondStock],
            defaults: stockDefaults,
            fetcher: { symbol in
                queryLoadingStatesDuringRefresh.append(refreshingStockStore.isLoading)
                refreshedSymbols.append(symbol.canonical)
                let original = symbol.canonical == stock.symbol ? stock : secondStock
                return StockSnapshot(
                    symbol: original.symbol,
                    providerCode: original.providerCode,
                    name: original.name,
                    marketName: original.marketName,
                    currency: original.currency,
                    price: original.price + 1,
                    change: original.change,
                    changePercent: original.changePercent,
                    previousClose: original.previousClose,
                    open: original.open,
                    high: original.high,
                    low: original.low,
                    volume: original.volume,
                    quoteTime: original.quoteTime,
                    points: original.points,
                    fetchedAt: Date()
                )
            }
        )
        await refreshingStockStore.refreshAll()
        try expect(
            refreshedSymbols == [stock.symbol, secondStock.symbol]
                && refreshingStockStore.records.allSatisfy { snapshot in
                    snapshot.price == (snapshot.symbol == stock.symbol ? stock.price + 1 : secondStock.price + 1)
                },
            "refresh all stocks updates every saved symbol"
        )
        try expect(
            queryLoadingStatesDuringRefresh.allSatisfy { !$0 },
            "refresh all does not activate the add-stock loading state"
        )
        for index in 0..<100 {
            let target = index.isMultiple(of: 2) ? stock : secondStock
            refreshingStockStore.select(target)
            try expect(
                refreshingStockStore.selectedSymbol == target.symbol
                    && refreshingStockStore.selected?.symbol == target.symbol,
                "stock selection remains deterministic during rapid repeated switching"
            )
        }

        let locationFixture = Data("""
        {"results":[
          {"id":1796236,"name":"上海","latitude":31.22222,"longitude":121.45806,"timezone":"Asia/Shanghai","country":"中国","admin1":"上海市"},
          {"id":745044,"name":"Springfield","latitude":39.80172,"longitude":-89.64371,"timezone":"America/Chicago","country":"美国","admin1":"Illinois"}
        ]}
        """.utf8)
        let shanghai = try OpenMeteoWeatherService.parseLocation(data: locationFixture)
        let locationSuggestions = try OpenMeteoWeatherService.parseLocations(data: locationFixture)
        try expect(
            shanghai.name == "上海"
                && shanghai.subtitle == "上海市 · 中国"
                && shanghai.timezone == "Asia/Shanghai"
                && locationSuggestions.map(\.name) == ["上海", "Springfield"],
            "weather geocoding response parses multiple suggestions"
        )
        let forecastFixture = Data("""
        {
          "current": {
            "time": "2026-07-23T14:00", "temperature_2m": 33.2,
            "relative_humidity_2m": 61, "apparent_temperature": 37.8,
            "is_day": 1, "precipitation": 0.1, "weather_code": 2,
            "wind_speed_10m": 13.4, "wind_direction_10m": 135
          },
          "hourly": {
            "time": ["2026-07-23T13:00", "2026-07-23T14:00", "2026-07-23T15:00"],
            "temperature_2m": [32.8, 33.2, 32.7],
            "precipitation_probability": [10, 15, 20],
            "weather_code": [1, 2, 61]
          },
          "daily": {
            "time": ["2026-07-23", "2026-07-24"],
            "weather_code": [2, 61],
            "temperature_2m_max": [34.0, 31.0],
            "temperature_2m_min": [27.0, 26.0],
            "precipitation_probability_max": [20, 70],
            "sunrise": ["2026-07-23T05:06", "2026-07-24T05:07"],
            "sunset": ["2026-07-23T18:55", "2026-07-24T18:54"],
            "wind_speed_10m_max": [18.0, 23.0]
          }
        }
        """.utf8)
        let weather = try OpenMeteoWeatherService.parseForecast(data: forecastFixture, location: shanghai)
        try expect(
            weather.current.temperature == 33.2
                && weather.hourly.count == 2
                && weather.hourly.first?.time == "2026-07-23T14:00"
                && weather.daily.count == 2,
            "weather current hourly and daily response parsing"
        )
        try expect(WeatherCondition.title(for: 95) == "雷雨", "weather condition mapping")
        try expect(WeatherCondition.windDirection(135) == "东南", "weather wind direction mapping")
        try expect(
            try JSONDecoder().decode(WeatherSnapshot.self, from: JSONEncoder().encode(weather)) == weather,
            "weather snapshot persistence round trip"
        )
        let metNorwayFixture = Data("""
        {"properties":{"timeseries":[
          {"time":"2026-07-23T02:00:00Z","data":{
            "instant":{"details":{"air_temperature":32.2,"relative_humidity":72.8,"wind_from_direction":194.3,"wind_speed":3.0}},
            "next_1_hours":{"summary":{"symbol_code":"partlycloudy_day"},"details":{"precipitation_amount":0.1,"probability_of_precipitation":20.0}}
          }},
          {"time":"2026-07-23T03:00:00Z","data":{
            "instant":{"details":{"air_temperature":33.0,"relative_humidity":68.0,"wind_from_direction":190.0,"wind_speed":4.0}},
            "next_1_hours":{"summary":{"symbol_code":"rainshowers_day"},"details":{"precipitation_amount":0.8,"probability_of_precipitation":70.0}}
          }},
          {"time":"2026-07-23T16:00:00Z","data":{
            "instant":{"details":{"air_temperature":27.0,"relative_humidity":85.0,"wind_from_direction":160.0,"wind_speed":2.0}},
            "next_1_hours":{"summary":{"symbol_code":"clearsky_night"},"details":{"precipitation_amount":0.0,"probability_of_precipitation":0.0}}
          }}
        ]}}
        """.utf8)
        let metWeather = try METNorwayWeatherService.parse(data: metNorwayFixture, location: shanghai)
        try expect(
            metWeather.current.temperature == 32.2
                && abs(metWeather.current.windSpeed - 10.8) < 0.001
                && metWeather.hourly.map(\.weatherCode) == [2, 80, 0]
                && metWeather.daily.count == 2,
            "MET Norway response converts UTC, units and symbols into Luma weather models"
        )
        try expect(
            METNorwayWeatherService.weatherCode(for: "heavyrainandthunder_day") == 95
                && METNorwayWeatherService.weatherCode(for: "snowshowers_night") == 85,
            "MET Norway symbols map to WMO weather codes"
        )
        let cmaFixture = Data("""
        {"code":0,"data":{
          "daily":[
            {"date":"2026/07/23","high":36.0,"low":28.0,"dayCode":2},
            {"date":"2026/07/24","high":35.0,"low":27.0,"dayCode":7}
          ],
          "now":{"precipitation":0.1,"temperature":33.0,"humidity":69.0,"windDirectionDegree":86.0,"windSpeed":1.1,"feelst":38.8},
          "lastUpdate":"2026/07/23 10:00"
        }}
        """.utf8)
        let cmaWeather = try CMAWeatherService.parse(data: cmaFixture, location: shanghai)
        try expect(
            cmaWeather.current.temperature == 33
                && cmaWeather.current.apparentTemperature == 38.8
                && cmaWeather.current.weatherCode == 3
                && cmaWeather.hourly.isEmpty
                && cmaWeather.daily.map(\.weatherCode) == [3, 61]
                && cmaWeather.daily.allSatisfy { $0.precipitationProbability == nil },
            "China Meteorological Administration response parsing"
        )
        let nmcFixture = Data("""
        {"code":0,"data":{
          "real":{
            "publish_time":"2026-07-23 10:00",
            "weather":{"temperature":33.0,"humidity":69.0,"rain":0.0,"img":"1","feelst":38.8},
            "wind":{"degree":86.0,"speed":1.1},
            "sunriseSunset":{"sunrise":"2026-07-23 05:05","sunset":"2026-07-23 18:56"}
          },
          "predict":{"detail":[
            {"date":"2026-07-23","day":{"weather":{"img":"2","temperature":"36"}},"night":{"weather":{"img":"2","temperature":"28"}}},
            {"date":"2026-07-24","day":{"weather":{"img":"7","temperature":"35"}},"night":{"weather":{"img":"1","temperature":"27"}}}
          ]}
        }}
        """.utf8)
        let nmcWeather = try NMCWeatherService.parse(data: nmcFixture, location: shanghai)
        try expect(
            nmcWeather.current.weatherCode == 2
                && abs(nmcWeather.current.windSpeed - 3.96) < 0.001
                && nmcWeather.hourly.isEmpty
                && nmcWeather.daily.map(\.weatherCode) == [3, 61]
                && nmcWeather.daily.first?.sunrise == "2026-07-23 05:05",
            "National Meteorological Center response parsing"
        )
        try expect(
            WeatherDataSource.allCases.map(\.title) == ["自动", "Open-Meteo", "MET Norway", "中国气象局", "中央气象台"]
                && ChinaWeatherCodeMapper.wmoCode(4) == 95
                && ChinaWeatherCodeMapper.wmoCode(8) == 63,
            "weather settings exposes automatic fallback, two global and two Chinese free data sources"
        )

        let weatherSuiteName = "app.luma.weather-tests." + UUID().uuidString
        let weatherDefaults = UserDefaults(suiteName: weatherSuiteName)!
        weatherDefaults.removePersistentDomain(forName: weatherSuiteName)
        defer { weatherDefaults.removePersistentDomain(forName: weatherSuiteName) }
        let weatherStore = WeatherStore(
            defaults: weatherDefaults,
            adder: { query in
                try expect(query == "上海", "weather location query is trimmed")
                return weather
            }
        )
        await weatherStore.add("  上海  ")
        weatherStore.setDataSource(.nationalMeteorologicalCenter)
        try expect(
            weatherStore.records == [weather] && weatherStore.selectedLocationID == weather.id,
            "weather location add selects and persists the record"
        )
        let restoredWeatherStore = WeatherStore(defaults: weatherDefaults)
        try expect(
            restoredWeatherStore.records == [weather] && restoredWeatherStore.dataSource == .nationalMeteorologicalCenter,
            "weather saved locations and selected data source restore after relaunch"
        )

        let secondLocation = WeatherLocation(
            id: 1850147,
            name: "东京",
            admin1: "东京都",
            country: "日本",
            latitude: 35.6895,
            longitude: 139.6917,
            timezone: "Asia/Tokyo"
        )
        let tokyoWeather = WeatherSnapshot(
            location: secondLocation,
            current: weather.current,
            hourly: weather.hourly,
            daily: weather.daily,
            fetchedAt: weather.fetchedAt
        )
        var refreshedWeatherIDs: [Int] = []
        let refreshingWeatherStore = WeatherStore(
            records: [weather, tokyoWeather],
            defaults: weatherDefaults,
            fetcher: { location in
                refreshedWeatherIDs.append(location.id)
                return WeatherSnapshot(
                    location: location,
                    current: CurrentWeather(
                        time: weather.current.time,
                        temperature: weather.current.temperature + 1,
                        apparentTemperature: weather.current.apparentTemperature,
                        humidity: weather.current.humidity,
                        precipitation: weather.current.precipitation,
                        weatherCode: weather.current.weatherCode,
                        windSpeed: weather.current.windSpeed,
                        windDirection: weather.current.windDirection,
                        isDay: weather.current.isDay
                    ),
                    hourly: weather.hourly,
                    daily: weather.daily,
                    fetchedAt: Date()
                )
            }
        )
        await refreshingWeatherStore.refreshAll()
        try expect(
            refreshedWeatherIDs == [weather.id, tokyoWeather.id]
                && refreshingWeatherStore.records.allSatisfy { $0.current.temperature == 34.2 },
            "refresh all weather locations updates every saved location"
        )

        let linkEntry = ClipboardEntry(payload: .link(URL(string: "https://example.com")!))
        try expect(linkEntry.kind == .link && linkEntry.title == "https://example.com", "clipboard link classification")
        let fileEntry = ClipboardEntry(payload: .files([URL(fileURLWithPath: "/tmp/Luma.png")]))
        try expect(fileEntry.kind == .file && fileEntry.title == "Luma.png", "clipboard file classification")
        let imageEntry = ClipboardEntry(payload: .image(ClipboardImage(data: Data([0x89, 0x50, 0x4E, 0x47]))))
        try expect(imageEntry.kind == .image, "clipboard image classification")
        let plainEntry = ClipboardEntry(payload: .text("temporary"))
        let clipboard = ClipboardMonitor(entries: [linkEntry, plainEntry])
        clipboard.toggleFavorite(linkEntry)
        try expect(clipboard.filteredEntries(.favorites).count == 1, "clipboard favorites filter")
        clipboard.clearHistory()
        try expect(clipboard.entries == [ClipboardEntry(id: linkEntry.id, payload: linkEntry.payload, copiedAt: linkEntry.copiedAt, isFavorite: true)], "clipboard clear preserves favorites")

        try expect(
            ClipboardPasteShortcut.keyCode == CGKeyCode(kVK_ANSI_V)
                && ClipboardPasteShortcut.eventFlags == .maskCommand,
            "clipboard double-click emits Command-V to the previous application"
        )
        let linkPasteboard = NSPasteboard(
            name: NSPasteboard.Name("app.luma.tests.link-paste." + UUID().uuidString)
        )
        linkPasteboard.clearContents()
        ClipboardMonitor.write(linkEntry.payload, to: linkPasteboard)
        try expect(
            linkPasteboard.string(forType: .URL) == "https://example.com"
                && linkPasteboard.string(forType: .string) == "https://example.com",
            "clipboard links expose both URL and plain-text pasteboard representations"
        )
        try expect(
            ClipboardKeyboardNavigation.movedSelection(
                current: plainEntry.id,
                entries: [plainEntry, linkEntry],
                delta: 1
            ) == linkEntry.id,
            "clipboard down arrow selects the next entry"
        )
        try expect(
            ClipboardKeyboardNavigation.movedSelection(
                current: linkEntry.id,
                entries: [plainEntry, linkEntry],
                delta: 1
            ) == plainEntry.id,
            "clipboard selection wraps after the last entry"
        )
        try expect(
            ClipboardKeyboardNavigation.movedFilter(current: .all, delta: -1) == .link
                && ClipboardKeyboardNavigation.movedFilter(current: .all, delta: 1) == .favorites,
            "clipboard left and right arrows switch filters"
        )
        let longClipboardEntries = (0..<500).map {
            ClipboardEntry(payload: .text("entry-\($0)"))
        }
        var restoredSelection = ClipboardSelectionState(
            selectedID: longClipboardEntries[347].id
        )
        restoredSelection.reset()
        try expect(
            restoredSelection.move(in: longClipboardEntries, delta: 1)
                == longClipboardEntries.first?.id,
            "re-entering clipboard clears a reused middle selection so the first down arrow selects the first entry"
        )
        restoredSelection.select(longClipboardEntries[23].id)
        try expect(
            restoredSelection.selectedID == longClipboardEntries[23].id,
            "single-click selection updates the clipboard selection state"
        )
        let firstCopyDate = Date(timeIntervalSince1970: 100)
        let latestCopyDate = Date(timeIntervalSince1970: 300)
        let repeatedText = ClipboardEntry(
            payload: .text("deduplicated text"),
            copiedAt: firstCopyDate,
            isFavorite: true
        )
        let interveningText = ClipboardEntry(
            payload: .text("another value"),
            copiedAt: Date(timeIntervalSince1970: 200)
        )
        let deduplicatedTextHistory = ClipboardHistory.inserting(
            .text("deduplicated text"),
            into: [interveningText, repeatedText],
            copiedAt: latestCopyDate
        )
        try expect(
            deduplicatedTextHistory.count == 2
                && deduplicatedTextHistory.first?.payload == repeatedText.payload
                && deduplicatedTextHistory.first?.copiedAt == latestCopyDate
                && deduplicatedTextHistory.first?.isFavorite == true,
            "repeated text moves to the top, refreshes its timestamp, and preserves favorite state"
        )
        let repeatedLink = ClipboardEntry(
            payload: .link(URL(string: "https://example.com/luma")!),
            copiedAt: firstCopyDate
        )
        let deduplicatedLinkHistory = ClipboardHistory.inserting(
            repeatedLink.payload,
            into: [interveningText, repeatedLink],
            copiedAt: latestCopyDate
        )
        try expect(
            deduplicatedLinkHistory.count == 2
                && deduplicatedLinkHistory.first?.payload == repeatedLink.payload
                && deduplicatedLinkHistory.first?.copiedAt == latestCopyDate,
            "repeated links move to the top without creating duplicate history rows"
        )

        _ = NSApplication.shared
        let layoutClipboard = ClipboardMonitor(entries: [plainEntry, linkEntry])
        let filledTopInset = try topVisualInset(
            ClipboardPluginView(clipboard: layoutClipboard, initialFilter: .all)
        )
        let emptyTopInset = try topVisualInset(
            ClipboardPluginView(clipboard: layoutClipboard, initialFilter: .image)
        )
        try expect(
            abs(filledTopInset - emptyTopInset) <= 2,
            "clipboard category layout stays vertically anchored: filled=\(filledTopInset), empty=\(emptyTopInset)"
        )

        let validPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=")!
        var largeValidPNG = validPNG
        largeValidPNG.append(Data(repeating: 0, count: 13 * 1_024 * 1_024))
        let largeImagePasteboard = NSPasteboard(
            name: NSPasteboard.Name("app.luma.tests.large-image." + UUID().uuidString)
        )
        largeImagePasteboard.clearContents()
        largeImagePasteboard.setData(largeValidPNG, forType: .png)
        let capturedLargeImage = ClipboardMonitor.readPayload(from: largeImagePasteboard).map {
            if case .image = $0 { return true }
            return false
        } ?? false
        try expect(
            capturedLargeImage,
            "clipboard captures valid images larger than the previous 12 MB cutoff"
        )
        let expandableImageEntry = ClipboardEntry(payload: .image(ClipboardImage(data: validPNG)))
        let imageClipboard = ClipboardMonitor(entries: [expandableImageEntry])
        let collapsedImageHeight = fittingHeight(
            ClipboardEntryRow(entry: expandableImageEntry, clipboard: imageClipboard),
            width: 650
        )
        let expandedImageHeight = fittingHeight(
            ClipboardEntryRow(entry: expandableImageEntry, clipboard: imageClipboard, initiallyExpanded: true),
            width: 650
        )
        try expect(expandedImageHeight > collapsedImageHeight + 100, "clipboard image expands to page width")

        let pluginSuiteName = "app.luma.plugin-tests." + UUID().uuidString
        let pluginDefaults = UserDefaults(suiteName: pluginSuiteName)!
        pluginDefaults.removePersistentDomain(forName: pluginSuiteName)
        defer { pluginDefaults.removePersistentDomain(forName: pluginSuiteName) }
        let pluginSettings = PluginSettings(defaults: pluginDefaults)
        let nativeBorderlessEditor = BorderlessTextEditor.makeScrollView(text: "Luma", delegate: nil)
        try expect(
            nativeBorderlessEditor.borderType == .noBorder
                && !nativeBorderlessEditor.hasVerticalScroller
                && !nativeBorderlessEditor.hasHorizontalScroller,
            "translation editor exposes only the SwiftUI outer border"
        )
        try expect(
            BorderlessTextEditorCommand.shouldSubmit(
                #selector(NSResponder.insertNewline(_:)),
                modifierFlags: []
            )
                && !BorderlessTextEditorCommand.shouldSubmit(
                    #selector(NSResponder.insertNewline(_:)),
                    modifierFlags: .shift
                ),
            "translation input submits with Return and keeps Shift-Return for a newline"
        )
        let translationPasteboard = NSPasteboard(name: .init("app.luma.translation-tests"))
        translationPasteboard.clearContents()
        translationPasteboard.setString("Hello Luma", forType: .string)
        try expect(
            ClipboardMonitor.plainText(from: translationPasteboard) == "Hello Luma",
            "translation can read plain clipboard text"
        )
        translationPasteboard.clearContents()
        translationPasteboard.writeObjects([
            URL(fileURLWithPath: "/tmp/Luma-translation-test.txt") as NSURL
        ])
        try expect(
            ClipboardMonitor.plainText(from: translationPasteboard) == nil,
            "translation ignores non-text clipboard payloads"
        )
        try expect(
            SettingsSection.allCases.map(\.title) == ["应用设置", "快捷键管理", "插件关键词管理", "剪贴板设置", "AI 管理", "翻译设置", "股票设置", "天气设置"],
            "application settings leads the settings navigation"
        )
        let applicationSuiteName = "app.luma.application-tests." + UUID().uuidString
        let applicationDefaults = UserDefaults(suiteName: applicationSuiteName)!
        applicationDefaults.removePersistentDomain(forName: applicationSuiteName)
        defer { applicationDefaults.removePersistentDomain(forName: applicationSuiteName) }
        let applicationSettings = ApplicationSettings(defaults: applicationDefaults)
        var appliedStatusBarVisibility: Bool?
        applicationSettings.applyHandler = { appliedStatusBarVisibility = $0 }
        applicationSettings.setShowsStatusBarIcon(false)
        try expect(
            applicationSettings.recentSearchDisplayMode == .vertical,
            "recent search display defaults to the existing vertical layout"
        )
        applicationSettings.setRecentSearchDisplayMode(.horizontal)
        let restoredApplicationSettings = ApplicationSettings(defaults: applicationDefaults)
        try expect(
            !applicationSettings.showsStatusBarIcon
                && !restoredApplicationSettings.showsStatusBarIcon
                && appliedStatusBarVisibility == false,
            "status bar icon visibility defaults on, applies immediately, and persists"
        )
        try expect(
            restoredApplicationSettings.recentSearchDisplayMode == .horizontal,
            "recent search display mode persists"
        )
        try expect(
            LumaStatusIcon.image.isTemplate && LumaStatusIcon.image.size == NSSize(width: 18, height: 18),
            "Luma status icon is a native 18-point template image"
        )
        try expect(
            Plugin.allCases.allSatisfy { pluginSettings.isEnabled($0) && pluginSettings.keywords(for: $0) == $0.keywords },
            "plugins start enabled with their default keyword lists"
        )

        let aiSuiteName = "app.luma.ai-tests." + UUID().uuidString
        let aiDefaults = UserDefaults(suiteName: aiSuiteName)!
        aiDefaults.removePersistentDomain(forName: aiSuiteName)
        defer { aiDefaults.removePersistentDomain(forName: aiSuiteName) }
        let secretStore = InMemoryAISecretStore()
        let aiSettings = AISettings(defaults: aiDefaults, secrets: secretStore)
        let deepSeekID = AISettings.deepSeekProviderID
        guard let deepSeek = aiSettings.provider(id: deepSeekID),
              let deepSeekModel = deepSeek.models.first else {
            throw TestFailure("default DeepSeek provider exists")
        }
        try expect(
            deepSeek.baseURL == "https://api.deepseek.com/anthropic"
                && deepSeek.apiFormat == .anthropicMessages
                && deepSeek.models.map(\.name) == ["deepseek-v4-pro", "deepseek-v4-flash"],
            "AI management includes the official DeepSeek Anthropic-compatible defaults"
        )
        aiSettings.updateProvider(id: deepSeekID) { $0.isEnabled = true }
        aiSettings.setAPIKey("sk-secret-not-in-defaults", for: deepSeekID)
        try expect(
            !aiDefaults.dictionaryRepresentation().description.contains("sk-secret-not-in-defaults"),
            "AI API keys are excluded from UserDefaults"
        )

        let anthropicTarget = AIRequestTarget(
            provider: aiSettings.provider(id: deepSeekID)!,
            model: deepSeekModel,
            apiKey: "test-key"
        )
        let anthropicRequest = try AIService.makeRequest(
            systemPrompt: "system",
            userPrompt: "hello",
            target: anthropicTarget
        )
        try expect(
            anthropicRequest.url?.absoluteString == "https://api.deepseek.com/anthropic/v1/messages"
                && anthropicRequest.value(forHTTPHeaderField: "x-api-key") == "test-key"
                && anthropicRequest.value(forHTTPHeaderField: "Authorization") == nil,
            "Anthropic-compatible requests use the correct endpoint and authentication"
        )
        let anthropicFixture = Data(#"{"content":[{"type":"text","text":"你好"}]}"#.utf8)
        try expect(
            try AIService.parseResponse(anthropicFixture, format: .anthropicMessages) == "你好",
            "Anthropic response text parsing"
        )

        guard let byteDance = aiSettings.provider(id: AISettings.byteDanceProviderID),
              let byteDanceModel = byteDance.models.first else {
            throw TestFailure("default ByteDance provider exists")
        }
        let openAITarget = AIRequestTarget(provider: byteDance, model: byteDanceModel, apiKey: "ark-key")
        let openAIRequest = try AIService.makeRequest(
            systemPrompt: "system",
            userPrompt: "hello",
            target: openAITarget
        )
        try expect(
            openAIRequest.url?.absoluteString == "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
                && openAIRequest.value(forHTTPHeaderField: "Authorization") == "Bearer ark-key",
            "OpenAI-compatible requests use the Volcano Ark endpoint and bearer authentication"
        )
        let openAIFixture = Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8)
        try expect(
            try AIService.parseResponse(openAIFixture, format: .openAIChatCompletions) == "你好",
            "OpenAI response text parsing"
        )

        let translationSettings = TranslationSettings(aiSettings: aiSettings, defaults: aiDefaults)
        translationSettings.setBackend(.ai)
        translationSettings.setProvider(deepSeekID)
        translationSettings.setModel(deepSeekModel.id)
        let restoredAISettings = AISettings(defaults: aiDefaults, secrets: secretStore)
        let restoredTranslationSettings = TranslationSettings(aiSettings: restoredAISettings, defaults: aiDefaults)
        try expect(
            restoredTranslationSettings.backend == .ai
                && restoredTranslationSettings.providerID == deepSeekID
                && restoredTranslationSettings.modelID == deepSeekModel.id
                && restoredTranslationSettings.requestTarget?.apiKey == "sk-secret-not-in-defaults",
            "translation AI provider and model selection persist"
        )

        let appFixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaAppIndexTests-" + UUID().uuidString, isDirectory: true)
        let fakeSafari = appFixtureRoot.appendingPathComponent("Safari.app", isDirectory: true)
        let fakeUtilities = appFixtureRoot.appendingPathComponent("Utilities", isDirectory: true)
        let fakeTerminal = fakeUtilities.appendingPathComponent("Terminal.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeSafari, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeTerminal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appFixtureRoot) }
        let scannedApplications = InstalledAppIndex.scan(roots: [appFixtureRoot])
        try expect(
            Set(scannedApplications.map(\.name)) == Set(["Safari", "Terminal"]),
            "installed app index scans top-level and nested macOS apps"
        )
        let installedApps = InstalledAppIndex(applications: scannedApplications)
        let recentSuiteName = "app.luma.recent-tests." + UUID().uuidString
        let recentDefaults = UserDefaults(suiteName: recentSuiteName)!
        recentDefaults.removePersistentDomain(forName: recentSuiteName)
        defer { recentDefaults.removePersistentDomain(forName: recentSuiteName) }
        let recentUsage = RecentUsageStore(defaults: recentDefaults)
        var openedApplicationURL: URL?
        let searchableClipboardText = ClipboardEntry(payload: .text("Luma clipboard searchable invoice 42"))
        let searchableClipboardLink = ClipboardEntry(
            payload: .link(URL(string: "https://example.com/docs/clipboard-searchable")!)
        )
        let searchableClipboardFile = ClipboardEntry(
            payload: .files([URL(fileURLWithPath: "/tmp/Quarterly Clipboard Searchable.pdf")])
        )
        let navigationClipboard = ClipboardMonitor(
            entries: [searchableClipboardText, searchableClipboardLink, searchableClipboardFile]
        )
        let navigationModel = LauncherModel(
            clipboard: navigationClipboard,
            pluginSettings: pluginSettings,
            installedApps: installedApps,
            recentUsage: recentUsage,
            fileSearch: FileSearchIndex(),
            quicklinks: QuicklinkStore(defaults: recentDefaults),
            snippets: SnippetStore(defaults: recentDefaults),
            applicationOpener: { url in
                openedApplicationURL = url
                return true
            }
        )
        navigationModel.prepareForPresentation()
        try expect(navigationModel.presentation == .search && navigationModel.preferredWindowHeight == 58, "launcher opens a thinner search-only panel")
        navigationModel.query = "json"
        try expect(navigationModel.presentation == .results && navigationModel.preferredWindowHeight == 430, "launcher expands for results")
        navigationModel.activateSelected()
        try expect(navigationModel.presentation == .plugin && navigationModel.selectedPlugin == .json, "search opens a single tool")
        try expect(
            navigationModel.preferredWindowHeight == LauncherModel.defaultExpandedWindowHeight
                && LauncherModel.defaultExpandedWindowHeight == 666,
            "plugin and settings pages use the captured default panel height"
        )
        try expect(recentUsage.items.first?.plugin == .json, "opening a plugin records it as recently used")
        navigationModel.returnToSearch()
        try expect(
            navigationModel.recentItems.first?.plugin == .json
                && navigationModel.preferredWindowHeight == CGFloat(96 + navigationModel.recentItems.count * 52),
            "recent plugins appear below the search field and expand the search panel"
        )
        for index in 0..<10 {
            let recentAppURL = appFixtureRoot
                .appendingPathComponent("RecentApp\(index).app", isDirectory: true)
            try FileManager.default.createDirectory(at: recentAppURL, withIntermediateDirectories: true)
            recentUsage.record(
                application: InstalledApplication(
                    url: recentAppURL,
                    name: "Recent App \(index)",
                    bundleIdentifier: "app.luma.recent.\(index)"
                )
            )
        }
        try expect(
            navigationModel.recentItems.count == 9
                && navigationModel.preferredWindowHeight == CGFloat(96 + 9 * 52),
            "search page shows at most nine recent items and fits them without scrolling"
        )
        for index in 10..<20 {
            let recentAppURL = appFixtureRoot
                .appendingPathComponent("RecentApp\(index).app", isDirectory: true)
            try FileManager.default.createDirectory(at: recentAppURL, withIntermediateDirectories: true)
            recentUsage.record(
                application: InstalledApplication(
                    url: recentAppURL,
                    name: "Recent App \(index)",
                    bundleIdentifier: "app.luma.recent.\(index)"
                )
            )
        }
        try expect(
            navigationModel.horizontalRecentItems(of: .application).count == 15
                && navigationModel.recentItems.count == 9,
            "horizontal applications use their own 15-item limit without changing the vertical 9-item limit"
        )
        for plugin in Plugin.allCases {
            recentUsage.record(plugin: plugin)
        }
        try expect(
            navigationModel.horizontalRecentItems(of: .plugin).count == min(15, Plugin.allCases.count)
                && navigationModel.horizontalRecentItems(of: .application).count == 15
                && navigationModel.recentItems.count == 9,
            "horizontal plugins and applications keep independent limits"
        )
        let recentHosting = NSHostingView(
            rootView: RecentItemsView(model: navigationModel, displayMode: .vertical)
                .frame(width: 920, height: navigationModel.preferredWindowHeight - 58)
        )
        recentHosting.layoutSubtreeIfNeeded()
        try expect(!containsScrollView(in: recentHosting), "recent usage fits its content without a scroll container")
        try expect(
            navigationModel.preferredWindowHeight(recentDisplayMode: .horizontal)
                == LauncherModel.horizontalRecentWindowHeight,
            "horizontal recent usage uses a compact two-row panel height"
        )
        let horizontalRecentHosting = NSHostingView(
            rootView: RecentItemsView(model: navigationModel, displayMode: .horizontal)
                .frame(width: 920, height: LauncherModel.horizontalRecentWindowHeight - 58)
        )
        horizontalRecentHosting.layoutSubtreeIfNeeded()
        try expect(
            containsScrollView(in: horizontalRecentHosting),
            "horizontal recent usage keeps plugin and application rows on one scrolling line"
        )
        navigationModel.showSettings()
        try expect(navigationModel.presentation == .settings && navigationModel.selectedPlugin == nil, "settings is a secondary page")
        try expect(
            LauncherKeyboardRouting.handlesEscape(for: .settings)
                && LauncherKeyboardRouting.handlesEscape(for: .plugin)
                && !LauncherKeyboardRouting.handlesEscape(for: .search)
                && !LauncherKeyboardRouting.handlesEscape(for: .results),
            "Escape returns from plugin and settings pages only"
        )
        navigationModel.query = "password"
        try expect(navigationModel.presentation == .results && !navigationModel.isShowingSettings, "typing leaves settings for search")

        navigationModel.returnToSearch()
        let searchBridge = LauncherSearchField(
            text: Binding(get: { navigationModel.query }, set: { navigationModel.query = $0 }),
            focusRequest: 0,
            onSubmit: navigationModel.activateSelected,
            onMove: navigationModel.moveSelection,
            onActions: navigationModel.toggleActions,
            onEscape: { _ = navigationModel.handleEscape() }
        )
        let searchCoordinator = searchBridge.makeCoordinator()
        let nativeSearchField = NSSearchField()
        LauncherSearchField.configure(nativeSearchField, coordinator: searchCoordinator)
        try expect(nativeSearchField.target == nil && nativeSearchField.action == nil, "typing does not install an incremental submit action")
        try expect(
            (nativeSearchField.cell as? NSSearchFieldCell)?.searchButtonCell == nil,
            "search field removes the overlapping native magnifier"
        )
        nativeSearchField.stringValue = "json"
        searchCoordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: nativeSearchField)
        )
        try expect(
            navigationModel.query == "json" && navigationModel.presentation == .results && navigationModel.selectedPlugin == nil,
            "typing only displays matching results"
        )
        _ = searchCoordinator.control(
            nativeSearchField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )
        try expect(
            navigationModel.presentation == .plugin && navigationModel.selectedPlugin == .json,
            "Enter explicitly opens the selected result"
        )
        navigationModel.prepareForPresentation(query: "翻译")
        try expect(
            navigationModel.query.isEmpty && navigationModel.presentation == .plugin && navigationModel.selectedPlugin == .translate,
            "keyword shortcut directly opens its only matching plugin"
        )

        pluginSettings.setEnabled(false, for: .json)
        navigationModel.query = "json"
        try expect(!navigationModel.filteredPlugins.contains(.json), "disabled plugin is removed from search results")
        pluginSettings.setEnabled(true, for: .json)
        pluginSettings.updateKeyword(for: .json, at: 0, value: "amberotter")
        navigationModel.query = "amberotter"
        try expect(navigationModel.filteredPlugins == [.json], "modified default plugin keyword participates in search")
        let customKeywordIndex = pluginSettings.addKeyword(to: .json)
        pluginSettings.updateKeyword(for: .json, at: customKeywordIndex, value: "rainbowfish")
        navigationModel.query = "rainbowfish"
        try expect(navigationModel.filteredPlugins == [.json], "new plugin keyword participates in search")
        pluginSettings.updateKeyword(for: .json, at: customKeywordIndex, value: "structuredfish")
        navigationModel.query = "structuredfish"
        try expect(navigationModel.filteredPlugins == [.json], "modified plugin keyword participates in search")
        let restoredPluginSettings = PluginSettings(defaults: pluginDefaults)
        try expect(
            restoredPluginSettings.isEnabled(.json)
                && restoredPluginSettings.keywords(for: .json).first == "amberotter"
                && restoredPluginSettings.keywords(for: .json).last == "structuredfish",
            "plugin enabled state and keyword edits persist"
        )

        navigationModel.prepareForPresentation(query: "Terminal")
        try expect(
            navigationModel.filteredApplications.map(\.name) == ["Terminal"]
                && navigationModel.filteredPlugins.isEmpty,
            "local macOS apps appear in launcher search results"
        )
        navigationModel.activateSelected()
        try expect(
            openedApplicationURL?.resolvingSymlinksInPath().path == fakeTerminal.resolvingSymlinksInPath().path,
            "Enter launches the selected macOS app"
        )
        navigationModel.query = "quarterly searchable"
        try expect(
            navigationModel.filteredPlugins.isEmpty && navigationModel.filteredApplications.isEmpty,
            "launcher search excludes clipboard contents"
        )
        navigationModel.activateSelected()
        try expect(
            navigationModel.selectedPlugin == nil,
            "Enter does nothing when only clipboard content matches globally"
        )
        try expect(
            navigationClipboard.filteredEntries(.all, matching: "quarterly searchable").map(\.id)
                == [searchableClipboardFile.id],
            "clipboard plugin searches multiple terms in file names and paths"
        )
        try expect(
            navigationClipboard.filteredEntries(.link, matching: "clipboard-searchable").map(\.id)
                == [searchableClipboardLink.id],
            "clipboard plugin searches link contents within the selected type"
        )
        try expect(
            navigationClipboard.filteredEntries(.text, matching: "invoice 42").map(\.id)
                == [searchableClipboardText.id],
            "clipboard plugin searches text contents within the selected type"
        )
        try expect(
            recentUsage.items.first?.application?.url.resolvingSymlinksInPath().path
                == fakeTerminal.resolvingSymlinksInPath().path,
            "opening a macOS app moves it to the top of recent usage"
        )
        let restoredRecentUsage = RecentUsageStore(defaults: recentDefaults)
        try expect(
            restoredRecentUsage.items.first?.application?.name == "Terminal"
                && restoredRecentUsage.items.contains(where: { $0.plugin == .json }),
            "recent plugins and apps persist locally"
        )

        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        var windowPlacement = LauncherWindowPlacement()
        let capturedScreenVisibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1255)
        let capturedDefaultFrame = windowPlacement.frame(
            width: 920,
            height: 58,
            heightContext: .search,
            visibleFrame: capturedScreenVisibleFrame
        )
        try expect(
            abs(capturedDefaultFrame.minX - 567) < 1
                && abs(capturedDefaultFrame.maxY - 1034) < 1,
            "launcher defaults to the user-selected current position"
        )
        let defaultWindowFrame = windowPlacement.frame(
            width: 920,
            height: 58,
            heightContext: .search,
            visibleFrame: visibleFrame
        )
        try expect(
            visibleFrame.contains(defaultWindowFrame) && defaultWindowFrame.maxY > visibleFrame.midY,
            "responsive default launcher position stays visible and above center"
        )

        let controlPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        LauncherPanelAppearance.hideWindowControls(in: controlPanel)
        try expect(
            [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy {
                controlPanel.standardWindowButton($0)?.isHidden == true
            },
            "launcher hides all three title-bar window controls"
        )
        let draggedFrame = NSRect(x: 86, y: 620, width: 920, height: 58)
        windowPlacement.remember(frame: draggedFrame, visibleFrame: visibleFrame)
        let expandedAtDraggedPosition = windowPlacement.frame(
            width: 920,
            height: 600,
            heightContext: .settings,
            visibleFrame: visibleFrame
        )
        try expect(
            expandedAtDraggedPosition.minX == draggedFrame.minX
                && expandedAtDraggedPosition.maxY == draggedFrame.maxY,
            "runtime window position keeps its top-left anchor while expanding"
        )
        let secondaryVisibleFrame = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let secondaryDefaultFrame = windowPlacement.frame(
            width: 920,
            height: 600,
            heightContext: .settings,
            visibleFrame: secondaryVisibleFrame
        )
        try expect(
            secondaryVisibleFrame.contains(secondaryDefaultFrame)
                && secondaryDefaultFrame.minX != draggedFrame.minX,
            "each display starts from its own responsive default position"
        )
        let secondaryDraggedFrame = NSRect(x: 1650, y: 380, width: 920, height: 600)
        windowPlacement.remember(
            frame: secondaryDraggedFrame,
            visibleFrame: secondaryVisibleFrame
        )
        let reopenedSecondaryFrame = windowPlacement.frame(
            width: 920,
            height: 500,
            heightContext: .plugin(Plugin.translate.rawValue),
            visibleFrame: secondaryVisibleFrame
        )
        let reopenedPrimaryFrame = windowPlacement.frame(
            width: 920,
            height: 500,
            heightContext: .plugin(Plugin.translate.rawValue),
            visibleFrame: visibleFrame
        )
        try expect(
            reopenedSecondaryFrame.minX == secondaryDraggedFrame.minX
                && reopenedSecondaryFrame.maxY == secondaryDraggedFrame.maxY
                && reopenedPrimaryFrame.minX == draggedFrame.minX
                && reopenedPrimaryFrame.maxY == draggedFrame.maxY,
            "runtime launcher position is remembered independently for every display"
        )
        let displayBounds: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1440, height: 900),
            2: CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        ]
        try expect(
            FocusedDisplayResolver.bestDisplayID(
                for: CGRect(x: 1600, y: 120, width: 900, height: 700),
                displayBounds: displayBounds
            ) == 2,
            "focused application window resolves to the display with the largest overlap"
        )
        let userResizedFrame = NSRect(x: 86, y: 300, width: 920, height: 420)
        windowPlacement.rememberHeight(userResizedFrame.height, for: .plugin(Plugin.json.rawValue))
        let reopenedAtRememberedHeight = windowPlacement.frame(
            width: 920,
            height: 58,
            heightContext: .plugin(Plugin.json.rawValue),
            visibleFrame: visibleFrame
        )
        try expect(
            reopenedAtRememberedHeight.height == userResizedFrame.height,
            "launcher remembers the user-adjusted plugin height during the current run"
        )
        let independentSettingsFrame = windowPlacement.frame(
            width: 920,
            height: LauncherModel.defaultExpandedWindowHeight,
            heightContext: .settings,
            visibleFrame: visibleFrame
        )
        let independentOtherPluginFrame = windowPlacement.frame(
            width: 920,
            height: LauncherModel.defaultExpandedWindowHeight,
            heightContext: .plugin(Plugin.translate.rawValue),
            visibleFrame: visibleFrame
        )
        let independentSearchFrame = windowPlacement.frame(
            width: 920,
            height: defaultWindowFrame.height,
            heightContext: .search,
            visibleFrame: visibleFrame
        )
        try expect(
            independentSettingsFrame.height == LauncherModel.defaultExpandedWindowHeight
                && independentOtherPluginFrame.height == LauncherModel.defaultExpandedWindowHeight
                && independentSearchFrame.height == defaultWindowFrame.height,
            "search, settings, and every plugin keep independent runtime heights"
        )
        let placementAfterRelaunch = LauncherWindowPlacement()
        try expect(
            placementAfterRelaunch.frame(
                width: 920,
                height: 58,
                heightContext: .search,
                visibleFrame: visibleFrame
            ) == defaultWindowFrame,
            "window position resets after relaunch"
        )

        let shortcutSuiteName = "app.luma.shortcut-tests." + UUID().uuidString
        let shortcutDefaults = UserDefaults(suiteName: shortcutSuiteName)!
        shortcutDefaults.removePersistentDomain(forName: shortcutSuiteName)
        defer { shortcutDefaults.removePersistentDomain(forName: shortcutSuiteName) }
        let shortcutSettings = ShortcutSettings(defaults: shortcutDefaults)
        try expect(shortcutSettings.shortcut == .default && shortcutSettings.shortcut.displayString == "⌥ Space", "default global shortcut")
        let customShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey | optionKey)
        )
        shortcutSettings.applyHandler = { _ in false }
        shortcutSettings.bind(customShortcut)
        try expect(shortcutSettings.shortcut == .default && shortcutSettings.errorMessage != nil, "occupied shortcut is rejected")
        shortcutSettings.applyHandler = { _ in true }
        shortcutSettings.bind(customShortcut)
        let restoredShortcutSettings = ShortcutSettings(defaults: shortcutDefaults)
        try expect(restoredShortcutSettings.shortcut == customShortcut && customShortcut.displayString == "⌥⌘J", "shortcut persists")

        shortcutSettings.keywordApplyHandler = { _, _, _ in true }
        let jsonBindingID = shortcutSettings.addKeywordBinding()
        shortcutSettings.updateKeyword(id: jsonBindingID, keyword: "json")
        let jsonShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(controlKey | optionKey)
        )
        shortcutSettings.bindKeywordShortcut(id: jsonBindingID, shortcut: jsonShortcut)
        let clipboardBindingID = shortcutSettings.addKeywordBinding()
        shortcutSettings.updateKeyword(id: clipboardBindingID, keyword: "剪贴板")
        let clipboardShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey)
        )
        shortcutSettings.bindKeywordShortcut(id: clipboardBindingID, shortcut: clipboardShortcut)
        let restoredKeywordSettings = ShortcutSettings(defaults: shortcutDefaults)
        try expect(
            restoredKeywordSettings.keywordBindings == [
                KeywordShortcutBinding(id: jsonBindingID, keyword: "json", shortcut: jsonShortcut),
                KeywordShortcutBinding(id: clipboardBindingID, keyword: "剪贴板", shortcut: clipboardShortcut)
            ],
            "multiple keyword shortcut bindings persist independently"
        )
        shortcutSettings.keywordApplyHandler = { _, _, _ in false }
        let rejectedShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey)
        )
        shortcutSettings.bindKeywordShortcut(id: jsonBindingID, shortcut: rejectedShortcut)
        try expect(
            shortcutSettings.keywordBindings.first(where: { $0.id == jsonBindingID })?.shortcut == jsonShortcut
                && shortcutSettings.keywordErrorIDs.contains(jsonBindingID),
            "occupied keyword shortcut keeps its previous binding"
        )

        let testSuiteName = "app.luma.tests." + UUID().uuidString
        let testSettings = UserDefaults(suiteName: testSuiteName)!
        testSettings.removePersistentDomain(forName: testSuiteName)
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaClipboardTests-" + UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: storageDirectory)
            testSettings.removePersistentDomain(forName: testSuiteName)
        }
        let clipboardStorage = ClipboardStorage(directory: storageDirectory)
        let persistedEntries = [
            ClipboardEntry(payload: .text("persistent text")),
            ClipboardEntry(payload: .link(URL(string: "https://openai.com")!), isFavorite: true),
            ClipboardEntry(payload: .files([URL(fileURLWithPath: "/tmp/persistent.txt")])),
            ClipboardEntry(payload: .image(ClipboardImage(data: Data([1, 2, 3, 4]))))
        ]
        clipboardStorage.save(persistedEntries)
        let reloadedEntries = clipboardStorage.load()
        try expect(reloadedEntries.count == 4, "clipboard storage round trip")
        try expect(Set(reloadedEntries.map(\.kind)) == Set(ClipboardKind.allCases), "all clipboard kinds persisted")
        if let persistedImage = reloadedEntries.first(where: { $0.kind == .image }),
           case .image(let imageReference) = persistedImage.payload {
            try expect(imageReference.inlineData == nil && imageReference.fileURL != nil, "persisted image loads lazily")
        } else {
            throw TestFailure("persisted image reference")
        }
        let dedupDirectory = storageDirectory.appendingPathComponent("Deduplicated", isDirectory: true)
        let dedupStorage = ClipboardStorage(directory: dedupDirectory)
        let duplicateImageData = Data([1, 3, 3, 7])
        dedupStorage.save([
            ClipboardEntry(payload: .image(ClipboardImage(data: duplicateImageData))),
            ClipboardEntry(payload: .image(ClipboardImage(data: duplicateImageData)))
        ])
        let deduplicatedEntries = dedupStorage.load()
        let deduplicatedURLs = deduplicatedEntries.compactMap { entry -> URL? in
            guard case .image(let image) = entry.payload else { return nil }
            return image.fileURL
        }
        try expect(
            deduplicatedEntries.count == 2 && Set(deduplicatedURLs).count == 1,
            "identical clipboard images share one content-addressed file"
        )

        let firstLargeImage = storageDirectory.appendingPathComponent("first-large.image")
        let secondLargeImage = storageDirectory.appendingPathComponent("second-large.image")
        FileManager.default.createFile(atPath: firstLargeImage.path, contents: nil)
        FileManager.default.createFile(atPath: secondLargeImage.path, contents: nil)
        let sparseImageBytes = UInt64(60 * 1_024 * 1_024)
        let firstHandle = try FileHandle(forWritingTo: firstLargeImage)
        try firstHandle.truncate(atOffset: sparseImageBytes)
        try firstHandle.close()
        let secondHandle = try FileHandle(forWritingTo: secondLargeImage)
        try secondHandle.truncate(atOffset: sparseImageBytes)
        try secondHandle.close()
        let newestLargeImage = ClipboardEntry(
            payload: .image(ClipboardImage(fileURL: firstLargeImage))
        )
        let olderLargeImage = ClipboardEntry(
            payload: .image(ClipboardImage(fileURL: secondLargeImage))
        )
        try expect(
            ClipboardMonitor.enforcingStorageLimit(
                on: [newestLargeImage, olderLargeImage],
                limit: .oneHundredMB
            ) == [newestLargeImage],
            "clipboard image limit keeps the newest unfavorited images within budget"
        )
        let diskBackedMonitor = ClipboardMonitor(storage: clipboardStorage, settings: testSettings)
        if let fileToRemove = diskBackedMonitor.entries.first(where: { $0.kind == .file }) {
            diskBackedMonitor.remove(fileToRemove)
        }
        diskBackedMonitor.flushPersistence()
        let relaunchedMonitor = ClipboardMonitor(storage: clipboardStorage, settings: testSettings)
        try expect(relaunchedMonitor.entries.count == 3 && !relaunchedMonitor.entries.contains(where: { $0.kind == .file }), "clipboard monitor relaunch persistence")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
        let fourMonthsAgo = calendar.date(byAdding: .month, value: -4, to: now)!
        let recentEntry = ClipboardEntry(payload: .text("recent"), copiedAt: twoMonthsAgo)
        let expiredEntry = ClipboardEntry(payload: .text("expired"), copiedAt: fourMonthsAgo)
        let oldFavorite = ClipboardEntry(payload: .text("favorite"), copiedAt: fourMonthsAgo, isFavorite: true)
        let retentionMonitor = ClipboardMonitor(
            entries: [recentEntry, expiredEntry, oldFavorite],
            settings: testSettings,
            retentionPeriod: .threeMonths,
            referenceDate: now
        )
        try expect(retentionMonitor.entries.map(\.title).sorted() == ["favorite", "recent"], "three-month retention with favorite exemption")
        try expect(ClipboardRetentionPeriod.allCases.count == 6, "all retention choices")
        let retentionExpectations: [(ClipboardRetentionPeriod, DateComponents)] = [
            (.threeDays, DateComponents(day: -3)),
            (.sevenDays, DateComponents(day: -7)),
            (.oneMonth, DateComponents(month: -1)),
            (.threeMonths, DateComponents(month: -3)),
            (.sixMonths, DateComponents(month: -6)),
            (.oneYear, DateComponents(year: -1))
        ]
        for (period, components) in retentionExpectations {
            try expect(
                period.cutoffDate(from: now, calendar: calendar) == calendar.date(byAdding: components, to: now),
                "retention cutoff " + period.rawValue
            )
        }

        let defaultRetention = ClipboardMonitor(entries: [], settings: testSettings)
        try expect(
            defaultRetention.retentionPeriod == .threeMonths
                && defaultRetention.storageLimit == .fiveHundredMB,
            "default clipboard retention and storage limit"
        )
        defaultRetention.updateRetentionPeriod(.sevenDays, referenceDate: now)
        defaultRetention.updateStorageLimit(.twoHundredFiftyMB)
        let restoredSetting = ClipboardMonitor(entries: [], settings: testSettings)
        try expect(
            restoredSetting.retentionPeriod == .sevenDays
                && restoredSetting.storageLimit == .twoHundredFiftyMB,
            "clipboard retention and storage settings persisted"
        )
        let shortenedRetention = ClipboardMonitor(
            entries: [recentEntry, oldFavorite],
            settings: testSettings,
            retentionPeriod: .threeMonths,
            referenceDate: now
        )
        shortenedRetention.updateRetentionPeriod(.oneMonth, referenceDate: now)
        try expect(shortenedRetention.entries == [oldFavorite], "shorter retention purges immediately")

    }

    private func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw TestFailure(name) }
    }

    private func topVisualInset<V: View>(_ view: V) throws -> Int {
        let width = 715
        let height = 423
        let root = view
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw TestFailure("clipboard layout bitmap")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        for topInset in 0..<height {
            let y = topInset
            for x in stride(from: 8, to: width - 8, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if color.alphaComponent > 0.5 && luminance < 0.72 {
                    return topInset
                }
            }
        }
        throw TestFailure("clipboard layout has no visible content")
    }

    private func fittingHeight<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    private func containsScrollView(in view: NSView) -> Bool {
        if view is NSScrollView { return true }
        return view.subviews.contains(where: containsScrollView(in:))
    }
}

struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { "Core test failed: \(message)" }
}
