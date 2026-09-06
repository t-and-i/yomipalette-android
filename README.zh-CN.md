# YomiPalette Mobile

用喜欢的声音，把电子书变成有声书。

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

这是Android和iOS的Flutter客户端，作为独立项目保存在桌面版仓库的`mobile/`目录中。

## 初始版本范围

- 读取TXT、EPUB和PDF；TXT支持自动检测及手动选择UTF-8、UTF-16、UTF-32、CP932／Shift_JIS、GB18030和Big5
- 按章节或字符上限拆分（默认5000字符）
- 试听所选单元约15秒；未选择时使用第一个单元
- Edge TTS、Azure Speech和Google Cloud TTS
- 使用Android Keystore／iOS Keychain保存凭据，或仅在当前会话保留
- 生成、保存和分享MP3
- 直接保存到用户选择的文件夹；Android会保留系统授予的文件夹权限
- 因配额或网络错误停止后，从第一个未完成单元继续生成
- 英语、日语、简体中文界面

MOBI、AZW、AZW3（Kindle）格式**在移动版暂不支持**。桌面版通过 Python 的 `mobi` 包读取这些文件（AZW3 的 KF8 EPUB 会复用为章节结构）。在移动设备上请使用桌面版本，或先用 Calibre 等工具将 Kindle 文件转换为 EPUB 后再导入。

TXT字符编码默认为“自动检测”。如果检测结果不正确，可在TXT字符编码栏中手动选择编码，应用会从原始文件数据重新读取。旧式编码无法保证每次都能完全自动识别；此功能不影响EPUB处理。

可通过“选择输出文件夹”直接指定保存位置；没有写入权限时会显示错误。未指定时，文件生成在应用专用存储并打开分享界面。关闭分享界面后，应用会询问是否删除本次应用内副本；保留的副本会在卸载应用或清除应用数据时删除。

## 不支持的功能及原因

- **Google服务账号JSON：**其中包含可重复使用的私钥。安全存储只能保护静态数据，无法保证在root、越狱或运行时注入环境中不被提取，因此移动版只支持API密钥。
- **OpenAI：**OpenAI不建议在移动客户端暴露秘密API密钥。Keystore／Keychain无法防止运行时提取，待将来提供后端中转时再评估。
- **Edge TTS：**无需API密钥即可使用，但它使用Microsoft Edge Read Aloud的非官方服务端点，并不是受支持的Flutter公共SDK。服务端协议变更可能导致功能突然失效；需要稳定服务合同时请使用Azure Speech。

这些限制仅适用于移动版，不影响桌面版。开发环境和完整安全说明请参阅[日语README](README.ja.md)。

## 支持 YomiPalette 开发

如果 YomiPalette 对您有帮助，欢迎支持项目的持续开发。您的支持将用于功能改进、问题修复以及 Windows 和 Android 的兼容性测试。支持完全自愿，不影响您可以使用的应用功能。

- [通过 GitHub Sponsors 支持开发](https://github.com/sponsors/tjsongwei)
- [通过 Buy Me a Coffee 支持开发](https://buymeacoffee.com/tjsongweic)

## PDF导入

支持含文本的PDF。“按章节／页”按原始页序生成 `Page 001` 等单元；“按字符数”先合并所有提取的页面文本再分割。不根据PDF书签划分章节。无文本的页面（空白或纯图片）会被跳过，标题保留原始页码。

暂不支持OCR。无法读取纯图片或扫描PDF；混合文档只提取其中的文本页面。不支持需要输入密码的PDF。竖排、多栏、表格及特殊字体的阅读顺序或提取结果可能不准确。PDF文本在设备上提取；语音生成遵循所选TTS服务的通常行为。
