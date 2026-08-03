import Foundation
import Testing

@testable import Luma

@Suite(.serialized)
struct RefreshPerformanceTests {
    @Test
    @MainActor
    func stockQuoteRefreshDoesNotWaitForFundamentals() async throws {
        let suiteName = "app.luma.stock-refresh-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var cached = stockSnapshot(price: 10)
        cached.totalMarketValue = 100
        let quote = stockSnapshot(price: 11)
        let fundamentalsStarted = AsyncGate()
        let releaseFundamentals = AsyncGate()
        let quoteRefreshFinished = AsyncFlag()
        let store = StockStore(
            records: [cached],
            defaults: defaults,
            fetcher: { _ in quote },
            fundamentalsFetcher: { _ in
                await fundamentalsStarted.open()
                await releaseFundamentals.wait()
                return StockFundamentals(
                    totalMarketValue: 200,
                    circulatingMarketValue: 150,
                    priceEarningsRatio: 12,
                    industry: "测试行业"
                )
            }
        )

        let refreshTask = Task { @MainActor in
            await store.refreshAll()
            await quoteRefreshFinished.set()
        }
        await fundamentalsStarted.wait()
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await quoteRefreshFinished.value)
        #expect(store.selected?.price == 11)
        #expect(store.selected?.totalMarketValue == 100)

        await releaseFundamentals.open()
        await refreshTask.value
        for _ in 0..<50 where store.selected?.totalMarketValue != 200 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(store.selected?.totalMarketValue == 200)
        #expect(store.selected?.industry == "测试行业")
    }

    @Test
    func weatherFallbackHedgesAStalledPrimarySource() async throws {
        let location = WeatherLocation(
            id: 1,
            name: "上海",
            admin1: "上海市",
            country: "中国",
            latitude: 31.22222,
            longitude: 121.45806,
            timezone: "Asia/Shanghai"
        )
        let fallback = weatherSnapshot(location: location, temperature: 31)
        let start = Date()

        let result = try await WeatherStore.fetchAutomaticSnapshot(
            location,
            candidates: [.openMeteo, .metNorway],
            hedgeDelayNanoseconds: 20_000_000
        ) { _, source in
            if source == .openMeteo {
                try await Task.sleep(nanoseconds: 300_000_000)
                throw WeatherServiceError.invalidResponse
            }
            return fallback
        }

        #expect(result == fallback)
        #expect(Date().timeIntervalSince(start) < 0.15)

        let fastFailureStart = Date()
        let fastFailureResult = try await WeatherStore.fetchAutomaticSnapshot(
            location,
            candidates: [.openMeteo, .metNorway],
            hedgeDelayNanoseconds: 1_000_000_000
        ) { _, source in
            if source == .openMeteo { throw WeatherServiceError.invalidResponse }
            return fallback
        }
        #expect(fastFailureResult == fallback)
        #expect(Date().timeIntervalSince(fastFailureStart) < 0.15)
    }

    private func stockSnapshot(price: Double) -> StockSnapshot {
        StockSnapshot(
            symbol: "600115.SS",
            providerCode: "sh600115",
            name: "中国东航",
            marketName: "上海",
            currency: "CNY",
            price: price,
            change: 0.1,
            changePercent: 1,
            previousClose: price - 0.1,
            open: price - 0.1,
            high: price,
            low: price - 0.2,
            volume: 1_000,
            quoteTime: "20260803094000",
            points: [],
            fetchedAt: Date()
        )
    }

    private func weatherSnapshot(location: WeatherLocation, temperature: Double) -> WeatherSnapshot {
        WeatherSnapshot(
            location: location,
            current: CurrentWeather(
                time: "2026-08-03T10:00",
                temperature: temperature,
                apparentTemperature: temperature,
                humidity: 70,
                precipitation: 0,
                weatherCode: 1,
                windSpeed: 5,
                windDirection: 180,
                isDay: true
            ),
            hourly: [],
            daily: [],
            fetchedAt: Date()
        )
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private actor AsyncFlag {
    private(set) var value = false

    func set() {
        value = true
    }
}
