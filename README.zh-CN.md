# YomiPalette Android

用喜欢的声音，把电子书变成有声书。

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

这是Android版YomiPalette的Flutter客户端，由 **yomipalette-android** 独立维护。Windows和macOS版请参阅 [yomipalette-desktop](https://github.com/t-and-i/yomipalette-desktop)。iOS开发已结束，本仓库仅面向Android。

## 初始版本范围

- 读取TXT、EPUB和PDF；TXT支持自动检测及手动选择UTF-8、UTF-16、UTF-32、CP932／Shift_JIS、GB18030和Big5
- 按章节或字符上限拆分（默认5000字符）
- 试听所选单元约15秒；未选择时使用第一个单元
- Edge TTS、Azure Speech和Google Cloud TTS
- 使用Android Keystore保存凭据，或仅在当前会话保留
- 生成、保存和分享MP3
- 直接保存到用户选择的文件夹；Android会保留系统授予的文件夹权限
- 因配额或网络错误停止后，从第一个未完成单元继续生成
- 英语、日语、简体中文界面

MOBI、AZW、AZW3（Kindle）格式**在移动版暂不支持**。桌面版通过 Python 的 `mobi` 包读取这些文件（AZW3 的 KF8 EPUB 会复用为章节结构）。在移动设备上请使用桌面版本，或先用 Calibre 等工具将 Kindle 文件转换为 EPUB 后再导入。

TXT字符编码默认为“自动检测”。如果检测结果不正确，可在TXT字符编码栏中手动选择编码，应用会从原始文件数据重新读取。旧式编码无法保证每次都能完全自动识别；此功能不影响EPUB处理。

可通过“选择输出文件夹”直接指定保存位置；没有写入权限时会显示错误。未指定时，文件生成在应用专用存储并打开分享界面。关闭分享界面后，应用会询问是否删除本次应用内副本；保留的副本会在卸载应用或清除应用数据时删除。

## 不支持的功能及原因

- **Google服务账号JSON：**其中包含可重复使用的私钥。安全存储只能保护静态数据，无法保证在root、越狱或运行时注入环境中不被提取，因此移动版只支持API密钥。
- **OpenAI：**OpenAI不建议在移动客户端暴露秘密API密钥。Android Keystore无法防止运行时提取，待将来提供后端中转时再评估。
- **Edge TTS：**无需API密钥即可使用，但它使用Microsoft Edge Read Aloud的非官方服务端点，并不是受支持的Flutter公共SDK。服务端协议变更可能导致功能突然失效；需要稳定服务合同时请使用Azure Speech。

这些限制仅适用于移动版，不影响桌面版。开发环境和完整安全说明请参阅[日语README](README.ja.md)。

## PDF导入

支持含文本的PDF。“按章节／页”按原始页序生成 `Page 001` 等单元；“按字符数”先合并所有提取的页面文本再分割。不根据PDF书签划分章节。无文本的页面（空白或纯图片）会被跳过，标题保留原始页码。

暂不支持OCR。无法读取纯图片或扫描PDF；混合文档只提取其中的文本页面。不支持需要输入密码的PDF。竖排、多栏、表格及特殊字体的阅读顺序或提取结果可能不准确。PDF文本在设备上提取；语音生成遵循所选TTS服务的通常行为。

## 开发环境与验证

安装Flutter 3.47或更高版本（Dart 3.13或更高版本）和Android SDK，并满足 `flutter doctor` 的Android要求。在仓库根目录执行：

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

EPUB案例与合成PDF样本位于 `test/fixtures/`。安装 `pypdf` 后可执行 `python test/fixtures/pdf/generate.py` 重新生成PDF样本。Linux测试跳过原生PDFium案例，请在Windows或macOS上补充验证。

GitHub Actions执行分析、测试和Android调试APK构建。推送新的 `v*` 标签会构建release模式的APK并发布到本仓库。当前使用调试签名，仅供测试；正式分发和Google Play发布需要另行配置正式签名。请勿提交API密钥或签名文件。

版本在 `pubspec.yaml` 中独立管理。为保持兼容，保留Android applicationId与内部Dart包名。以往的合并Release位于[桌面版仓库](https://github.com/t-and-i/yomipalette-desktop/releases)，今后的Android版本位于[本仓库](https://github.com/t-and-i/yomipalette-android/releases)。

## 许可证

采用 [MIT License](LICENSE)。Copyright (c) 2026 YuluEthan.

## 应用信息与隐私

点击顶部的信息图标，可查看已安装版本及构建编号、离线隐私说明、许可证和GitHub联系链接。TTS选择栏下方也可打开隐私说明。尚未配置用于Google Play提交的公开隐私政策网址。

## Google Play签名AAB（本地构建）

在仓库根目录的PowerShell中，首次运行 `powershell -ExecutionPolicy Bypass -File scripts/initialize-play-signing.ps1` 创建上传密钥；之后运行 `powershell -ExecutionPolicy Bypass -File scripts/build-play.ps1`。输出为 `build/app/outputs/bundle/release/app-release.aab`，脚本验证签名及其与保存的公开证书的一致性，不会上传。

密钥、含随机生成明文密码的 `key.properties` 和公开证书位于Git之外的 `%USERPROFILE%/.android/yomipalette-signing/`，仅当前Windows用户有访问权限。请将整个目录备份到加密存储，切勿提交或分享密钥和密码文件。只有 `upload-certificate.pem` 是公开证书。脚本不会覆盖已有目录。可用 `-JavaBin` 指定其他JBR路径，构建时可用 `-SigningProperties` 指定其他UTF-8配置文件（storeFile、storePassword、keyAlias、keyPassword；storeFile使用绝对路径和正斜杠），公开证书须放在同一目录。

普通调试运行及release APK仍使用测试用调试签名。release AAB必须通过专用脚本显式启用Play签名，缺少密钥时不会回退。尚未配置CI密钥或上传发布。Play App Signing需另行设置；Google管理的分发密钥与上传密钥、调试签名不同，因此测试APK不能直接覆盖更新为该Play版本。保持应用ID不变，后续提交时递增versionCode。AAB不能像APK一样直接安装。隐私政策网址、Play申报、测试及发布仍需另行完成。
