# YomiPalette Google Play Billing 設定手順

## アプリ内商品

- アプリ: YomiPalette / Android
- Package name: `com.tjsongwei.tts_text_mp3_mobile`
- 新商品ID: `full_access`（買い切り・永久利用権）
- 旧商品ID: `remove_ads`（既存購入者の復元用）
- 種類: 非消費型・買い切り（初回30日は無料、その後に手動購入で永久利用権。自動課金なし）
- 日本の予定価格: 500円（Play Consoleで新商品に設定）
- アプリ内の購入価格はGoogle Playから取得した金額を表示

Play Consoleの「収益化」→「商品」→「アプリ内商品」または「1回限りの商品」で商品を登録し、有効化してください。新商品 `full_access` が未登録または無効の場合、購入ボタンは使用できません。既存 `remove_ads` 購入の復元は引き続き必要です。

## 内部テスト

1. Play Consoleのライセンステスターにテスト用Googleアカウントを登録
2. 内部テストに署名済みAABをアップロードし、テストユーザーに参加してもらう
3. ライセンステスターの端末でGoogle Playからインストールする
4. 購入・購入キャンセル・保留中・購入復元・再起動後の利用権状態をテスト
5. 別端末でも同じGoogleアカウントから復元できるか確認

**テストトラックでも、ライセンステスター以外は実際の請求が発生する場合があります。**

## Phase 1：購入処理の安全性と残るバックエンド作業

- 購入イベントは受信順に直列処理。重複通知は同じ購入トークンの二重 acknowledge を避けます。
- アプリは新しい購入だけでなく「復元」時も検証サービスに問い合わせます。明示的な `verified` 応答の場合のみ利用権を許可し、`rejected` なら権利を失効させ、通信エラー時は新たな権利を付与しません。
- **本番版では旧 `ad_free_owned_v1` ローカルフラグを信用しません。** 検証バックエンドがない場合、購入ボタンは無効です。
- **本番購入検証未完了**：CloudflareステージングにはPlay Integrity、RTDN、Voided Purchases API連携がありますが、新商品と旧商品の実購入・返金・復元の総合検証、および署名付きオフライン権利キャッシュは引き続き必要です。
- 既存の購入者には起動後の復元・検証が必要です。ネットワーク障害時に利用権を維持するには、短期有効な署名付き権利トークン等を追加する必要があります。

### アプリと検証バックエンド間のAPI契約

本番AABには信頼できる HTTPS エンドポイントを指定します。

```text
scripts/build-play.ps1 -PurchaseVerifierUrl https://example.com/verify
```

アプリから検証先へ次のJSONを `POST` します。

```json
{
  "packageName": "com.tjsongwei.tts_text_mp3_mobile",
  "productId": "full_access",
  "purchaseToken": "<Google Play purchase token>",
  "requestId": "<32 lowercase hex characters>",
  "integrityToken": "<Play Integrity Standard token>"
}
```

バックエンドが **Google Play Developer API** で実際に購入済み・未失効と確認した場合だけ HTTP 200 / `{"status":"verified"}` を返します。払い戻しや無効購入は HTTP 200 / `{"status":"rejected"}`。タイムアウト、サーバー障害、未定義応答はアプリ側で `unavailable` と扱い、権利を付与しません。**単にリクエストが来たという理由で verified を返してはいけません。**

検証先は購入トークンの重複利用・Google PlayのアプリID・商品ID・購入状態・失効状況をチェックし、Googleサービスアカウントの秘密鍵はサーバーのシークレットとして保持します。RTDNの受信後はGoogleのAPIを再確認し、返金等に応じて権利を失効させます。アプリ側からの復元だけで返金の全面的な捕捉はできません。

### 内部テスト専用のビルド

```powershell
.\scripts\build-play.ps1 -InternalTestBilling
```

このスイッチは **未検証レシートによるライセンステスト（QAのみ）** を有効にします。製品版トラックへの昇格は禁止です。Google Playに新しいAABをアップロードするときはversionCodeが未使用であることを確認してください。通常の `build-play.ps1` は検証バックエンドURLが未設定なら明示的に失敗します。

プライバシーポリシー https://t-and-i.biz/yomipalette/privacy/ にGoogle Play Billingと購入トークンの処理を反映し、データセーフティを最終確認してください。

## アプリアイコン

以前作成した開いた本・音波の画像を `android/app/src/main/res/mipmap-*/ic_launcher.png` に適用しました。編集用縮小画像は `assets/branding/yomipalette_icon.webp` です。Google Playストア用の512×512PNGは別途登録します。
