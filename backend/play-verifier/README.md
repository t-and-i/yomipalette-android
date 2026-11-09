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

### Integrity対応アプリとの契約

```http
POST /verify
Content-Type: application/json

{
  "packageName": "com.tjsongwei.tts_text_mp3_mobile",
  "productId": "remove_ads",
  "purchaseToken": "<Google Play purchase token>",
  "requestId": "<32 lowercase hex characters>",
  "integrityToken": "<Play Integrity Standard token>"
}
```

- Google Playで購入済み・未失効：HTTP 200 `{"status":"verified"}`
- 無効なトークン、未完了購入、異なる商品、失効：HTTP 200 `{"status":"rejected"}`
- Google API接続失敗、サービスアカウント認証エラー、D1障害、返金情報の鮮度不足：HTTP 503 `{"status":"unavailable"}`

Google 401・403・429・5xxを**購入拒否と誤判定せず**通信不能として扱い、安全側に倒します。購入承認（acknowledge）は、検証成功後にアプリ側が従来どおり実施します。

### Play Integrity Standard API

購入と復元は同じ検証経路を通ります。アプリは試行ごとに新しいランダムな `requestId` を生成し、アプリID、商品ID、購入トークンのSHA-256、要求ID、検証操作の識別子を順序固定のJSON配列にしてSHA-256を計算します。Googleに渡す `requestHash` はこのダイジェストです。WorkerはGoogleが復号した値と照合し、判定時刻は過去2分以内・未来30秒以内を許容します。

`PLAY_RECOGNIZED`、`LICENSED`、`MEETS_DEVICE_INTEGRITY` を必須とします。Integrityの失敗・未評価はHTTP 503 `unavailable` で扱います。購入権限は引き続きGoogle Play Developer APIの購入状態とD1の失効情報で判断します。再試行では新しいIntegrityトークンを取得します。使い回されたIntegrityトークンの再利用防止はGoogleのStandard APIに依存します。

端末への紐付けや購入トークンの一回限りの消費は行いません。購入したGoogle Playアカウントから新しい端末で復元し、その環境でIntegrity要件を満たせば、同じ購入トークンを再検証できます。YomiPaletteには独自アカウントがないため、復号した判定から購入者本人やアカウントの同一性は確認できず、漏えいした購入トークンが別の正規環境から提示されるリスクは残ります。

運用前にPlay Consoleで対象アプリとGoogle Cloudプロジェクトをリンクし、そのプロジェクトでPlay Integrity APIを有効化します。Workerのサービスアカウントはリンクしたプロジェクトで復号できるものを使い、既存の購入照会権限も付与します。通常のPlayビルドには `scripts/build-play.ps1 -IntegrityProjectNumber` または `YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER` でリンク先のプロジェクト番号を渡します。Integrity未対応のアプリから新しいWorkerへの購入検証はHTTP 400になるため、アプリとWorkerのリリースは互換性を確認して計画してください。

