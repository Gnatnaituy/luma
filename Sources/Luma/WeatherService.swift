import Combine
import Foundation

struct WeatherLocation: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let admin1: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timezone: String

    var subtitle: String {
        var parts: [String] = []
        if !admin1.isEmpty, admin1 != name { parts.append(admin1) }
        if !country.isEmpty, country != admin1 { parts.append(country) }
        return parts.joined(separator: " · ")
    }
}

struct CurrentWeather: Codable, Equatable {
    let time: String
    let temperature: Double
    let apparentTemperature: Double
    let humidity: Int
    let precipitation: Double
    let weatherCode: Int
    let windSpeed: Double
    let windDirection: Int
    let isDay: Bool
}

struct HourlyWeather: Codable, Equatable, Identifiable {
    let time: String
    let temperature: Double
    let precipitationProbability: Int?
    let weatherCode: Int

    var id: String { time }
}

struct DailyWeather: Codable, Equatable, Identifiable {
    let date: String
    let weatherCode: Int
    let maximumTemperature: Double
    let minimumTemperature: Double
    let precipitationProbability: Int?
    let sunrise: String
    let sunset: String
    let maximumWindSpeed: Double

    var id: String { date }
}

struct WeatherSnapshot: Codable, Equatable, Identifiable {
    let location: WeatherLocation
    let current: CurrentWeather
    let hourly: [HourlyWeather]
    let daily: [DailyWeather]
    let fetchedAt: Date

    var id: Int { location.id }
}

enum WeatherDataSource: String, CaseIterable, Codable, Identifiable {
    case openMeteo
    case metNorway
    case chinaMeteorologicalAdministration
    case nationalMeteorologicalCenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openMeteo: "Open-Meteo"
        case .metNorway: "MET Norway"
        case .chinaMeteorologicalAdministration: "中国气象局"
        case .nationalMeteorologicalCenter: "中央气象台"
        }
    }

    var subtitle: String {
        switch self {
        case .openMeteo: "免密钥，全球覆盖，提供当前、逐小时与七日聚合预报"
        case .metNorway: "挪威气象研究所官方接口，免密钥，提供全球未来约九日预报"
        case .chinaMeteorologicalAdministration: "中国气象局官方气象站实况与七日预报，仅支持中国境内"
        case .nationalMeteorologicalCenter: "国家气象中心官方站点实况与七日预报，仅支持中国境内"
        }
    }
}

enum WeatherCondition {
    static func title(for code: Int) -> String {
        switch code {
        case 0: "晴"
        case 1: "大部晴朗"
        case 2: "局部多云"
        case 3: "阴"
        case 45, 48: "雾"
        case 51, 53, 55, 56, 57: "毛毛雨"
        case 61, 63, 65, 66, 67: "雨"
        case 71, 73, 75, 77: "雪"
        case 80, 81, 82: "阵雨"
        case 85, 86: "阵雪"
        case 95, 96, 99: "雷雨"
        default: "未知天气"
        }
    }

    static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func windDirection(_ degrees: Int) -> String {
        let labels = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let normalized = (degrees % 360 + 360) % 360
        return labels[Int((Double(normalized) / 45).rounded()) % labels.count]
    }
}

enum WeatherServiceError: LocalizedError {
    case emptyQuery
    case locationNotFound
    case invalidResponse
    case malformedData
    case unsupportedRegion

    var errorDescription: String? {
        switch self {
        case .emptyQuery: "请输入地点名称"
        case .locationNotFound: "没有找到该地点"
        case .invalidResponse: "天气服务暂时不可用"
        case .malformedData: "天气数据格式异常"
        case .unsupportedRegion: "当前天气数据源仅支持中国境内地点"
        }
    }
}

struct OpenMeteoWeatherService {
    func addLocation(_ query: String) async throws -> WeatherSnapshot {
        let location = try await searchLocation(query)
        return try await fetch(location)
    }

    func searchLocation(_ query: String) async throws -> WeatherLocation {
        guard let location = try await searchLocations(query, count: 1).first else {
            throw WeatherServiceError.locationNotFound
        }
        return location
    }

