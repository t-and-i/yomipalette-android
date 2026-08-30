# TTS Text to MP3 Mobile

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

Android・iOS向けのFlutterアプリです。デスクトップ版とは別プロジェクトですが、同じリポジトリの`mobile/`で管理します。

## 初期版の対応範囲

- TXT・EPUBの読み込み
- 章ごと／指定文字数ごとの分割（初期値5000文字）
- 選択した出力単位の約15秒音声確認。未選択時は先頭を使用
- Azure SpeechとGoogle Cloud TTSの音声一覧取得・MP3生成
- APIキーをAndroid Keystore／iOS Keychainで安全に保存、またはセッション中だけ保持
- MP3のアプリ文書領域への保存と共有
- 日本語・英語・簡体中国語UI

## モバイル版で対応しない機能と理由

### GoogleサービスアカウントJSON

モバイル版では読み込み・保存ともに対応しません。サービスアカウントJSONには、Google Cloudプロジェクトへサービスアカウントとしてアクセスできる秘密鍵が含まれます。アプリの安全領域に保存しても、API呼び出し時には復号された認証情報をプロセスが使用するため、root化・脱獄端末や動的解析に対して完全には保護できません。漏えい時に別端末からも悪用でき、通常のAPIキーより影響が大きいためです。

Google Cloud TTSは、利用者自身のAPIキー方式だけを提供します。利用者はGoogle Cloud ConsoleでCloud Text-to-Speech APIを有効化し、利用量上限と適切なAPIキー制限を設定してください。

### OpenAI

初期版では対応しません。OpenAIは秘密APIキーをブラウザやモバイルアプリなどのクライアント側コードへ露出しないよう案内しています。Keychain／Keystoreは保存時の保護には有効ですが、実行中のキー抽出までは防げないため、将来バックエンド中継方式を用意する場合に再検討します。デスクトップ版のOpenAI機能は変更しません。

### Edge TTS

初期版では対応しません。デスクトップ版はPythonの`edge-tts`ライブラリに依存していますが、Flutter／Dart向けに同じ契約と動作を保証する公式SDKがありません。非公式WebSocket仕様を独自実装するとサービス側変更で動作しなくなる可能性が高いため、互換性と利用条件を確認できるまで除外します。

### その他の差異

- デスクトップ版のGoogleサービスアカウント認証、OpenAI、Edge TTSには影響しません。
- MP3の保存先は任意のフォルダではなく、OSが管理するアプリ文書領域です。生成後に共有シートからファイルアプリや他アプリへ保存できます。
- APIキーを安全領域へ保存しても、root化・脱獄、デバッガ接続、実行時フックに対する完全な保護は保証できません。

## 開発環境の準備

Flutter SDKをインストールし、`flutter doctor`のAndroid/iOS要件を満たしてください。iOSのビルドと署名にはmacOSとXcodeが必要です。

```bash
cd mobile
flutter pub get
flutter test
flutter run
```

AndroidとiOSのホストプロジェクトはリポジトリに含まれます。APIキーや署名ファイルをGitへコミットしないでください。

GitHub Actionsは解析、テスト、AndroidデバッグAPK、署名なしiOSビルドを検証します。ストア公開用Android App BundleとiOSアーカイブには、それぞれの開発者アカウントとリポジトリ外で管理する署名情報を別途設定する必要があります。CIのデバッグAPKを一般配布しないでください。
