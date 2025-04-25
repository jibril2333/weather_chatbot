//
//  weather_app_testApp.swift
//  weather_app_test
//
//  Created by Song Lingchen on R 7/03/03.
//

import SwiftUI

// Application Environment Variables
class AppEnvironment {
    static let shared = AppEnvironment()
    
    // OpenAI API Key
    let openAIApiKey = "" // Please replace with your API key
    
    // OpenAI Model Settings
    let modelName = "gpt-4o" // Options: gpt-4, gpt-3.5-turbo
    
    // Application Settings
    var weatherSystemPrompt = "You are a professional weather assistant. Please answer weather-related questions in a concise and friendly manner. Provide accurate weather information and inform users when you cannot access real-time weather data."
    
    // Whether to reset conversation
    var resetChatHistory = false
    
    // Tokyo Weather Data
    private var tokyoWeather: String?
    
    private init() {
        // Fetch Tokyo weather on initialization
        fetchTokyoWeather()
    }
    
    // Fetch Tokyo Weather
    private func fetchTokyoWeather() {
        let urlString = "https://api.open-meteo.com/v1/jma?latitude=35.6895&longitude=139.6917&current=temperature_2m,weather_code"
        
        guard let url = URL(string: urlString) else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = json["current"] as? [String: Any],
                   let temperature = current["temperature_2m"] as? Double,
                   let weatherCode = current["weather_code"] as? Int {
                    
                    let weatherCondition = self.getWeatherCondition(from: weatherCode)
                    self.tokyoWeather = "Tokyo Current Weather: \(weatherCondition), Temperature: \(Int(temperature))°C"
                    
                    // Update system prompt
                    DispatchQueue.main.async {
                        self.weatherSystemPrompt = """
                        You are a professional weather assistant. Please answer weather-related questions in a concise and friendly manner.
                        Current Tokyo Weather Information: \(self.tokyoWeather ?? "Unable to fetch real-time weather data")
                        Please use this information to answer user questions. If users ask about Tokyo's weather, prioritize using this real-time data.
                        For weather questions about other cities, please inform users that you cannot access real-time data.
                        """
                    }
                }
            } catch {
                print("Weather data parsing error: \(error)")
            }
        }
        task.resume()
    }
    
    // Get weather condition description from weather code
    private func getWeatherCondition(from code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Partly Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Light Rain"
        case 61, 63, 65: return "Rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Light Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }
}

@main
struct weather_app_testApp: App {
    init() {
        // Set environment variables when app starts
        setupEnvironment()
    }
    
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationView {
                    ContentView()
                }
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun")
                }
                
                NavigationView {
                    ChatView()
                }
                .tabItem {
                    Label("Weather Assistant", systemImage: "message")
                }
            }
        }
    }
    
    // Set up environment variables
    private func setupEnvironment() {
        // Here you can load keys from secure storage or configuration files
        print("App started, environment variables set")
        print("Using model: \(AppEnvironment.shared.modelName)")
        
        // Show prompt if chat history needs to be reset
        if AppEnvironment.shared.resetChatHistory {
            print("Will reset chat history")
        }
    }
}
