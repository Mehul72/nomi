import Foundation

struct WeatherTool: Tool {
    let name = "get_weather"
    let description = "Current conditions and a daily forecast for a place, in metric units. Use it for questions like the weather today, whether it will rain tomorrow, or the weekend outlook."
    let parameters = [
        ToolParameterSpec.optional("location", .string, "City or place name, such as Sydney or Melbourne. Leave empty for the user's home location."),
        ToolParameterSpec.optional("when", .string, "Which period the user asked about", allowedValues: ["now", "today", "tomorrow", "weekend", "week"]),
    ]
    let risk = RiskLevel.low
    let symbol = "cloud.sun"

    private let client: WeatherClient

    init(client: WeatherClient = WeatherClient()) {
        self.client = client
    }

    func activityLabel(for arguments: ToolArguments) -> String {
        if let location = try? arguments.optionalString("location"), !location.isEmpty {
            return "Checking the weather in \(location)"
        }
        return "Checking the weather"
    }

    func confirmationText(for arguments: ToolArguments) -> String { "Check the weather?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard !context.isOffline else { throw ToolError.offline }
        let requested = try arguments.optionalString("location")?.trimmingCharacters(in: .whitespaces) ?? ""
        let when = WeatherPeriod(rawValue: try arguments.optionalString("when") ?? "today") ?? .today
        let placeName = requested.isEmpty ? (context.homeLocation ?? "") : requested
        guard !placeName.isEmpty else {
            throw ToolError.failed("No location was given and no home location is set in Settings > Tools.")
        }
        let place = try await client.geocode(placeName)
        let forecast = try await client.forecast(latitude: place.latitude, longitude: place.longitude)
        let report = WeatherReport(place: place, forecast: forecast)
        return ToolResult(content: report.text(for: when), summary: "Weather for \(place.name): \(report.currentSummary)")
    }
}

nonisolated enum WeatherPeriod: String, Sendable {
    case now, today, tomorrow, weekend, week
}

nonisolated struct WeatherPlace: Sendable, Equatable {
    var name: String
    var region: String?
    var country: String?
    var latitude: Double
    var longitude: Double

    var displayName: String {
        [name, region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Open-Meteo's forecast payload, decoded only as far as the report needs.
nonisolated struct WeatherForecast: Decodable, Sendable, Equatable {
    struct Current: Decodable, Sendable, Equatable {
        let time: String
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }

    struct Daily: Decodable, Sendable, Equatable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int?]
        let precipitation_sum: [Double?]
    }

    let timezone: String
    let current: Current
    let daily: Daily
}

/// Turns a forecast into the sentences the model receives.
nonisolated struct WeatherReport: Sendable {
    let place: WeatherPlace
    let forecast: WeatherForecast
    var calendar: Calendar = .current

    var currentSummary: String {
        "\(Self.round(forecast.current.temperature_2m))°C, \(Self.describe(forecast.current.weather_code).lowercased())"
    }

    func text(for period: WeatherPeriod) -> String {
        var lines = ["Weather for \(place.displayName) (times in \(forecast.timezone))."]
        lines.append(
            "Now: \(Self.round(forecast.current.temperature_2m))°C, feels like \(Self.round(forecast.current.apparent_temperature))°C, "
            + "\(Self.describe(forecast.current.weather_code).lowercased()), humidity \(Int(forecast.current.relative_humidity_2m))%, wind \(Self.round(forecast.current.wind_speed_10m)) km/h."
        )
        let days = dayLines()
        switch period {
        case .now: break
        case .today: lines += days.prefix(1)
        case .tomorrow: lines += days.dropFirst().prefix(1)
        case .weekend: lines += weekendLines()
        case .week: lines += days
        }
        return lines.joined(separator: "\n")
    }

    /// One line per forecast day, in order. Relative labels say Today and Tomorrow; weekday labels name the day.
    func dayLines(weekdayNames: Bool = false) -> [String] {
        forecast.daily.time.indices.map { index in
            let date = forecast.daily.time[index]
            let label = Self.dayLabel(date, index: weekdayNames ? .max : index, calendar: calendar)
            let rain = forecast.daily.precipitation_probability_max[safe: index]??.description ?? "unknown"
            let amount = forecast.daily.precipitation_sum[safe: index]?.map { Self.round($0) } ?? "0"
            return "\(label) (\(date)): \(Self.describe(forecast.daily.weather_code[index])), high \(Self.round(forecast.daily.temperature_2m_max[index]))°C, "
                + "low \(Self.round(forecast.daily.temperature_2m_min[index]))°C, rain chance \(rain)%, precipitation \(amount) mm."
        }
    }

    private func weekendLines() -> [String] {
        let lines = dayLines(weekdayNames: true)
        let weekendIndices = forecast.daily.time.indices.filter { index in
            guard let date = Self.parse(forecast.daily.time[index], calendar: calendar) else { return false }
            return calendar.isDateInWeekend(date)
        }
        let chosen = weekendIndices.prefix(2)
        return chosen.isEmpty ? Array(lines.prefix(2)) : chosen.map { lines[$0] }
    }

    static func dayLabel(_ date: String, index: Int, calendar: Calendar) -> String {
        switch index {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            guard let parsed = parse(date, calendar: calendar) else { return date }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "EEEE"
            return formatter.string(from: parsed)
        }
    }

    static func parse(_ date: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }

    static func round(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// WMO weather interpretation codes.
    static func describe(_ code: Int) -> String {
        switch code {
        case 0: "Clear sky"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61: "Light rain"
        case 63: "Rain"
        case 65: "Heavy rain"
        case 66, 67: "Freezing rain"
        case 71: "Light snow"
        case 73: "Snow"
        case 75: "Heavy snow"
        case 77: "Snow grains"
        case 80: "Light showers"
        case 81: "Showers"
        case 82: "Violent showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "Unknown conditions"
        }
    }
}

nonisolated extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Open-Meteo geocoding and forecast requests. No key, metric units, 15 second limit per request.
nonisolated struct WeatherClient: Sendable {
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Result]?
    }

    func geocode(_ name: String) async throws -> WeatherPlace {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        let data = try await fetch(components.url!)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        guard let first = response.results?.first else {
            throw ToolError.failed("No place called \(name) was found.")
        }
        return WeatherPlace(name: first.name, region: first.admin1, country: first.country, latitude: first.latitude, longitude: first.longitude)
    }

    func forecast(latitude: Double, longitude: Double) async throws -> WeatherForecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]
        let data = try await fetch(components.url!)
        return try JSONDecoder().decode(WeatherForecast.self, from: data)
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError.failed("The weather service did not answer (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        return data
    }
}
