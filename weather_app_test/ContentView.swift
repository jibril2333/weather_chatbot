import SwiftUI
import CoreLocation

// 天气数据结构
struct WeatherData: Identifiable {
    let id = UUID()
    let city: String
    let temperature: Double
    let condition: String
    let icon: String
    let humidity: Int
    let windSpeed: Double
    let precipitation: Double
    let location: CLLocationCoordinate2D
}

// 天气服务类
class WeatherService: ObservableObject {
    @Published var weatherData: [WeatherData] = []
    private let cities: [(name: String, location: CLLocationCoordinate2D)] = [
        ("Tokyo", CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917)),    // 东京 - 首都，最大城市
        ("Osaka", CLLocationCoordinate2D(latitude: 34.6937, longitude: 135.5023)),    // 大阪 - 关西经济中心
        ("Nagoya", CLLocationCoordinate2D(latitude: 35.1815, longitude: 136.9066)),   // 名古屋 - 中部经济中心
        ("Fukuoka", CLLocationCoordinate2D(latitude: 33.5902, longitude: 130.4017))   // 福冈 - 九州最大城市
    ]
    
    func fetchWeather() {
        for city in cities {
            let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(city.location.latitude)&longitude=\(city.location.longitude)&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m&timezone=Asia%2FTokyo"
            
            guard let url = URL(string: urlString) else {
                print("Invalid URL for city: \(city.name)")
                return
            }
            
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let data = data, error == nil else {
                    print("Error fetching weather data for \(city.name): \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    let weatherData = WeatherData(
                        city: city.name,
                        temperature: response.current.temperature_2m,
                        condition: self?.getWeatherCondition(from: response.current.weather_code) ?? "Unknown",
                        icon: self?.getWeatherIcon(from: response.current.weather_code) ?? "questionmark.circle.fill",
                        humidity: response.current.relative_humidity_2m,
                        windSpeed: response.current.wind_speed_10m,
                        precipitation: response.current.precipitation,
                        location: city.location
                    )
                    
                    DispatchQueue.main.async {
                        if let index = self?.weatherData.firstIndex(where: { $0.city == city.name }) {
                            self?.weatherData[index] = weatherData
                        } else {
                            self?.weatherData.append(weatherData)
                        }
                    }
                } catch {
                    print("Error decoding weather data for \(city.name): \(error.localizedDescription)")
                }
            }.resume()
        }
    }
    
    private func getWeatherCondition(from code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Partly Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Light Drizzle"
        case 61, 63, 65: return "Rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with Hail"
        default: return "Unknown"
        }
    }
    
    private func getWeatherIcon(from code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2, 3: return "cloud.sun.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

// API 响应结构
struct WeatherResponse: Codable {
    let current: CurrentWeather
    
    struct CurrentWeather: Codable {
        let temperature_2m: Double
        let relative_humidity_2m: Int
        let precipitation: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }
}

struct ContentView: View {
    @StateObject private var weatherService = WeatherService()
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(weatherService.weatherData) { data in
                    WeatherRow(data: data)
                }
            }
            .navigationTitle("My Weather")
            .refreshable {
                await refreshWeather()
            }
            .onAppear {
                weatherService.fetchWeather()
            }
        }
    }
    
    private func refreshWeather() async {
        isRefreshing = true
        weatherService.fetchWeather()
        isRefreshing = false
    }
}

struct WeatherRow: View {
    let data: WeatherData
    
    var body: some View {
        HStack {
            Image(systemName: data.icon)
                .font(.title)
                .frame(width: 50)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(data.city)
                    .font(.headline)
                Text(data.condition)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text("湿度: \(data.humidity)%")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("风速: \(String(format: "%.1f", data.windSpeed)) km/h")
                    .font(.caption)
                    .foregroundColor(.gray)
                if data.precipitation > 0 {
                    Text("降水: \(String(format: "%.1f", data.precipitation)) mm")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Text("\(Int(data.temperature))°C")
                .font(.title)
                .fontWeight(.bold)
        }
        .padding(.vertical, 8)
    }
}

struct DetailView: View {
    let data: WeatherData
    
    var body: some View {
        VStack(spacing: 20) {
            Text(data.city)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Image(systemName: data.icon)
                .font(.system(size: 100))
                .foregroundColor(.blue)
            
            Text("\(Int(data.temperature))°C")
                .font(.system(size: 70))
                .fontWeight(.bold)
            
            Text(data.condition)
                .font(.title)
                .foregroundColor(.gray)
            
            HStack(spacing: 30) {
                VStack {
                    Text("\(data.humidity)%")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Humidity")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                VStack {
                    Text("\(String(format: "%.1f", data.windSpeed)) km/h")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Wind Speed")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                if data.precipitation > 0 {
                    VStack {
                        Text("\(String(format: "%.1f", data.precipitation)) mm")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Precipitation")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Weather Details")
    }
}

