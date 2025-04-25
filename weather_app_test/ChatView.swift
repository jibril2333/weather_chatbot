import SwiftUI
import Combine
// 添加UIKit以便使用UIKit的手势识别器
import UIKit

// 消息结构体，表示聊天消息
struct Message: Identifiable, Equatable {
    let id = UUID() // 唯一标识符
    let content: String // 消息内容
    let isUser: Bool // 是否为用户消息
    let timestamp: Date // 消息发送时间
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

// 聊天视图
struct ChatView: View {
    @State private var messageText = "" // 用户输入的消息文本
    @State private var messages: [Message] = [] // 存储所有消息的数组
    @State private var isLoading = false // 追踪是否正在等待API响应
    @State private var showTypingIndicator = false // 显示"正在输入"指示器
    @State private var currentAssistantMessage = "" // 当前正在生成的助手消息
    @FocusState private var isInputFocused: Bool // 输入框焦点状态
    @State private var scrollToBottom = false // 控制是否滚动到底部
    @State private var showCopyTip = true // 显示复制提示
    @State private var showAllCopiedToast = false // 显示整个对话已复制提示
    
    // 为滚动视图提供滚动锚点
    private let scrollToBottomId = "scrollToBottom"
    
    // OpenAI 聊天服务
    private let openAIService = OpenAIService(
        apiKey: AppEnvironment.shared.openAIApiKey,
        model: AppEnvironment.shared.modelName
    )
    