    func searchLocations(_ query: String, count: Int = 8) async throws -> [WeatherLocation] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw WeatherServiceError.emptyQuery }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: value),
            URLQueryItem(name: "count", value: String(min(max(count, 1), 20))),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        let data = try await request(components)
        return try Self.parseLocations(data: data)
    }

    func fetch(_ location: WeatherLocation) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,wind_direction_10m"
            ),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,wind_speed_10m_max"
            ),
            URLQueryItem(name: "timezone", value: location.timezone),
            URLQueryItem(name: "forecast_days", value: "7")
        ]
        let data = try await request(components)
        return try Self.parseForecast(data: data, location: location)
    }

    static func parseLocation(data: Data) throws -> WeatherLocation {
        guard let location = try parseLocations(data: data).first else {
            throw WeatherServiceError.locationNotFound
        }
        return location
    }

    static func parseLocations(data: Data) throws -> [WeatherLocation] {
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (response.results ?? []).map { result in
            WeatherLocation(
                id: result.id,
                name: result.name,
                admin1: result.admin1 ?? "",
                country: result.country ?? "",
                latitude: result.latitude,
                longitude: result.longitude,
                timezone: result.timezone
            )
        }
    }

    static func parseForecast(data: Data, location: WeatherLocation) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let current = CurrentWeather(
            time: response.current.time,
            temperature: response.current.temperature,
            apparentTemperature: response.current.apparentTemperature,
            humidity: response.current.humidity,
            precipitation: response.current.precipitation,
            weatherCode: response.current.weatherCode,
            windSpeed: response.current.windSpeed,
            windDirection: response.current.windDirection,
            isDay: response.current.isDay == 1
        )

        let hourlyCount = [
            response.hourly.time.count,
            response.hourly.temperature.count,
            response.hourly.precipitationProbability.count,
            response.hourly.weatherCode.count
        ].min() ?? 0
        let hourly = (0..<hourlyCount).compactMap { index -> HourlyWeather? in
            guard response.hourly.time[index] >= current.time else { return nil }
            return HourlyWeather(
                time: response.hourly.time[index],
                temperature: response.hourly.temperature[index],
                precipitationProbability: response.hourly.precipitationProbability[index],
                weatherCode: response.hourly.weatherCode[index]
            )
        }.prefix(24)

        let dailyCount = [
            response.daily.time.count,
            response.daily.weatherCode.count,
            response.daily.maximumTemperature.count,
            response.daily.minimumTemperature.count,
            response.daily.precipitationProbability.count,
            response.daily.sunrise.count,
            response.daily.sunset.count,
            response.daily.maximumWindSpeed.count
        ].min() ?? 0
        let daily = (0..<dailyCount).map { index in
            DailyWeather(
                date: response.daily.time[index],
                weatherCode: response.daily.weatherCode[index],
                maximumTemperature: response.daily.maximumTemperature[index],
                minimumTemperature: response.daily.minimumTemperature[index],
                precipitationProbability: response.daily.precipitationProbability[index],
                sunrise: response.daily.sunrise[index],
                sunset: response.daily.sunset[index],
                maximumWindSpeed: response.daily.maximumWindSpeed[index]
            )
        }
        guard !hourly.isEmpty, !daily.isEmpty else { throw WeatherServiceError.malformedData }
        return WeatherSnapshot(
            location: location,
            current: current,
            hourly: Array(hourly),
            daily: daily,
            fetchedAt: Date()
        )
    }

    private func request(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else { throw WeatherServiceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Luma/1.1 (macOS; native Swift)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }
        return data
    }

    private struct GeocodingResponse: Decodable {
        let results: [GeocodingResult]?
    }

    private struct GeocodingResult: Decodable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let timezone: String
        let country: String?
        let admin1: String?
    }

    private struct ForecastResponse: Decodable {
        let current: CurrentResponse
        let hourly: HourlyResponse
        let daily: DailyResponse
    }

    private struct CurrentResponse: Decodable {
        let time: String
        let temperature: Double
        let humidity: Int
        let apparentTemperature: Double
        let isDay: Int
        let precipitation: Double
        let weatherCode: Int
        let windSpeed: Double
        let windDirection: Int

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case isDay = "is_day"
            case precipitation
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
        }
    }

    private struct HourlyResponse: Decodable {
        let time: [String]
        let temperature: [Double]
        let precipitationProbability: [Int]
        let weatherCode: [Int]

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case weatherCode = "weather_code"
        }
    }

    private struct DailyResponse: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let maximumTemperature: [Double]
        let minimumTemperature: [Double]
        let precipitationProbability: [Int]
        let sunrise: [String]
        let sunset: [String]
        let maximumWindSpeed: [Double]

        private enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case maximumTemperature = "temperature_2m_max"
            case minimumTemperature = "temperature_2m_min"
            case precipitationProbability = "precipitation_probability_max"
            case sunrise
            case sunset
            case maximumWindSpeed = "wind_speed_10m_max"
        }
    }
}