仕様: [Standard API](https://developer.android.com/google/play/integrity/standard) · [判定フィールド](https://developer.android.com/google/play/integrity/verdicts) · [セットアップ](https://developer.android.com/google/play/integrity/setup)

## ステージング環境（2026-11-09 HTTPS公開・Cron配備済み）

本番向けの `wrangler.jsonc` と別に、LenovoのGit除外設定ファイル `wrangler.staging.jsonc` を用意しました。Cloudflareアカウントは `T AND I` です。

- Worker: `yomipalette-play-verifier-staging`。2026-11-09にCustom Domainを接続し、HTTPS疎通確認済み（Version: `1263914a-ed75-4f86-a5c3-3fc12a011056`）。
- 専用D1: `yomipalette-play-entitlements-staging`（ID: `bb5bfaab-3401-445d-ab8c-127f4ca7aec2`）。`revoked_purchase_tokens` と `sync_state` の空テーブルを作成済み。本番DBとは分離。
- ステージング固有のRate Limiting namespaceは `7923101` と `7923102`。本番設定のカウンタと共有しません。
- 既存のSecrets Storeの `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` Bindingを再利用します。**秘密鍵のコピーや値の表示は行いません**。この認証情報は実際のGoogle APIを呼び出せるため、アクセス公開前にレビューが必要です。
- `workers_dev: false` / `preview_urls: false` はCloudflare管理APIで無効を確認済み。Custom Domain `yp-verify-stg.tiaozheng.dpdns.org` は設定・DNS・HTTPS疎通確認済み。Pub/Sub OIDC認証付きPushもテスト通知で受信確認済み。
- Cron: `0 */6 * * *`（UTC、JSTでは毎日03:00・09:00・15:00・21:00）。ステージング専用D1に対して6時間ごとにGoogle Play Voided Purchases APIを照会します。Cron配備後、Cloudflare管理APIでも登録を確認済みです。
- D1初回同期は2026-11-08 23:18:30 JSTに成功。2026-11-09 09:00:05 JSTの自動同期更新も確認済み。返金トークン0件。引き続き `sync_state` とWorkerログを監視し、12時間以上同期状態が古くなると `/verify` が503を返す点に注意してください。
- 2026-11-09にステージングWorkerへ `RTDN_OIDC_AUDIENCE`、`RTDN_PUSH_SERVICE_ACCOUNT_EMAIL`、`RTDN_PUBSUB_SUBSCRIPTION` を設定・デプロイ済み（Version: `5160906d-264a-4bf6-b030-4fa9d4369672`）。Cloudflare管理APIで設定値を照合済み。`POST /rtdn` は未認証で401、Google Play Consoleのテスト通知では204を返しました。Google Cloud側の認証付きPushサブスクリプションも作成済みです。
- デプロイコマンドでは必ず `--config wrangler.staging.jsonc` を明示し、初期設定と差分を再確認してください。検証のみであれば以下です。

```powershell
cd C:\CodexWorkspace\yomipalette-android\backend\play-verifier
npx wrangler@4.157.0 deploy --dry-run --config wrangler.staging.jsonc
```

ステージングAPI: `https://yp-verify-stg.tiaozheng.dpdns.org/verify`。2026-11-09にTLSで疎通を確認し、`GET /verify` は405、無効なJSONの `POST /verify` は400を返しました。`POST /rtdn` はOIDC設定前に503、設定後の未認証アクセスに401、Google Play Console発の認証付きテスト通知に204を返しました。**正規のGoogle Play購入・Play Integrityトークンを使ったエンドツーエンド検証は未実施**です。正式にアプリから使用する前に、購入者トークンの悪用リスクと監視を確認してください。本番の`wrangler.jsonc`ではデプロイしないでください。

## ステージングRTDN Pushサブスクリプション（Google Cloud側作成・テスト受信済み）

Cloudflare Worker側は以下の設定でデプロイ済み。**下記の値は公開設定であり、秘密鍵ではありません**。

| 設定 | 値 |
| --- | --- |
| Google Cloudプロジェクト | `tts-text-mp3`（番号 `22173932202`） |
| 既存トピック | `projects/tts-text-mp3/topics/yomipalette-rtdn` |
| サブスクリプションID | `yomipalette-rtdn-staging-push` |
| プッシュエンドポイント | `https://yp-verify-stg.tiaozheng.dpdns.org/rtdn` |
| OIDC Audience | `https://yp-verify-stg.tiaozheng.dpdns.org/rtdn`（末尾スラッシュなし） |
| OIDCサービスアカウント | `yomipalette-rtdn-push@tts-text-mp3.iam.gserviceaccount.com` |
| Workerが照合するサブスクリプション | `projects/tts-text-mp3/subscriptions/yomipalette-rtdn-staging-push` |

再構築時の手順: Cloud Consoleの **Pub/Sub → サブスクリプション → 作成** で上記のトピックとIDを指定し、配送タイプ **Push** を選択。エンドポイントを入力し、**認証を有効にする** で上記サービスアカウント・Audienceを指定します。**ペイロードのラップ解除は無効**（Pub/Sub標準JSONエンベロープ必須）。再試行には指数バックオフを推奨します。

Pushサービスアカウントに対して、Pub/Subサービスエージェント `service-22173932202@gcp-sa-pubsub.iam.gserviceaccount.com` が `iam.serviceAccounts.getOpenIdToken` を使用できる必要があります。すでにサービスエージェント権限がある場合は追加不要です。足りない場合のみ、**対象Pushサービスアカウントに限定して**`roles/iam.serviceAccountOpenIdTokenCreator`など必要最小限の権限を付与してください。サブスクリプションを作成する主体にも、そのPushサービスアカウントに対する`iam.serviceAccounts.actAs`が必要です。

2026-11-09 23:37:43 JST、Google Play Consoleからテスト通知を送信し、Cloudflare Workers ObservabilityログでGoogle送信元の `POST /rtdn`、HTTP **204 No Content**、Worker outcome **ok**（約70ms）を確認しました。これにより、署名付きOIDC、Audience、送信元サービスアカウント、サブスクリプション照合とテスト通知処理の成功を確認済みです。なお、購入・返金などの実イベントは未検証であり、本番環境の設定は変更していません。

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
5. Pub/Subからの**RTDN**（特に返金・取消）をOIDCで認証してWorkerに届ける仕組み、Cloudflare側の**Rate Limiting**、**Play Integrity Standard API** の実環境での動作を検証し、監視・アラートを整備してください。
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
7. 公開`/verify`のレート制限はローカル実装済みですが、実環境での防御効果は未検証です。購入トークンの第三者再利用防止とオフライン権利設計は未完了です。**Workerの本番公開は引き続き禁止**します。

参考: https://developer.android.com/google/play/billing/getting-ready 、
https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions

## 購入検証APIのレート制限（ローカル実装済み、未デプロイ）

`POST /verify` は、Google Play APIへの無制限の外部アクセスを避けるため、Cloudflare Workers Rate Limiting APIを利用します。設定は `wrangler.example.jsonc` にあります。

| Binding | しきい値 | 判定キー |
|---|---|---|
| `VERIFY_IP_RATE_LIMIT` | 1分間30回 | Cloudflareの `CF-Connecting-IP` |
| `VERIFY_TOKEN_RATE_LIMIT` | 1分間6回 | 購入トークンの SHA-256 ハッシュ |

- IP制限を先に判定し、購入JSONの形式検査後にトークン制限を判定します。トークンはLimiterやログに平文で渡しません。`X-Forwarded-For` は信頼しません。
- 429レスポンスは `Retry-After: 60` を付け、購入トークンを返しません。
- Binding未設定、Limiterの異常、応答形式不正の場合は503 `unavailable` で安全側に倒します。
- `/rtdn` には購入検証用制限を適用しません。Pub/Sub OIDC署名とサブスクリプション名で認証・制限します。
- このRate Limiting APIは **Cloudflare拠点単位の近似制限**です。厳密な全世界共通制限ではありません。必要に応じてCloudflare WAFやDurable Objectsで防御を補完します。
- **購入トークンの所有権を証明するものではありません。** 盗まれた有効トークンの第三者使用対策には、Android側とバックエンドのPlay Integrity Standard API連携を引き続き実装する必要があります。リリース前は `requestHash` に購入要求のSHA-256ダイジェストをバインドし、サーバー側でGoogleが復号・検証した結果についてアプリ整合性・鮮度・リクエスト一致を判定する設計を検証してください。利用規約に適合するデバイス要件も検討します。

公式: https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/
https://developer.android.com/google/play/integrity/standard

## 特に重要な未完了事項

- **RTDN未接続**：現状は6時間周期のVoided Purchases APIによるポーリングだけです。返金後すぐに失効しない時間帯があります。GoogleはRTDNとVoided Purchases APIの併用を推奨しています。
- **購入トークン再利用への耐性**：ユーザーアカウントがないため、Play Integrityを通過しても、漏えいした購入トークンを提示した人が購入者本人かどうかは確認できません。
- **API濫用防止**：Rate Limiting APIのIP・トークン単位制限はローカル実装済みですが、Cloudflare本番運用での防御効果・ログ・アラートは未検証です。必要に応じWAFも併用します。Cloudflare Accessの対話型ログインを強制するとアプリから使用できません。
- **オフライン権利**：アプリは署名付きオフライン権利キャッシュ未実装です。起動後の購入確認にはネットワーク接続が必要です。
- **プライバシー/データセーフティ**：購入トークンをGoogleと検証バックエンドが取り扱うため、正式公開前にプライバシーポリシー・Play Consoleの申告を見直す必要があります。
- **本物のAPI疎通未検証**：Google Play Consoleのサービスアカウント権限、Cloudflare D1、Secrets Storeの設定は完了しましたが、Workerは未作成・未デプロイで、Google Play API実通信は未実施です。テストはすべてモックです。

## 参照

- Google Play ProductPurchaseV2: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2
- Voided Purchases API: https://developers.google.com/android-publisher/voided-purchases
- RTDN: https://developer.android.com/google/play/billing/rtdn-reference
- GoogleサービスアカウントOAuth: https://developers.google.com/identity/protocols/oauth2/service-account
- Cloudflare Workers & D1: https://developers.cloudflare.com/d1/get-started/