    var body: some View {
        VStack(spacing: 0) {
            // 显示聊天消息的滚动视图
            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 添加一个欢迎消息，如果没有其他消息的话
                        if messages.isEmpty {
                            welcomeMessage
                        }
                        
                        // 复制提示
                        if showCopyTip && !messages.isEmpty {
                            HStack {
                                Spacer()
                                Text("Tip: Long press or double tap to copy message")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                                    .onTapGesture {
                                        withAnimation {
                                            showCopyTip = false
                                        }
                                    }
                                Spacer()
                            }
                            .padding(.bottom, 4)
                            .transition(.opacity)
                            .onAppear {
                                // 5秒后自动隐藏提示
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                    withAnimation {
                                        showCopyTip = false
                                    }
                                }
                            }
                        }
                        
                        ForEach(messages) { message in
                            if message.content == "Click here to retry the last question" {
                                // 显示重试按钮消息
                                HStack(alignment: .bottom, spacing: 8) {
                                    // 重试图标
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.green)
                                    
                                    // 重试按钮
                                    Button(action: {
                                        // 找到上一个用户消息并重试
                                        if let lastUserMessage = messages.filter({ $0.isUser }).last {
                                            // 取出之前的问题重新发送
                                            messageText = lastUserMessage.content
                                            sendMessage()
                                        }
                                    }) {
                                        Text(message.content)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .cornerRadius(18)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18)
                                                    .stroke(Color.green, lineWidth: 1)
                                            )
                                    }
                                    
                                    Spacer() // 消息靠左对齐
                                }
                                .padding(.horizontal, 4)
                                .id(message.id) // 为每个消息设置一个ID，便于滚动
                            } else {
                                // 普通消息气泡
                                MessageBubble(message: message)
                                    .id(message.id) // 为每个消息设置一个ID，便于滚动
                                    .onAppear {
                                        // 当新消息出现时，隐藏复制提示
                                        if messages.count > 1 && messages.last?.id == message.id {
                                            showCopyTip = false
                                        }
                                    }
                            }
                        }
                        
                        // 显示正在生成的消息
                        if !currentAssistantMessage.isEmpty {
                            MessageBubble(message: Message(
                                content: currentAssistantMessage,
                                isUser: false,
                                timestamp: Date()
                            ))
                            .id("currentMessage")
                        }
                        
                        // "正在输入"指示器
                        if showTypingIndicator {
                            TypingIndicator()
                                .padding(.leading)
                        }
                        
                        // 滚动锚点
                        Color.clear
                            .frame(height: 1)
                            .id(scrollToBottomId)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 5)
                }
                .scrollIndicators(.visible) // 添加滚动条指示器
                .onChange(of: messages) { _ in
                    // 当消息数组变化时，自动滚动到底部
                    withAnimation {
                        scrollView.scrollTo(scrollToBottomId, anchor: .bottom)
                    }
                }
                .onChange(of: currentAssistantMessage) { _ in
                    // 当正在生成的消息变化时，滚动到该消息
                    withAnimation {
                        scrollView.scrollTo("currentMessage", anchor: .bottom)
                    }
                }
                .onChange(of: showTypingIndicator) { _ in
                    // 当typing指示器显示或隐藏时，自动滚动到底部
                    withAnimation {
                        scrollView.scrollTo(scrollToBottomId, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // 用户输入区域
            HStack(spacing: 10) {
                // 输入框
                TextField("Ask about the weather...", text: $messageText)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(18)
                    .focused($isInputFocused)
                    .disabled(isLoading) // 加载时禁用输入
                    .submitLabel(.send) // 设置键盘上的发送按钮
                    .onSubmit {
                        if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage()
                        }
                    }
                
                // 发送按钮
                Button(action: sendMessage) {
                    Image(systemName: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "paperplane.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isLoading)
                .animation(.default, value: messageText)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .navigationTitle("Weather Assistant")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !messages.isEmpty {
                    Button(action: copyAllMessages) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .overlay(
            Group {
                if showAllCopiedToast {
                    VStack {
                        Text("All messages copied")
                            .font(.subheadline)
                            .padding(10)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                showAllCopiedToast = false
                            }
                        }
                    }
                }
            }
        )
        .onAppear {
            // 应用启动时初始化聊天
            initializeChat()
        }
        // 点击背景时收起键盘
        .onTapGesture {
            isInputFocused = false
        }
    }
    
    // 复制所有消息
    private func copyAllMessages() {
        var conversationText = ""
        
        for message in messages {
            let prefix = message.isUser ? "Me: " : "Weather Assistant: "
            conversationText += "\(prefix)\(message.content)\n\n"
        }
        
        UIPasteboard.general.string = conversationText
        
        // 显示已复制提示
        withAnimation {
            showAllCopiedToast = true
        }
        
        // 添加震动反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // 初始化聊天
    private func initializeChat() {
        // 如果需要重置聊天历史
        if AppEnvironment.shared.resetChatHistory {
            openAIService.clearChatHistory()
        }
        
        // 设置系统提示
        openAIService.addSystemPrompt(AppEnvironment.shared.weatherSystemPrompt)
        
        print("Chat view initialized")
    }
    
    // 欢迎消息视图
    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Welcome to Weather Assistant!")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("You can ask me about:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                suggestionButton("What's the weather like in Tokyo today?")
                suggestionButton("What's the forecast for Osaka for the next three days?")
                suggestionButton("Will it rain in Nagoya soon?")
                suggestionButton("What's the current temperature in Fukuoka?")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.vertical, 10)
    }
    
    // 建议按钮
    private func suggestionButton(_ text: String) -> some View {
        Button(action: {
            messageText = text
            sendMessage()
        }) {
            Text(text)
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(16)
        }
    }
    
    // 发送消息的函数
    func sendMessage() {
        let userMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // 添加用户消息到数组
        let newMessage = Message(content: userMessage, isUser: true, timestamp: Date())
        messages.append(newMessage)
        messageText = "" // 清空输入框
        
        // 显示"正在输入"指示器
        showTypingIndicator = true
        isLoading = true
        currentAssistantMessage = ""
        
        // 发送请求到OpenAI API - 使用流式响应
        openAIService.sendMessageStream(userMessage, onUpdate: { messageContent in
            // 更新当前正在生成的消息
            DispatchQueue.main.async {
                currentAssistantMessage = messageContent
            }
        }, completion: { result in
            DispatchQueue.main.async {
                // 隐藏"正在输入"指示器
                showTypingIndicator = false
                isLoading = false
                
                switch result {
                case .success():
                    // 将当前生成的消息添加到消息数组
                    if !currentAssistantMessage.isEmpty {
                        let aiMessage = Message(content: currentAssistantMessage, isUser: false, timestamp: Date())
                        messages.append(aiMessage)
                        currentAssistantMessage = ""
                    }
                    
                case .failure(let error):
                    // 处理错误
                    var errorMessage = "Sorry, I couldn't respond to your question"
                    
                    // 检查具体的错误类型
                    if let openAIError = error as? OpenAIError {
                        switch openAIError {
                        case .networkError(_):
                            errorMessage = "Network connection issue. Please check your network settings and try again."
                        case .apiError(let message):
                            errorMessage = "Sorry, there was a problem processing your request: \(message)"
                        case .noData:
                            errorMessage = "Sorry, no response data received. Please try again later."
                        default:
                            errorMessage = "Sorry, there was a technical issue. Please try again later. Error: \(error.localizedDescription)"
                        }
                    } else {
                        // 其他未捕获的错误类型
                        errorMessage = "Sorry, I couldn't respond to your question: \(error.localizedDescription)"
                    }
                    
                    let messageContent = Message(
                        content: errorMessage,
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(messageContent)
                    currentAssistantMessage = ""
                    
                    // 如果是网络错误或API错误，显示重试按钮
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let retryMessage = Message(
                            content: "Click here to retry the last question",
                            isUser: false,
                            timestamp: Date()
                        )
                        messages.append(retryMessage)
                    }
                }
            }
        })
    }
}

// 长按复制手势识别
struct LongPressGesture: ViewModifier {
    let text: String
    @Binding var showToast: Bool
    
    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) { // 双击也可以复制
                UIPasteboard.general.string = text
                withAnimation {
                    showToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showToast = false
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                UIPasteboard.general.string = text
                withAnimation {
                    showToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showToast = false
                    }
                }
                
                // 添加震动反馈
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
    }
}