struct METNorwayWeatherService {
    func fetch(_ location: WeatherLocation) async throws -> WeatherSnapshot {
        var components = URLComponents(
            string: "https://api.met.no/weatherapi/locationforecast/2.0/complete"
        )!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.4f", location.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.4f", location.longitude))
        ]
        guard let url = components.url else { throw WeatherServiceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Luma/1.1 github.com/Gnatnaituy/luma", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }
        return try Self.parse(data: data, location: location)
    }

    static func parse(data: Data, location: WeatherLocation) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let first = response.properties.timeseries.first else {
            throw WeatherServiceError.malformedData
        }
        let timezone = TimeZone(identifier: location.timezone) ?? .current
        guard let firstDate = parseDate(first.time) else { throw WeatherServiceError.malformedData }
        let firstPeriod = first.data.next1Hours ?? first.data.next6Hours ?? first.data.next12Hours
        let firstCode = weatherCode(for: firstPeriod?.summary.symbolCode ?? "cloudy")
        let current = CurrentWeather(
            time: localTimestamp(firstDate, timezone: timezone),
            temperature: first.data.instant.details.airTemperature,
            apparentTemperature: first.data.instant.details.airTemperature,
            humidity: Int(first.data.instant.details.relativeHumidity.rounded()),
            precipitation: firstPeriod?.details.precipitationAmount ?? 0,
            weatherCode: firstCode,
            windSpeed: first.data.instant.details.windSpeed * 3.6,
            windDirection: Int(first.data.instant.details.windFromDirection.rounded()),
            isDay: isDay(symbol: firstPeriod?.summary.symbolCode, date: firstDate, timezone: timezone)
        )

        let hourly = response.properties.timeseries.compactMap { item -> HourlyWeather? in
            guard let date = parseDate(item.time), date >= firstDate, item.data.next1Hours != nil else { return nil }
            let period = item.data.next1Hours
            return HourlyWeather(
                time: localTimestamp(date, timezone: timezone),
                temperature: item.data.instant.details.airTemperature,
                precipitationProbability: Int((period?.details.probabilityOfPrecipitation ?? 0).rounded()),
                weatherCode: weatherCode(for: period?.summary.symbolCode ?? "cloudy")
            )
        }.prefix(24)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        var grouped: [String: [TimeSeries]] = [:]
        for item in response.properties.timeseries {
            guard let date = parseDate(item.time), date >= calendar.startOfDay(for: firstDate) else { continue }
            grouped[localDate(date, timezone: timezone), default: []].append(item)
        }
        let daily = grouped.keys.sorted().prefix(7).compactMap { date -> DailyWeather? in
            guard let items = grouped[date], !items.isEmpty else { return nil }
            let temperatures = items.map { $0.data.instant.details.airTemperature }
            let windSpeeds = items.map { $0.data.instant.details.windSpeed * 3.6 }
            let periods = items.compactMap { $0.data.next1Hours ?? $0.data.next6Hours ?? $0.data.next12Hours }
            let probability = periods.compactMap(\.details.probabilityOfPrecipitation).max() ?? 0
            let code = periods.map { weatherCode(for: $0.summary.symbolCode) }.max() ?? 3
            return DailyWeather(
                date: date,
                weatherCode: code,
                maximumTemperature: temperatures.max() ?? 0,
                minimumTemperature: temperatures.min() ?? 0,
                precipitationProbability: Int(probability.rounded()),
                sunrise: "",
                sunset: "",
                maximumWindSpeed: windSpeeds.max() ?? 0
            )
        }
        guard !hourly.isEmpty, !daily.isEmpty else { throw WeatherServiceError.malformedData }
        return WeatherSnapshot(
            location: location,
            current: current,
            hourly: Array(hourly),
            daily: daily,
            fetchedAt: Date()
        )
    }

    static func weatherCode(for symbol: String) -> Int {
        let value = symbol.lowercased()
        if value.contains("thunder") { return 95 }
        if value.contains("snow") { return value.contains("showers") ? 85 : 71 }
        if value.contains("sleet") { return 66 }
        if value.contains("rainshowers") { return 80 }
        if value.contains("heavyrain") { return 65 }
        if value.contains("rain") { return 63 }
        if value.contains("drizzle") { return 51 }
        if value.contains("fog") { return 45 }
        if value.contains("partlycloudy") { return 2 }
        if value.contains("cloudy") { return 3 }
        if value.contains("fair") { return 1 }
        if value.contains("clearsky") { return 0 }
        return 3
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func localTimestamp(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }

    private static func localDate(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isDay(symbol: String?, date: Date, timezone: TimeZone) -> Bool {
        if symbol?.contains("_night") == true { return false }
        if symbol?.contains("_day") == true { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return (6..<18).contains(calendar.component(.hour, from: date))
    }

    private struct Response: Decodable {
        let properties: Properties
    }

    private struct Properties: Decodable {
        let timeseries: [TimeSeries]
    }

    private struct TimeSeries: Decodable {
        let time: String
        let data: ForecastData
    }

    private struct ForecastData: Decodable {
        let instant: Instant
        let next1Hours: Period?
        let next6Hours: Period?
        let next12Hours: Period?

        private enum CodingKeys: String, CodingKey {
            case instant
            case next1Hours = "next_1_hours"
            case next6Hours = "next_6_hours"
            case next12Hours = "next_12_hours"
        }
    }

    private struct Instant: Decodable {
        let details: InstantDetails
    }

    private struct InstantDetails: Decodable {
        let airTemperature: Double
        let relativeHumidity: Double
        let windFromDirection: Double
        let windSpeed: Double

        private enum CodingKeys: String, CodingKey {
            case airTemperature = "air_temperature"
            case relativeHumidity = "relative_humidity"
            case windFromDirection = "wind_from_direction"
            case windSpeed = "wind_speed"
        }
    }

    private struct Period: Decodable {
        let summary: Summary
        let details: PeriodDetails
    }

    private struct Summary: Decodable {
        let symbolCode: String

        private enum CodingKeys: String, CodingKey {
            case symbolCode = "symbol_code"
        }
    }

    private struct PeriodDetails: Decodable {
        let precipitationAmount: Double?
        let probabilityOfPrecipitation: Double?

        private enum CodingKeys: String, CodingKey {
            case precipitationAmount = "precipitation_amount"
            case probabilityOfPrecipitation = "probability_of_precipitation"
        }
    }
}

enum ChinaWeatherCodeMapper {
    static func wmoCode(_ code: Int) -> Int {
        switch code {
        case 0: 0
        case 1: 2
        case 2: 3
        case 3: 80
        case 4: 95
        case 5: 96
        case 6: 66
        case 7: 61
        case 8: 63
        case 9...12: 65
        case 13: 85
        case 14: 71
        case 15: 73
        case 16, 17: 75
        case 18: 45
        case 19: 67
        case 20...31: 45
        case 53: 45
        default: 3
        }
    }
}

struct CMAWeatherService {
    func fetch(_ location: WeatherLocation) async throws -> WeatherSnapshot {
        try validateChina(location)
        let stationsData = try await request(
            URL(string: "https://weather.cma.cn/api/map/weather/1")!,
            referer: "https://weather.cma.cn/"
        )
        let map = try JSONDecoder().decode(StationMapResponse.self, from: stationsData)
        guard let station = map.data.city.min(by: {
            distance($0, location) < distance($1, location)
        }) else { throw WeatherServiceError.locationNotFound }
        var components = URLComponents(string: "https://weather.cma.cn/api/weather/view")!
        components.queryItems = [URLQueryItem(name: "stationid", value: station.id)]
        guard let url = components.url else { throw WeatherServiceError.invalidResponse }
        return try Self.parse(data: try await request(url, referer: "https://weather.cma.cn/"), location: location)
    }

    static func parse(data: Data, location: WeatherLocation) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
        guard response.code == 0, let payload = response.data, let firstDay = payload.daily.first else {
            throw WeatherServiceError.malformedData
        }
        let now = payload.now
        let current = CurrentWeather(
            time: payload.lastUpdate.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "T"),
            temperature: now.temperature,
            apparentTemperature: now.feelsLike ?? now.temperature,
            humidity: Int(now.humidity.rounded()),
            precipitation: now.precipitation,
            weatherCode: ChinaWeatherCodeMapper.wmoCode(firstDay.dayCode),
            windSpeed: now.windSpeed * 3.6,
            windDirection: Int(now.windDirectionDegree.rounded()),
            isDay: (6..<18).contains(Calendar.current.component(.hour, from: Date()))
        )
        let daily = payload.daily.map { item in
            DailyWeather(
                date: item.date.replacingOccurrences(of: "/", with: "-"),
                weatherCode: ChinaWeatherCodeMapper.wmoCode(item.dayCode),
                maximumTemperature: item.high,
                minimumTemperature: item.low,
                precipitationProbability: nil,
                sunrise: "",
                sunset: "",
                maximumWindSpeed: 0
            )
        }
        return WeatherSnapshot(location: location, current: current, hourly: [], daily: daily, fetchedAt: Date())
    }

    private func validateChina(_ location: WeatherLocation) throws {
        guard location.country.contains("中国") || location.timezone == "Asia/Shanghai" else {
            throw WeatherServiceError.unsupportedRegion
        }
    }

    private func distance(_ station: Station, _ location: WeatherLocation) -> Double {
        pow(station.latitude - location.latitude, 2) + pow(station.longitude - location.longitude, 2)
    }

    private func request(_ url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) Luma/1.1", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }
        return data
    }

    private struct StationMapResponse: Decodable {
        let data: StationMapData
    }

    private struct StationMapData: Decodable {
        let city: [Station]
    }

    private struct Station: Decodable {
        let id: String
        let latitude: Double
        let longitude: Double

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            id = try container.decode(String.self)
            _ = try container.decode(String.self)
            _ = try container.decode(String.self)
            _ = try container.decode(Int.self)
            latitude = try container.decode(Double.self)
            longitude = try container.decode(Double.self)
        }
    }

    private struct WeatherResponse: Decodable {
        let code: Int
        let data: Payload?
    }

    private struct Payload: Decodable {
        let daily: [Day]
        let now: Now
        let lastUpdate: String
    }

    private struct Now: Decodable {
        let precipitation: Double
        let temperature: Double
        let humidity: Double
        let windDirectionDegree: Double
        let windSpeed: Double
        let feelsLike: Double?

        private enum CodingKeys: String, CodingKey {
            case precipitation, temperature, humidity, windDirectionDegree, windSpeed
            case feelsLike = "feelst"
        }
    }

    private struct Day: Decodable {
        let date: String
        let high: Double
        let low: Double
        let dayCode: Int
    }
}

