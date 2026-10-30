# YomiPalette Google Play Billing 設定手順

## アプリ内商品

- アプリ: YomiPalette / Android
- Package name: `com.tjsongwei.tts_text_mp3_mobile`
- 商品ID: `remove_ads`（コードと完全一致）
- 種類: 非消費型・買い切り（永久広告解除）
- 日本の価格: 500円（Play Consoleで設定）
- アプリ内の購入価格はGoogle Playから取得した金額を表示

Play Consoleの「収益化」→「商品」→「アプリ内商品」または「1回限りの商品」で商品を登録し、有効化してください。商品未登録時はアプリ内の購入ボタンが無効になります。

## 内部テスト

1. Play Consoleのライセンステスターにテスト用Googleアカウントを登録
2. 内部テストに署名済みAABをアップロードし、テストユーザーに参加してもらう
3. ライセンステスターの端末でGoogle Playからインストールする
4. 購入・購入キャンセル・保留中・購入復元・再起動後の広告解除状態をテスト
5. 別端末でも同じGoogleアカウントから復元できるか確認

**テストトラックでも、ライセンステスター以外は実際の請求が発生する場合があります。**

## 本番リリース前の必須事項（未完了）

現在はGoogle Play Billingの購入通知とローカルにキャッシュした購入済み状態でバナーを制御します。これは内部テスト用であり、サーバーでの購入トークンの検証・返金・取り消し検知は未実装です。公開前にGoogle Play Developer APIで購入トークンを検証するバックエンドを追加してください。Play Developer APIの鍵をアプリに埋め込まないでください。

プライバシーポリシー https://t-and-i.biz/yomipalette/privacy/ にGoogle Play Billingと端末内の広告解除状態保存を追記し、データセーフティを最終確認してください。

## アプリアイコン

以前作成した開いた本・音波の画像を `android/app/src/main/res/mipmap-*/ic_launcher.png` に適用しました。編集用縮小画像は `assets/branding/yomipalette_icon.webp` です。Google Playストア用の512×512PNGは別途登録します。
