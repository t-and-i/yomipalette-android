# TTS Text to MP3 Mobile

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

这是Android和iOS的Flutter客户端，作为独立项目保存在桌面版仓库的`mobile/`目录中。

## 初始版本范围

- 读取TXT和EPUB；TXT支持自动检测及手动选择UTF-8、UTF-16、UTF-32、CP932／Shift_JIS、GB18030和Big5
- 按章节或字符上限拆分（默认5000字符）
- 试听所选单元约15秒；未选择时使用第一个单元
- Edge TTS、Azure Speech和Google Cloud TTS
- 使用Android Keystore／iOS Keychain保存凭据，或仅在当前会话保留
- 生成、保存和分享MP3
- 直接保存到用户选择的文件夹；Android会保留系统授予的文件夹权限
- 因配额或网络错误停止后，从第一个未完成单元继续生成
- 英语、日语、简体中文界面

TXT字符编码默认为“自动检测”。如果检测结果不正确，可在TXT字符编码栏中手动选择编码，应用会从原始文件数据重新读取。旧式编码无法保证每次都能完全自动识别；此功能不影响EPUB处理。

可通过“选择输出文件夹”直接指定保存位置；没有写入权限时会显示错误。未指定时，文件生成在应用专用存储并打开分享界面。关闭分享界面后，应用会询问是否删除本次应用内副本；保留的副本会在卸载应用或清除应用数据时删除。

## 不支持的功能及原因

- **Google服务账号JSON：**其中包含可重复使用的私钥。安全存储只能保护静态数据，无法保证在root、越狱或运行时注入环境中不被提取，因此移动版只支持API密钥。
- **OpenAI：**OpenAI不建议在移动客户端暴露秘密API密钥。Keystore／Keychain无法防止运行时提取，待将来提供后端中转时再评估。
- **Edge TTS：**无需API密钥即可使用，但它使用Microsoft Edge Read Aloud的非官方服务端点，并不是受支持的Flutter公共SDK。服务端协议变更可能导致功能突然失效；需要稳定服务合同时请使用Azure Speech。

这些限制仅适用于移动版，不影响桌面版。开发环境和完整安全说明请参阅[日语README](README.ja.md)。
