# YomiPalette Google Play購入検証バックエンド（未デプロイ）

YomiPaletteの `remove_ads`（非消耗型買い切り商品）用に、**Cloudflare Workers + D1** で動作する購入検証の基礎実装です。現在はローカルテスト済みですが、**本番利用に必要な設定・不正利用対策が未完了のため、公開してはいけません**。

## 仕組み

1. Androidアプリが購入イベント・復元イベントを受信し、既存の `BackendPurchaseVerifier` がHTTPSで `POST /verify` を実行します。
2. WorkerはアプリIDと商品IDを固定し、サービスアカウントのOAuth 2.0アクセス・トークンで **Google Play Developer API `purchases.productsv2.getproductpurchasev2`** を呼び出します。
3. `purchaseStateContext.purchaseState` が `PURCHASED` かつ `productLineItem` に `remove_ads` があり、消費・全額返金済みでなければ候補とします。
4. D1に記録した返金・取り消し済みトークンのSHA-256ハッシュと照合します。**返金情報の同期が12時間以内に成功していなければ、購入者にも `unavailable` を返します**。
5. WorkerのCron Triggerが6時間ごとに **Voided Purchases API** を照会し、過去の同期と2日間重複する期間を取り込んでD1に失効情報を追加します。初回は29日前から収集します。
6. 戻り値はアプリ側の既存API契約 `{"status":"verified"|"rejected"|"unavailable"}` に対応します（`unavailable` はHTTP 503）。

`/verify` の購入トークンはGoogleへの照会にのみ使用します。D1には**購入トークンそのものではなくSHA-256ハッシュ**を保存します。サービスアカウント秘密鍵はCloudflare Secrets Storeに置き、アプリ・Git・ログ・HTTP応答に含めません。

### 現行アプリとの契約

```http
POST /verify
Content-Type: application/json

{
  "packageName": "com.tjsongwei.tts_text_mp3_mobile",
  "productId": "remove_ads",
  "purchaseToken": "<Google Play purchase token>"
}
```

- Google Playで購入済み・未失効：HTTP 200 `{"status":"verified"}`
- 無効なトークン、未完了購入、異なる商品、失効：HTTP 200 `{"status":"rejected"}`
- Google API接続失敗、サービスアカウント認証エラー、D1障害、返金情報の鮮度不足：HTTP 503 `{"status":"unavailable"}`

Google 401・403・429・5xxを**購入拒否と誤判定せず**通信不能として扱い、安全側に倒します。購入承認（acknowledge）は、検証成功後にアプリ側が従来どおり実施します。

## ローカル単体テスト

Node.js 20以降で実施（LenovoでNode.js 24を使用）：

```powershell
cd C:\CodexWorkspace\yomipalette-android\backend\play-verifier
npm run check
npm test
```

Google Play API・D1の挙動はモック化しており、鍵・Cloudflare課金・本物の購入は不要です。

## 本番用設定の準備（**まだデプロイしない**）

Cloudflare WorkersとD1の利用方針で進める場合、以下の設定を整える必要があります。

1. **Google Play Console** でDeveloper APIアクセスを有効にし、専用サービスアカウントにYomiPaletteの購入データを確認するための最小限の権限を付与します。サービスアカウントの秘密鍵をGitHubやAndroid APKに保存しないでください。
2. **Cloudflare D1** に `yomipalette-play-entitlements` を作成します。例：`npx wrangler d1 create yomipalette-play-entitlements`。
3. `wrangler.example.jsonc` をGit対象外の `wrangler.jsonc` にコピーし、T AND Iの `account_id`、実際のD1 `database_id`、Secrets Storeの `store_id` を設定します。D1テーブルはCloudflareコンソールから手動作成済みです。マイグレーション履歴を整合させる前に `wrangler d1 migrations apply --remote` を実行しないでください。
4. 会社アカウントのCloudflare Secrets Storeに `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`（scope: `workers`）を登録し、`secrets_store_secrets` の同名Bindingを設定します。Workerは `await env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON.get()` で取得し、以前の通常Secret文字列形式も互換維持します。**Worker未作成であり、`wrangler secret put` はWorkerを自動デプロイし得るため使用しません。JSON秘密鍵を会話・ログ・Gitに貼り付けないでください。**
5. Pub/Subからの**RTDN**（特に返金・取消）をOIDCで認証してWorkerに届ける仕組み、Cloudflare側の**Rate Limiting**、**Play Integrity／トークン再利用防止**、監視・アラートを別途実装・検証してください。
6. Cronをローカルで模擬し、D1の初回同期を成功させてから購入APIをテストしてください。初回同期前、Cron失敗から12時間超、または29日超の同期断絶時は、HTTP 503にして権利を付与しません。
7. インフラと認証が整ったあと、実際のPlayライセンステスターで購入・復元・返金取消を確認します。**それまではWorkersのデプロイもアプリの本番AAB作成も行わない**でください。

本番WorkerのHTTPS URLが決まった後にのみ、既存のビルドスクリプトに次のオプションを渡せます。

