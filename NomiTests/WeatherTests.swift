import Foundation
import Testing
@testable import Nomi

struct WeatherTests {
    static let fixture = Data("""
    {"timezone":"Australia/Sydney",
     "current":{"time":"2026-09-04T22:00","temperature_2m":14.6,"apparent_temperature":12.1,"relative_humidity_2m":71,"weather_code":3,"wind_speed_10m":9.4},
     "daily":{"time":["2026-09-04","2026-09-05","2026-09-06","2026-09-07"],
              "weather_code":[3,61,80,0],
              "temperature_2m_max":[19.2,17.4,18.9,21.0],
              "temperature_2m_min":[11.0,12.3,10.8,9.9],
              "precipitation_probability_max":[10,80,null,0],
              "precipitation_sum":[0.0,6.4,2.1,null]}}
    """.utf8)

    static let place = WeatherPlace(name: "Sydney", region: "New South Wales", country: "Australia", latitude: -33.87, longitude: 151.21)

    private func report() throws -> WeatherReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return WeatherReport(place: Self.place, forecast: try JSONDecoder().decode(WeatherForecast.self, from: Self.fixture), calendar: calendar)
    }

    @Test func decodesOptionalNullsInDailyArrays() throws {
        let forecast = try JSONDecoder().decode(WeatherForecast.self, from: Self.fixture)
        #expect(forecast.daily.precipitation_probability_max[2] == nil)
        #expect(forecast.daily.precipitation_sum[3] == nil)
        #expect(forecast.current.weather_code == 3)
    }

    @Test func todayIncludesCurrentAndFirstDay() throws {
        let text = try report().text(for: .today)
        #expect(text.contains("Now: 15°C, feels like 12°C, overcast, humidity 71%, wind 9 km/h."))
        #expect(text.contains("Today (2026-09-04): Overcast, high 19°C, low 11°C, rain chance 10%, precipitation 0 mm."))
        #expect(!text.contains("Tomorrow"))
    }

    @Test func tomorrowAnswersWillItRain() throws {
        let text = try report().text(for: .tomorrow)
        #expect(text.contains("Tomorrow (2026-09-05): Light rain, high 17°C, low 12°C, rain chance 80%, precipitation 6 mm."))
        #expect(!text.contains("Today ("))
    }

    @Test func weekendPicksSaturdayAndSunday() throws {
        let text = try report().text(for: .weekend)
        #expect(text.contains("Saturday (2026-09-05)"))
        #expect(text.contains("Sunday (2026-09-06): Light showers"))
        #expect(!text.contains("Monday"))
    }

    @Test func unknownRainChanceIsSaidNotGuessed() throws {
        let lines = try report().dayLines()
        #expect(lines[2].contains("rain chance unknown%"))
        #expect(lines[3].contains("precipitation 0 mm"))
    }

    @Test func weatherCodesHaveNames() {
        #expect(WeatherReport.describe(95) == "Thunderstorm")
        #expect(WeatherReport.describe(999) == "Unknown conditions")
    }

    @Test func offlineModeRefusesBeforeAnyRequest() async {
        let tool = WeatherTool()
        await #expect(throws: ToolError.offline) {
            _ = try await tool.execute(ToolArguments(["location": .string("Sydney")]), context: ToolContext(isOffline: true, homeLocation: nil))
        }
    }

    @Test func missingLocationWithoutHomeIsAClearError() async {
        let tool = WeatherTool()
        await #expect(throws: ToolError.failed("No location was given and no home location is set in Settings > Tools.")) {
            _ = try await tool.execute(ToolArguments([:]), context: ToolContext(isOffline: false, homeLocation: nil))
        }
    }
}
