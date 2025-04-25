//
//  OpenAIService.swift
//  weather_app_test
//
//  Created by Song Lingchen on R 7/03/03.
//
import Foundation

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Float?
    let stream: Bool?
    
    struct Message: Encodable {
        let role: String
        let content: String
    }
}

struct OpenAIResponse: Decodable {
    let id: String
    let choices: [Choice]
    
    struct Choice: Decodable {
        let message: Message
        
        struct Message: Decodable {
            let role: String
            let content: String
        }
    }
}

struct OpenAIStreamResponse: Decodable {
    let choices: [Choice]?
    let error: ResponseError?
    
    struct Choice: Decodable {
        let delta: Delta?
        
        struct Delta: Decodable {
            let content: String?
        }
    }
    
    struct ResponseError: Decodable {
        let message: String
        let type: String
    }
}

enum OpenAIError: Error {
    case networkError(Error)
    case invalidResponse
    case noData
    case decodingError(Error)
    case apiError(String)
    
    var localizedDescription: String {
        switch self {
        case .networkError(let error):
            return "Network Error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Server returned invalid response"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API Error: \(message)"
        }
    }
}

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model: String
    
    // 保存对话历史
    private var chatHistory: [OpenAIRequest.Message] = []
    
    // 创建自定义的URLSession配置
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0  // 增加超时时间到60秒
        config.timeoutIntervalForResource = 120.0  // 增加资源超时时间到120秒
        
        return URLSession(configuration: config)
    }()
    
    init(apiKey: String, model: String = "gpt-4") {
        self.apiKey = apiKey
        self.model = model
        print("Initializing OpenAI service, using model: \(model)")
    }
    
    // 清除对话历史
    func clearChatHistory() {
        chatHistory = []
        print("Chat history cleared")
    }
    
    // 添加系统提示
    func addSystemPrompt(_ prompt: String) {
        let systemMessage = OpenAIRequest.Message(role: "system", content: prompt)
        
        // 如果已经有系统提示，替换它
        if !chatHistory.isEmpty && chatHistory[0].role == "system" {
            chatHistory[0] = systemMessage
        } else {
            // 否则添加到历史的开头
            chatHistory.insert(systemMessage, at: 0)
        }
        
        print("System prompt added: \(prompt)")
    }
    
    // 发送消息 - 标准方式
    func sendMessage(_ message: String, completion: @escaping (Result<String, Error>) -> Void) {
        // 添加用户消息到历史
        let userMessage = OpenAIRequest.Message(role: "user", content: message)
        chatHistory.append(userMessage)
        
        guard let url = URL(string: baseURL) else {
            completion(.failure(OpenAIError.invalidResponse))
            return
        }
        
        print("Preparing to send request to: \(baseURL)")
        print("Chat history message count: \(chatHistory.count)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let openAIRequest = OpenAIRequest(
            model: model,
            messages: chatHistory,
            temperature: 0.7,
            stream: false
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(openAIRequest)
            print("Request body encoded")
        } catch {
            print("Encoding error: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        print("Starting network request...")
        
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                completion(.failure(OpenAIError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                completion(.failure(OpenAIError.invalidResponse))
                return
            }
            
            print("Received HTTP response, status code: \(httpResponse.statusCode)")
            
            guard let data = data else {
                print("No data received")
                completion(.failure(OpenAIError.noData))
                return
            }
            
            // Check for API errors
            if httpResponse.statusCode != 200 {
                do {
                    let errorResponse = try JSONDecoder().decode(OpenAIStreamResponse.self, from: data)
                    if let errorMessage = errorResponse.error?.message {
                        print("API error: \(errorMessage)")
                        completion(.failure(OpenAIError.apiError(errorMessage)))
                    } else {
                        let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response content"
                        print("Error status code \(httpResponse.statusCode): \(responseText)")
                        completion(.failure(OpenAIError.invalidResponse))
                    }
                    return
                } catch {
                    let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response content"
                    print("Error status code \(httpResponse.statusCode): \(responseText)")
                    completion(.failure(OpenAIError.invalidResponse))
                    return
                }
            }
            
            // Try to parse JSON response
            do {
                let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                if let content = response.choices.first?.message.content {
                    print("Successfully received response content")
                    // Add assistant's reply to chat history
                    let assistantMessage = OpenAIRequest.Message(role: "assistant", content: content)
                    self.chatHistory.append(assistantMessage)
                    completion(.success(content))
                } else {
                    print("Response does not contain message content")
                    completion(.failure(OpenAIError.invalidResponse))
                }
            } catch {
                print("JSON parsing error: \(error.localizedDescription)")
                
                // Try to print received raw data for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Server returned raw data: \(responseString)")
                }
                
                completion(.failure(OpenAIError.decodingError(error)))
            }
        }
        
        task.resume()
    }
    
    // 发送消息 - 流式响应
    func sendMessageStream(_ message: String, onUpdate: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        // Add user message to history
        let userMessage = OpenAIRequest.Message(role: "user", content: message)
        chatHistory.append(userMessage)
        
        guard let url = URL(string: baseURL) else {
            completion(.failure(OpenAIError.invalidResponse))
            return
        }
        
        print("Preparing to send stream request to: \(baseURL)")
        print("Chat history message count: \(chatHistory.count)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let openAIRequest = OpenAIRequest(
            model: model,
            messages: chatHistory,
            temperature: 0.7,
            stream: true
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(openAIRequest)
            print("Stream request body encoded")
        } catch {
            print("Encoding error: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        print("Starting stream network request...")
        
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                completion(.failure(OpenAIError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                completion(.failure(OpenAIError.invalidResponse))
                return
            }
            
            print("Received HTTP response, status code: \(httpResponse.statusCode)")
            
            guard let data = data else {
                print("No data received")
                completion(.failure(OpenAIError.noData))
                return
            }
            
            // Check for API errors
            if httpResponse.statusCode != 200 {
                do {
                    let errorResponse = try JSONDecoder().decode(OpenAIStreamResponse.self, from: data)
                    if let errorMessage = errorResponse.error?.message {
                        print("API error: \(errorMessage)")
                        completion(.failure(OpenAIError.apiError(errorMessage)))
                    } else {
                        let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response content"
                        print("Error status code \(httpResponse.statusCode): \(responseText)")
                        completion(.failure(OpenAIError.invalidResponse))
                    }
                    return
                } catch {
                    let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response content"
                    print("Error status code \(httpResponse.statusCode): \(responseText)")
                    completion(.failure(OpenAIError.invalidResponse))
                    return
                }
            }
            
            // Parse stream response
            var fullResponse = ""
            
            if let responseString = String(data: data, encoding: .utf8) {
                // Split stream response line by line
                let lines = responseString.components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                
                for line in lines {
                    // Each line in stream response is "data: {...}"
                    if line.hasPrefix("data: ") {
                        let jsonString = line.dropFirst(6) // Remove "data: " prefix
                        
                        // "[DONE]" indicates stream end
                        if jsonString == "[DONE]" {
                            continue
                        }
                        
                        if let jsonData = jsonString.data(using: .utf8) {
                            do {
                                let chunkResponse = try JSONDecoder().decode(OpenAIStreamResponse.self, from: jsonData)
                                if let content = chunkResponse.choices?.first?.delta?.content {
                                    fullResponse += content
                                    onUpdate(fullResponse)
                                }
                            } catch {
                                print("Stream response parsing error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                // Add full response to chat history
                if !fullResponse.isEmpty {
                    let assistantMessage = OpenAIRequest.Message(role: "assistant", content: fullResponse)
                    self.chatHistory.append(assistantMessage)
                    completion(.success(()))
                } else {
                    completion(.failure(OpenAIError.noData))
                }
            } else {
                completion(.failure(OpenAIError.invalidResponse))
            }
        }
        
        task.resume()
    }
}