```powershell
.\scripts\build-play.ps1 -PurchaseVerifierUrl https://your-verified-domain.example/verify
```

これは説明用の例であり、未設定のURLをそのまま使ってはいけません。

## RTDNの認証済み受信（ローカル実装済み・未接続）

- `POST /rtdn` は **Google Pub/Subの認証付きPush専用**です。JSON本文だけでは認証できません。
- Googleの署名付きOIDC JWTについて、公開鍵によるRS256署名、`iss`、`aud`、`email`、`email_verified`、有効期限を検証します。
- Pub/Subのサブスクリプション名も照合します。不正な認証は401、処理障害は503、正常処理は204です。
- 全額返金は購入トークンのSHA-256ハッシュをD1に記録します。取消・一部返金はGoogle Play APIで最新の状態を確認します。
- 重複通知はD1のUPSERTで冪等処理します。**RTDN受信では`sync_state`の定期同期時刻を更新しません。**
- 単なる購入通知やテスト通知では広告解除権を直接付与しません。権利付与は既存`POST /verify`で再検証します。

### 本番接続前の設定（現時点では未実施）

1. Google Cloudプロジェクト`tts-text-mp3`でPub/Sub APIを有効にし、RTDN専用のトピックを作成します。トピックへのPublisher権限はGoogle公式指定の`google-play-developer-notifications@system.gserviceaccount.com`だけに付与します。
2. Pub/Sub **Push認証専用サービスアカウント**を新規作成します（既存の購入検証用サービスアカウントとは分離）。秘密鍵作成は不要です。Google Pub/SubサービスエージェントにこのアカウントのToken Creator権限が必要です。
3. Workerデプロイ・厳格な不正利用対策・URL確定の後、Pub/Subに認証付きPushサブスクリプションを作り、`POST https://<worker-host>/rtdn`を通知先にします。
4. Workerの`vars`（秘密情報ではない設定）に次の3項目を登録します。`RTDN_OIDC_AUDIENCE`はPub/Sub PushのOIDC Audienceと**完全一致**させます。下記は値の例であり、未確定のままデプロイしないでください。

```jsonc
"vars": {
  "RTDN_OIDC_AUDIENCE": "https://<worker-host>/rtdn",
  "RTDN_PUSH_SERVICE_ACCOUNT_EMAIL": "<push-auth-service-account>@tts-text-mp3.iam.gserviceaccount.com",
  "RTDN_PUBSUB_SUBSCRIPTION": "projects/tts-text-mp3/subscriptions/<subscription-id>"
}
```

5. Google Play Console「収益化のセットアップ」でRTDNを有効にし、トピックIDを設定します。YomiPaletteでは **定期購入と1回限りの商品のすべての通知** を選びます。テスト通知後、受信・認証・D1更新を確認します。
6. Pub/Subの再試行・Dead Letter Topic・監視を追加してください。署名付きJWTの公開鍵取得失敗／Google API障害／D1障害では503で再送を要求します。
7. 公開`/verify`のレート制限、購入トークンの第三者再利用防止、オフライン権利設計は未完了です。**Workerの本番公開は引き続き禁止**します。

参考: https://developer.android.com/google/play/billing/getting-ready 、
https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions

## 特に重要な未完了事項

- **RTDN未接続**：現状は6時間周期のVoided Purchases APIによるポーリングだけです。返金後すぐに失効しない時間帯があります。GoogleはRTDNとVoided Purchases APIの併用を推奨しています。
- **購入トークン再利用への耐性**：今のFlutterアプリにはユーザーアカウント・Play Integrity証明の連携がありません。有効な購入トークンが第三者に漏れた場合、別端末で再利用され得ます。本番前に認証・不正利用リスクを検討してください。
- **API濫用防止**：HTTPS endpointはAndroidの公開クライアントから到達可能なため、Cloudflare WAFによるIP・リクエストレート制限やPlay Integrity検証を整える必要があります。Cloudflare Accessの対話型ログインを強制するとアプリから使用できません。
- **オフライン権利**：アプリは署名付きオフライン権利キャッシュ未実装です。起動後の購入確認にはネットワーク接続が必要です。
- **プライバシー/データセーフティ**：購入トークンをGoogleと検証バックエンドが取り扱うため、正式公開前にプライバシーポリシー・Play Consoleの申告を見直す必要があります。
- **本物のAPI疎通未検証**：Google Play Consoleのサービスアカウント権限、Cloudflare D1、Secrets Storeの設定は完了しましたが、Workerは未作成・未デプロイで、Google Play API実通信は未実施です。テストはすべてモックです。

## 参照

- Google Play ProductPurchaseV2: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2
- Voided Purchases API: https://developers.google.com/android-publisher/voided-purchases
- RTDN: https://developer.android.com/google/play/billing/rtdn-reference
- GoogleサービスアカウントOAuth: https://developers.google.com/identity/protocols/oauth2/service-account
- Cloudflare Workers & D1: https://developers.cloudflare.com/d1/get-started/
