# 天气助手应用 (Weather Assistant)

一个使用 SwiftUI 开发的天气应用，集成了 OpenAI GPT-4 的智能对话功能。

## 功能特点

- 🌤️ 实时天气显示
  - 支持日本主要城市（东京、大阪、名古屋、福冈）
  - 显示温度、湿度、风速、降水等信息
  - 使用 Open-Meteo JMA API 获取准确数据

- 💬 智能天气助手
  - 基于 GPT-4 的智能对话
  - 支持自然语言查询天气
  - 提供天气建议和解释

## 技术栈

- SwiftUI
- Open-Meteo JMA API
- OpenAI GPT-4 API
- CoreLocation

## 开发状态

🚧 项目正在开发中，尚未完成的功能：

- [ ] 天气预警通知
- [ ] 多语言支持
- [ ] 天气趋势图表
- [ ] 自定义城市添加
- [ ] 天气数据本地缓存
- [ ] 离线模式支持
- [ ] 深色模式优化
- [ ] 单元测试覆盖
- [ ] 性能优化

## 安装要求

- iOS 15.0+
- Xcode 13.0+
- Swift 5.5+

## 配置说明

1. 获取 Open-Meteo API key（目前不需要）
2. 获取 OpenAI API key
3. 在项目中配置 API keys

## 项目结构

```
weather_app_test/
├── weather_app_test/                    # 主项目目录
│   ├── OpenAIAssistantService.swift     # OpenAI 助手服务
│   ├── OpenAIService.swift              # OpenAI 基础服务
│   ├── ContentView.swift                # 天气主界面
│   ├── ChatView.swift                   # 聊天界面
│   ├── weather_app_testApp.swift        # 应用入口
│   ├── Assets.xcassets/                 # 资源目录
│   └── Preview Content/                 # 预览内容
├── weather_app_testTests/               # 单元测试目录
├── weather_app_testUITests/             # UI测试目录
└── ChatBot.xcodeproj/                   # Xcode项目文件
```

## 贡献指南

欢迎提交 Issue 和 Pull Request 来帮助改进这个项目。

## 许可证

MIT License 