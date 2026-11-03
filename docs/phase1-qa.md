# YomiPalette Phase 1：安全な実機テスト

## 作業対象と保護条件
- Playストア版 `com.tjsongwei.tts_text_mp3_mobile` を削除・上書きしない。
- 端末に新規追加する別パッケージ `com.tjsongwei.tts_text_mp3_mobile.qa` を使用する。
- このQA版はGoogleのサンプル広告を使用するDebug版であり、**Play Billingの実際の購入試験には使えない**。
- 購入・復元の確認はPlay内部テストで配布する専用のアップロード署名AABに限る（管理者の承認後に別途アップロード）。

## 別パッケージQA APKの作成と導入

```powershell
cd C:\CodexWorkspace\yomipalette-android
$env:ORG_GRADLE_PROJECT_YOMIPALETTE_SIDE_BY_SIDE_QA='true'
try {
  flutter build apk --debug
} finally {
  Remove-Item Env:ORG_GRADLE_PROJECT_YOMIPALETTE_SIDE_BY_SIDE_QA -ErrorAction SilentlyContinue
}
adb devices
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -n com.tjsongwei.tts_text_mp3_mobile.qa/com.tjsongwei.tts_text_mp3_mobile.MainActivity
```

QAアプリの設定・ファイル・購入状態はPlay版とは別です。アプリの表示名は同じため、混同しないようにしてください。

## MP3保存の正常系・失敗系

1. スマートフォン内に新しいテスト専用フォルダー（例：Download/YomiPalette-QA）を作り、**個人用の既存MP3がないこと**を確認する。
2. QAアプリを起動し、テスト用の短いTXTと端末TTSを選び、上記テストフォルダーを出力先として選択する。
3. MP3を生成し、テストフォルダーでファイルが再生できることを確認する。
4. 同じタイトルの内容を変更して再生成し、目的のMP3が更新され、正常に再生できることを確認する。
5. 書き込み失敗を検証する場合は、**テストフォルダーだけ**権限を取り消す。元のMP3が残ることを確かめる。実データのあるフォルダーやシステムフォルダーは使用しない。
6. SAFプロバイダーがrenameをサポートしない場合、古いファイルは消されず、保存エラーになります。ストレージごとに実機互換性を確認する。

## Billing実機確認

- QA APK（末尾 .qa）のGoogle Play購入テストはできません。
- Play内部テスト用には `.\scripts\build-play.ps1 -InternalTestAds` で別のアップロード署名済みAABを作成できます。Googleサンプル広告と未検証の購入通知を使用するため、**製品版に転用しない**こと。
- バックエンド検証が未稼働の場合、通常のPlay公開用ビルドは購入検証URLを要求して停止します。
- リアル決済禁止：ライセンステスターのみ、Google Playのテスト購入表示を確認する。

## 本番前に残る課題
購入検証バックエンドの構築・秘密情報の設定、Google Play Developer API接続、RTDNとVoided Purchases APIに基づく失効の通知、オフライン時の署名付き権利キャッシュ、端末・Play間の検証を完了すること。**Phase 1のアプリ側インターフェースが動作するだけでは正式公開条件を満たしません。**
