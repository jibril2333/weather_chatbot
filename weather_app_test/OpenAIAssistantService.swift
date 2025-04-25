import Foundation

// OpenAI Assistant API 错误类型
enum AssistantError: Error {
    case networkError(Error)
    case invalidResponse
    case noData
    case decodingError(Error)
    case apiError(String)
    case threadError(String)
    case runError(String)
    
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
        case .threadError(let message):
            return "Thread Error: \(message)"
        case .runError(let message):
            return "Run Error: \(message)"
        }
    }
}

// OpenAI Assistant 服务类
class OpenAIAssistantService {
    // MARK: - 属性
    private let apiKey: String
    private let assistantId: String
    private var threadId: String?
    
    private let baseURL = "https://api.openai.com/v1"
    
    // 创建自定义的URLSession配置
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        
        return URLSession(configuration: config)
    }()
    
    // MARK: - 初始化
    init(apiKey: String, assistantId: String, threadId: String? = nil) {
        self.apiKey = apiKey
        self.assistantId = assistantId
        self.threadId = threadId
        
        // 如果有保存的线程ID，从UserDefaults加载
        if threadId == nil {
            self.threadId = UserDefaults.standard.string(forKey: "openai_thread_id")
        }
        
        print("Initializing OpenAI Assistant service")
    }
    
    // MARK: - 公共方法
    
    /// 创建新的对话线程或获取已有线程
    func createOrGetThread(completion: @escaping (Result<String, Error>) -> Void) {
        if let threadId = threadId {
            // 尝试获取已有线程
            retrieveThread(threadId: threadId) { [weak self] result in
                switch result {
                case .success:
                    completion(.success(threadId))
                case .failure:
                    // 如果获取失败，创建新线程
                    self?.createThread(completion: completion)
                }
            }
        } else {
            // 直接创建新线程
            createThread(completion: completion)
        }
    }
    
    /// 发送消息并获取助手回复
    func sendMessage(message: String, onUpdate: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        // 确保有线程ID
        guard let threadId = threadId else {
            createOrGetThread { [weak self] result in
                switch result {
                case .success(let newThreadId):
                    self?.threadId = newThreadId
                    // 保存线程ID
                    UserDefaults.standard.set(newThreadId, forKey: "openai_thread_id")
                    // 递归调用，现在有了线程ID
                    self?.sendMessage(message: message, onUpdate: onUpdate, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }
        
        // 1. 添加用户消息到线程
        addMessageToThread(threadId: threadId, message: message) { [weak self] result in
            switch result {
            case .success:
                // 2. 运行助手
                self?.runAssistant(threadId: threadId, onUpdate: onUpdate, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 私有方法
    
    private func createThread(completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/threads")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(AssistantError.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(AssistantError.noData))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? String {
                    self?.threadId = id
                    // 保存线程ID
                    UserDefaults.standard.set(id, forKey: "openai_thread_id")
                    completion(.success(id))
                } else {
                    completion(.failure(AssistantError.threadError("Thread creation failed")))
                }
            } catch {
                completion(.failure(AssistantError.decodingError(error)))
            }
        }
        
        task.resume()
    }
    
    private func retrieveThread(threadId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/threads/\(threadId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let task = urlSession.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(AssistantError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AssistantError.invalidResponse))
                return
            }
            
            if 200...299 ~= httpResponse.statusCode {
                completion(.success(()))
            } else {
                completion(.failure(AssistantError.invalidResponse))
            }
        }
        
        task.resume()
    }
    
    private func addMessageToThread(threadId: String, message: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messageData: [String: Any] = [
            "role": "user",
            "content": message
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: messageData)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = urlSession.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(AssistantError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AssistantError.invalidResponse))
                return
            }
            
            if 200...299 ~= httpResponse.statusCode {
                completion(.success(()))
            } else {
                completion(.failure(AssistantError.invalidResponse))
            }
        }
        
        task.resume()
    }
    
    private func runAssistant(threadId: String, onUpdate: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let runData: [String: Any] = [
            "assistant_id": assistantId,
            "stream": true
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: runData)
        } catch {
            completion(.failure(AssistantError.runError("Run creation failed")))
            return
        }
        
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(AssistantError.networkError(error)))
                return
            }
            
            guard let data = data, let self = self else {
                completion(.failure(AssistantError.noData))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let runId = json["id"] as? String {
                    // 开始轮询运行状态
                    self.pollRunStatus(threadId: threadId, runId: runId, onUpdate: onUpdate, completion: completion)
                } else {
                    completion(.failure(AssistantError.runError("Run creation failed")))
                }
            } catch {
                completion(.failure(AssistantError.decodingError(error)))
            }
        }
        
        task.resume()
    }
    
    private func pollRunStatus(threadId: String, runId: String, onUpdate: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        // 创建一个定时器，每秒检查一次运行状态
        var timer: Timer?
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else {
                timer?.invalidate()
                return
            }
            
            self.checkRunStatus(threadId: threadId, runId: runId) { result in
                switch result {
                case .success(let status):
                    if status == "completed" {
                        // 运行完成，获取消息
                        timer?.invalidate()
                        self.getMessages(threadId: threadId) { messagesResult in
                            switch messagesResult {
                            case .success(let message):
                                onUpdate(message)
                                completion(.success(()))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    } else if status == "failed" || status == "cancelled" {
                        // 运行失败
                        timer?.invalidate()
                        completion(.failure(AssistantError.runError("Run creation failed")))
                    }
                    // 其他状态继续轮询
                case .failure(let error):
                    timer?.invalidate()
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func checkRunStatus(threadId: String, runId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/runs/\(runId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(AssistantError.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(AssistantError.noData))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    completion(.success(status))
                } else {
                    completion(.failure(AssistantError.invalidResponse))
                }
            } catch {
                completion(.failure(AssistantError.decodingError(error)))
            }
        }
        
        task.resume()
    }
    
    private func getMessages(threadId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/messages?limit=1")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(AssistantError.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(AssistantError.noData))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]],
                   let firstMessage = dataArray.first,
                   let role = firstMessage["role"] as? String,
                   role == "assistant",
                   let contentArray = firstMessage["content"] as? [[String: Any]] {
                    
                    // 提取所有文本内容
                    var fullContent = ""
                    for contentItem in contentArray {
                        if let type = contentItem["type"] as? String,
                           type == "text",
                           let textDict = contentItem["text"] as? [String: Any],
                           let value = textDict["value"] as? String {
                            fullContent += value
                        }
                    }
                    
                    if !fullContent.isEmpty {
                        completion(.success(fullContent))
                    } else {
                        completion(.failure(AssistantError.runError("No assistant response")))
                    }
                } else {
                    completion(.failure(AssistantError.runError("No assistant response")))
                }
            } catch {
                completion(.failure(AssistantError.decodingError(error)))
            }
        }
        
        task.resume()
    }
} 