struct NMCWeatherService {
    func fetch(_ location: WeatherLocation) async throws -> WeatherSnapshot {
        try validateChina(location)
        let provinces = try JSONDecoder().decode(
            [Province].self,
            from: try await request(URL(string: "https://www.nmc.cn/rest/province")!)
        )
        let provinceQuery = normalized(location.admin1.isEmpty ? location.name : location.admin1)
        guard let province = provinces.first(where: {
            let name = normalized($0.name)
            return name == provinceQuery || name.contains(provinceQuery) || provinceQuery.contains(name)
        }) else { throw WeatherServiceError.locationNotFound }
        let cities = try JSONDecoder().decode(
            [City].self,
            from: try await request(URL(string: "https://www.nmc.cn/rest/province/\(province.code)")!)
        )
        let cityQuery = normalized(location.name)
        guard let city = cities.first(where: {
            let name = normalized($0.city)
            return name == cityQuery || name.contains(cityQuery) || cityQuery.contains(name)
        }) else { throw WeatherServiceError.locationNotFound }
        var components = URLComponents(string: "https://www.nmc.cn/rest/weather")!
        components.queryItems = [URLQueryItem(name: "stationid", value: city.code)]
        guard let url = components.url else { throw WeatherServiceError.invalidResponse }
        return try Self.parse(data: try await request(url), location: location)
    }