// 可选择的文本组件
struct SelectableText: View {
    let text: String
    let foregroundColor: Color
    
    var body: some View {
        if #available(iOS 15.0, *) {
            Text(text)
                .foregroundColor(foregroundColor)
                .textSelection(.enabled)
        } else {
            Text(text)
                .foregroundColor(foregroundColor)
        }
    }
}

// 消息气泡视图
struct MessageBubble: View {
    let message: Message
    @State private var showCopiedToast = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer() // 用户消息靠右对齐
                
                // 用户消息内容
                SelectableText(text: message.content, foregroundColor: .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(18)
                    .cornerRadius(4, corners: [.topRight]) // 右上角特殊处理
                    .modifier(LongPressGesture(text: message.content, showToast: $showCopiedToast))
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                            showCopiedToast = true
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    .overlay(
                        Group {
                            if showCopiedToast {
                                Text("Copied")
                                    .font(.caption)
                                    .padding(6)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .transition(.opacity)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            withAnimation {
                                                showCopiedToast = false
                                            }
                                        }
                                    }
                            }
                        }
                        .offset(y: -30),
                        alignment: .top
                    )
                
                // 用户头像
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            } else {
                // AI头像
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                
                // AI消息内容
                SelectableText(text: message.content, foregroundColor: .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(18)
                    .cornerRadius(4, corners: [.topLeft]) // 左上角特殊处理
                    .modifier(LongPressGesture(text: message.content, showToast: $showCopiedToast))
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                            showCopiedToast = true
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    .overlay(
                        Group {
                            if showCopiedToast {
                                Text("Copied")
                                    .font(.caption)
                                    .padding(6)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .transition(.opacity)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            withAnimation {
                                                showCopiedToast = false
                                            }
                                        }
                                    }
                            }
                        }
                        .offset(y: -30),
                        alignment: .top
                    )
                
                Spacer() // AI消息靠左对齐
            }
        }
        .padding(.horizontal, 4)
    }
}

// "正在输入"指示器
struct TypingIndicator: View {
    @State private var animationOffset = 0.0
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // AI头像
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            
            // 动画点
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundColor(Color(.systemGray))
                        .offset(y: animationOffset(for: index))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Spacer()
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.6).repeatForever()) {
                animationOffset = -5
            }
        }
    }
    
    // 为每个点计算不同的动画偏移
    private func animationOffset(for index: Int) -> Double {
        let delay = 0.2 * Double(index)
        return sin(animationOffset + delay) * 5
    }
}

// 扩展View来支持不同的圆角设置
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// 自定义形状用于部分圆角
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
