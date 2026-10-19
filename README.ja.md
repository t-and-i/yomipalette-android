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

## PDFの読み込み

テキスト入りPDFに対応しています。「章・ページごと」ではページ順に `Page 001` などの単位を作り、「文字数ごと」では抽出した全ページの本文を連結して分割します。PDFのしおりによる章分けは行いません。文字のないページ（空白・画像のみ）は省略し、タイトルには元のページ番号を残します。

OCRは未対応です。画像・スキャンのみのPDFからは読み込めず、画像ページとテキストページが混在する場合はテキスト部分だけが対象です。パスワード入力が必要なPDFには対応していません。縦書き・段組み・表・特殊なフォントは、読み順や抽出結果が崩れる場合があります。PDFの文字は端末内で抽出し、音声生成時は選択したTTSプロバイダの通常の動作に従います。

## リポジトリの開発

このリポジトリのルートで `flutter analyze`、`flutter test`、`flutter build apk --release` を実行します。EPUBケースと合成PDF素材は `test/fixtures/` に含まれます。PDF素材は `pypdf` 導入後に `python test/fixtures/pdf/generate.py` で再生成できます。LinuxではPDFiumを使うテストをスキップするため、WindowsまたはmacOSでもテストしてください。

バージョンは `pubspec.yaml` で独立して管理します。互換性のためAndroid applicationIdと内部Dartパッケージ名を維持します。過去の統合Releaseは[デスクトップ側](https://github.com/t-and-i/yomipalette-desktop/releases)、今後のAndroid版は[こちら](https://github.com/t-and-i/yomipalette-android/releases)で管理します。

## ライセンス

[MIT License](LICENSE)で公開しています。Copyright (c) 2026 YuluEthan.

## アプリ情報とプライバシー

画面上部の情報アイコンから、インストール済みのバージョン・ビルド番号、オフラインで読めるプライバシー説明、ライセンス、GitHubのお問い合わせ先を確認できます。TTS選択欄からもプライバシー説明を開けます。Google Play申請用のプライバシーポリシー公開URLは未設定です。

## Google Play向けAAB（ローカル作成）

PowerShellをリポジトリのルートで開きます。初回のみ `powershell -ExecutionPolicy Bypass -File scripts/initialize-play-signing.ps1` を実行してアップロード鍵を作成します。既存の鍵は上書きしません。

以後は `powershell -ExecutionPolicy Bypass -File scripts/build-play.ps1` で署名済みAABを作成します。生成先は `build/app/outputs/bundle/release/app-release.aab`。署名と保存済みの公開証明書との一致も確認します。アップロードは行いません。

鍵・パスワード入りの設定ファイル・公開証明書は `%USERPROFILE%/.android/yomipalette-signing/` に保存されます。このフォルダーを暗号化した外部媒体などへバックアップしてください。`key.properties` は平文のパスワードを含むため、鍵とともにGitへ追加したり共有したりしないでください。パスワードは生成時にランダム作成され、画面には表示しません。公開証明書 `upload-certificate.pem` だけはPlay Consoleへの登録に利用できます。

スクリプトはAndroid Studioの標準インストール先のJBRを使用します。別の場所では `-JavaBin`、既存の鍵を利用する場合はビルド時に `-SigningProperties` で変更できます。設定ファイルはUTF-8、`storeFile` は絶対パスと `/` 区切りを使い、`storePassword`、`keyAlias`、`keyPassword` を指定します。同じフォルダーに公開証明書を置いてください。

通常のデバッグ実行と `flutter build apk --release` はテスト用デバッグ署名のままです。通常の `flutter build appbundle --release` は誤提出防止のため拒否します。専用スクリプトはGradleプロパティ `PLAY_RELEASE=true` と `PLAY_SIGNING_PROPERTIES` を実行中だけ渡します。GitHub Actionsには秘密鍵を登録していません。

初回提出時はPlay App Signingを設定します。Googleが配信用の署名鍵を管理する場合、このアップロード鍵とは別の鍵で配布APKが署名されます。その場合、GitHubのテストAPKや手元でアップロード鍵で署名したAPKからPlay版への上書き更新はできません。アンインストール前に必要な音声ファイルを保存してください。アプリIDは変更しません。バージョンは `pubspec.yaml` で管理し、提出済みのversionCodeを再利用しないでください。

この作業は提出用ファイルの準備です。プライバシーポリシー公開、データセーフティ等の申告、テスト、審査・公開は別途必要です。AABはAPKのように端末へ直接インストールできません。
