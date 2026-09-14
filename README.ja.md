# YomiPalette Android

電子書籍を、好きな声で。

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

Android向けのFlutterアプリです。**yomipalette-android** で独立して管理します。Windows・macOS版は [yomipalette-desktop](https://github.com/t-and-i/yomipalette-desktop) で開発します。iOSの開発は終了し、このリポジトリはAndroidのみを対象とします。

## 初期版の対応範囲

- TXT・EPUB・PDFの読み込み。TXTはUTF-8、UTF-16、UTF-32、CP932／Shift_JIS、GB18030、Big5を自動判別し、手動指定にも対応
- 章ごと／指定文字数ごとの分割（初期値5000文字）
- 選択した出力単位の約15秒音声確認。未選択時は先頭を使用
- Edge TTS、Azure Speech、Google Cloud TTSの音声一覧取得・MP3生成
- APIキーをAndroid Keystoreで安全に保存、またはセッション中だけ保持
- MP3のアプリ文書領域への保存と共有
- ユーザーが選択したフォルダへの直接保存。AndroidではOSの永続的なフォルダ権限を使用
- 使用制限や通信エラーで停止した場合、完成済みファイルを維持して未完了部分から生成を再開
- 日本語・英語・簡体中国語UI

MOBI・AZW・AZW3（Kindle）の読み込みは**モバイル版では現時点未対応**です。デスクトップ版は Python の `mobi` パッケージでこれらに対応しています（AZW3 の KF8 EPUB は章構造を再利用）。モバイルではデスクトップ版をお使いいただくか、Calibre などで事前に EPUB へ変換してから取り込んでください。

TXTの文字コードは初期状態で「自動判別」です。文字化けする場合は、ファイル欄の「TXT文字コード」から文字コードを指定すると、選択済みファイルを元データから読み直します。文字コードの自動判別は100%保証できないため、判別結果が正しくない場合は手動指定を使用してください。EPUB内部の文字コード処理には影響しません。

「出力先を選択」で保存先を指定できます。書き込み権限がない場合はエラーを表示します。未指定の場合はアプリ専用領域へ生成して共有画面を表示し、共有画面を閉じた後に今回のアプリ内コピーを削除するか確認します。保持したコピーはアプリのアンインストールまたはアプリデータ消去時に削除されます。

## モバイル版で対応しない機能と理由

### GoogleサービスアカウントJSON

モバイル版では読み込み・保存ともに対応しません。サービスアカウントJSONには、Google Cloudプロジェクトへサービスアカウントとしてアクセスできる秘密鍵が含まれます。アプリの安全領域に保存しても、API呼び出し時には復号された認証情報をプロセスが使用するため、root化・脱獄端末や動的解析に対して完全には保護できません。漏えい時に別端末からも悪用でき、通常のAPIキーより影響が大きいためです。

Google Cloud TTSは、利用者自身のAPIキー方式だけを提供します。利用者はGoogle Cloud ConsoleでCloud Text-to-Speech APIを有効化し、利用量上限と適切なAPIキー制限を設定してください。

### OpenAI

初期版では対応しません。OpenAIは秘密APIキーをブラウザやモバイルアプリなどのクライアント側コードへ露出しないよう案内しています。Android Keystoreは保存時の保護には有効ですが、実行中のキー抽出までは防げないため、将来バックエンド中継方式を用意する場合に再検討します。デスクトップ版のOpenAI機能は変更しません。

### Edge TTS

APIキー不要の選択肢としてモバイル版でも利用できます。ただし、デスクトップ版と同様にMicrosoft EdgeのRead Aloud向け非公式サービスエンドポイントを利用しており、Microsoftの公開・保証されたFlutter SDKではありません。サービス側の仕様変更によって突然利用できなくなる可能性があります。安定性や業務用途の保証が必要な場合はAzure Speechを使用してください。

### その他の差異

- デスクトップ版のGoogleサービスアカウント認証、OpenAI、Edge TTSには影響しません。
- MP3は選択したフォルダへ直接保存できます。出力先を指定しない場合はアプリ専用領域に生成し、共有シートから他アプリへ渡せます。
- APIキーを安全領域へ保存しても、root化・脱獄、デバッガ接続、実行時フックに対する完全な保護は保証できません。

## 開発環境の準備

Flutter 3.47以降（Dart 3.13以降）とAndroid SDKをインストールし、`flutter doctor`のAndroid要件を満たしてください。

```bash
cd yomipalette-android
flutter pub get
flutter test
flutter run
```

Androidのホストプロジェクトはリポジトリに含まれます。APIキーや署名ファイルをGitへコミットしないでください。

GitHub Actionsは解析、テスト、AndroidデバッグAPKを検証します。新しい `v*` タグをpushすると、このリポジトリにreleaseモードのAPKを公開します。現在はデバッグ鍵で署名するテスト用ビルドです。本番配布・Google Play公開には正式な署名設定が別途必要です。Appleの開発環境は不要です。

## YomiPaletteの開発を応援する

YomiPaletteが役に立ったら、開発の継続を応援していただけるとうれしいです。いただいた支援は、機能改善・不具合修正・Windows／Androidでの動作検証に役立てます。支援は任意で、支援の有無によって利用できる機能は変わりません。

- [GitHub Sponsorsで開発を応援する](https://github.com/sponsors/tjsongwei)
- [Buy Me a Coffeeで開発を応援する](https://buymeacoffee.com/tjsongweic)

## PDFの読み込み

テキスト入りPDFに対応しています。「章・ページごと」ではページ順に `Page 001` などの単位を作り、「文字数ごと」では抽出した全ページの本文を連結して分割します。PDFのしおりによる章分けは行いません。文字のないページ（空白・画像のみ）は省略し、タイトルには元のページ番号を残します。

OCRは未対応です。画像・スキャンのみのPDFからは読み込めず、画像ページとテキストページが混在する場合はテキスト部分だけが対象です。パスワード入力が必要なPDFには対応していません。縦書き・段組み・表・特殊なフォントは、読み順や抽出結果が崩れる場合があります。PDFの文字は端末内で抽出し、音声生成時は選択したTTSプロバイダの通常の動作に従います。

## リポジトリの開発

このリポジトリのルートで `flutter analyze`、`flutter test`、`flutter build apk --release` を実行します。EPUBケースと合成PDF素材は `test/fixtures/` に含まれます。PDF素材は `pypdf` 導入後に `python test/fixtures/pdf/generate.py` で再生成できます。LinuxではPDFiumを使うテストをスキップするため、WindowsまたはmacOSでもテストしてください。

バージョンは `pubspec.yaml` で独立して管理します。互換性のためAndroid applicationIdと内部Dartパッケージ名を維持します。過去の統合Releaseは[デスクトップ側](https://github.com/t-and-i/yomipalette-desktop/releases)、今後のAndroid版は[こちら](https://github.com/t-and-i/yomipalette-android/releases)で管理します。

## ライセンス

[MIT License](LICENSE)で公開しています。Copyright (c) 2026 YuluEthan.