    static func parse(data: Data, location: WeatherLocation) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == 0, let payload = response.data, let firstDay = payload.predict.detail.first else {
            throw WeatherServiceError.malformedData
        }
        let real = payload.real
        let imageCode = Int(real.weather.img) ?? Int(firstDay.day.weather.img) ?? 2
        let current = CurrentWeather(
            time: real.publishTime.replacingOccurrences(of: " ", with: "T"),
            temperature: real.weather.temperature,
            apparentTemperature: real.weather.feelsLike ?? real.weather.temperature,
            humidity: Int(real.weather.humidity.rounded()),
            precipitation: real.weather.rain,
            weatherCode: ChinaWeatherCodeMapper.wmoCode(imageCode),
            windSpeed: real.wind.speed * 3.6,
            windDirection: Int(real.wind.degree.rounded()),
            isDay: (6..<18).contains(Calendar.current.component(.hour, from: Date()))
        )
        let daily = payload.predict.detail.compactMap { item -> DailyWeather? in
            guard let high = Double(item.day.weather.temperature),
                  let low = Double(item.night.weather.temperature) else { return nil }
            return DailyWeather(
                date: item.date,
                weatherCode: ChinaWeatherCodeMapper.wmoCode(Int(item.day.weather.img) ?? 2),
                maximumTemperature: high,
                minimumTemperature: low,
                precipitationProbability: nil,
                sunrise: item.date == firstDay.date ? real.sunriseSunset.sunrise : "",
                sunset: item.date == firstDay.date ? real.sunriseSunset.sunset : "",
                maximumWindSpeed: 0
            )
        }
        guard !daily.isEmpty else { throw WeatherServiceError.malformedData }
        return WeatherSnapshot(location: location, current: current, hourly: [], daily: daily, fetchedAt: Date())
    }

    private func validateChina(_ location: WeatherLocation) throws {
        guard location.country.contains("中国") || location.timezone == "Asia/Shanghai" else {
            throw WeatherServiceError.unsupportedRegion
        }
    }

    private func normalized(_ value: String) -> String {
        ["维吾尔自治区", "壮族自治区", "回族自治区", "特别行政区", "自治区", "新区", "省", "市", "区", "县"]
            .reduce(value) { $0.replacingOccurrences(of: $1, with: "") }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) Luma/1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.nmc.cn/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }
        return data
    }

    private struct Province: Decodable { let code: String; let name: String }
    private struct City: Decodable { let code: String; let city: String }

    private struct Response: Decodable {
        let code: Int
        let data: Payload?
    }

    private struct Payload: Decodable {
        let real: Real
        let predict: Predict
    }

    private struct Real: Decodable {
        let publishTime: String
        let weather: RealWeather
        let wind: Wind
        let sunriseSunset: SunriseSunset

        private enum CodingKeys: String, CodingKey {
            case publishTime = "publish_time"
            case weather, wind, sunriseSunset
        }
    }

    private struct RealWeather: Decodable {
        let temperature: Double
        let humidity: Double
        let rain: Double
        let img: String
        let feelsLike: Double?

        private enum CodingKeys: String, CodingKey {
            case temperature, humidity, rain, img
            case feelsLike = "feelst"
        }
    }

    private struct Wind: Decodable { let degree: Double; let speed: Double }
    private struct SunriseSunset: Decodable { let sunrise: String; let sunset: String }
    private struct Predict: Decodable { let detail: [PredictDay] }
    private struct PredictDay: Decodable {
        let date: String
        let day: DayPart
        let night: DayPart
    }
    private struct DayPart: Decodable { let weather: DayWeather }
    private struct DayWeather: Decodable { let img: String; let temperature: String }
}

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var records: [WeatherSnapshot] = []
    @Published var selectedLocationID: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingAll = false
    @Published var errorMessage = ""
    @Published private(set) var dataSource: WeatherDataSource

    typealias LocationAdder = (String) async throws -> WeatherSnapshot
    typealias ForecastFetcher = (WeatherLocation) async throws -> WeatherSnapshot

    private let customAdder: LocationAdder?
    private let customFetcher: ForecastFetcher?
    private let defaults: UserDefaults
    private let defaultsKey = "luma.weather.locations.v1"
    private let dataSourceKey = "luma.weather.data-source.v1"

    init(
        records preloadedRecords: [WeatherSnapshot]? = nil,
        defaults: UserDefaults = .standard,
        adder: LocationAdder? = nil,
        fetcher: ForecastFetcher? = nil
    ) {
        self.defaults = defaults
        customAdder = adder
        customFetcher = fetcher
        dataSource = WeatherDataSource(rawValue: defaults.string(forKey: dataSourceKey) ?? "") ?? .openMeteo
        if let preloadedRecords {
            records = preloadedRecords
            selectedLocationID = preloadedRecords.first?.id
            return
        }
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([WeatherSnapshot].self, from: data) {
            records = saved
            selectedLocationID = saved.first?.id
        }
    }

    var selected: WeatherSnapshot? {
        records.first { $0.id == selectedLocationID } ?? records.first
    }

    var isBusy: Bool { isLoading || isRefreshingAll }

    func add(_ query: String) async {
        guard !isBusy else { return }
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = WeatherServiceError.emptyQuery.localizedDescription
            return
        }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            let snapshot: WeatherSnapshot
            if let customAdder {
                snapshot = try await customAdder(value)
            } else {
                let location = try await OpenMeteoWeatherService().searchLocation(value)
                snapshot = try await fetch(location)
            }
            upsert(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ location: WeatherLocation) async {
        guard !isBusy else { return }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            upsert(try await fetch(location))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSelected() async {
        guard !isBusy, let selected else { return }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            upsert(try await fetch(selected.location))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        guard !isBusy, !records.isEmpty else { return }
        let locations = records.map(\.location)
        let source = dataSource
        let customFetcher = customFetcher
        isRefreshingAll = true
        errorMessage = ""
        defer { isRefreshingAll = false }
        var failures = 0
        await withTaskGroup(of: WeatherSnapshot?.self) { group in
            let initialCount = min(4, locations.count)
            for location in locations.prefix(initialCount) {
                group.addTask {
                    try? await Self.fetchSnapshot(
                        location,
                        source: source,
                        customFetcher: customFetcher
                    )
                }
            }
            var nextIndex = initialCount
            while let snapshot = await group.next() {
                if let snapshot {
                    if let index = records.firstIndex(where: { $0.id == snapshot.id }) {
                        records[index] = snapshot
                    }
                } else {
                    failures += 1
                }
                if nextIndex < locations.count {
                    let location = locations[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        try? await Self.fetchSnapshot(
                            location,
                            source: source,
                            customFetcher: customFetcher
                        )
                    }
                }
            }
        }
        save()
        if failures > 0 {
            errorMessage = "已刷新 \(locations.count - failures)/\(locations.count) 个地点，\(failures) 个失败"
        }
    }

    func select(_ snapshot: WeatherSnapshot) {
        guard records.contains(where: { $0.id == snapshot.id }) else { return }
        selectedLocationID = snapshot.id
    }

    func remove(_ snapshot: WeatherSnapshot) {
        records.removeAll { $0.id == snapshot.id }
        if selectedLocationID == snapshot.id { selectedLocationID = records.first?.id }
        save()
    }

    func setDataSource(_ source: WeatherDataSource) {
        dataSource = source
        defaults.set(source.rawValue, forKey: dataSourceKey)
    }

    private func fetch(_ location: WeatherLocation) async throws -> WeatherSnapshot {
        try await Self.fetchSnapshot(location, source: dataSource, customFetcher: customFetcher)
    }

    private nonisolated static func fetchSnapshot(
        _ location: WeatherLocation,
        source: WeatherDataSource,
        customFetcher: ForecastFetcher?
    ) async throws -> WeatherSnapshot {
        if let customFetcher { return try await customFetcher(location) }
        switch source {
        case .openMeteo: return try await OpenMeteoWeatherService().fetch(location)
        case .metNorway: return try await METNorwayWeatherService().fetch(location)
        case .chinaMeteorologicalAdministration: return try await CMAWeatherService().fetch(location)
        case .nationalMeteorologicalCenter: return try await NMCWeatherService().fetch(location)
        }
    }

    private func upsert(_ snapshot: WeatherSnapshot) {
        records.removeAll { $0.id == snapshot.id }
        records.insert(snapshot, at: 0)
        if records.count > 20 { records.removeLast(records.count - 20) }
        selectedLocationID = snapshot.id
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
