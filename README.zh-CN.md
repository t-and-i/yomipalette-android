# TTS Text to MP3 Mobile

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

这是Android和iOS的Flutter客户端，作为独立项目保存在桌面版仓库的`mobile/`目录中。

## 初始版本范围

- 读取TXT和EPUB
- 按章节或字符上限拆分（默认5000字符）
- 试听所选单元约15秒；未选择时使用第一个单元
- Azure Speech和Google Cloud TTS API密钥认证
- 使用Android Keystore／iOS Keychain保存凭据，或仅在当前会话保留
- 生成、保存和分享MP3
- 英语、日语、简体中文界面

## 不支持的功能及原因

- **Google服务账号JSON：**其中包含可重复使用的私钥。安全存储只能保护静态数据，无法保证在root、越狱或运行时注入环境中不被提取，因此移动版只支持API密钥。
- **OpenAI：**OpenAI不建议在移动客户端暴露秘密API密钥。Keystore／Keychain无法防止运行时提取，待将来提供后端中转时再评估。
- **Edge TTS：**桌面版依赖Python的`edge-tts`库，目前没有能够保证相同接口和行为的Flutter／Dart官方SDK。

这些限制仅适用于移动版，不影响桌面版。开发环境和完整安全说明请参阅[日语README](README.ja.md)。

