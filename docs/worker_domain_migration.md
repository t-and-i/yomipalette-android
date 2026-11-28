# Worker domain migration

Migrated on November 29, 2026. The active Cloudflare zone is `t-and-i.date` in
the existing T AND I account. Custom domains were attached to the existing
Workers, preserving their code, secrets, D1 bindings, rate limits and signing
keys.

| Environment | Canonical base URL | Worker |
| --- | --- | --- |
| Production | `https://yp-verify.t-and-i.date` | `yomipalette-play-verifier` |
| Staging | `https://yp-verify-stg.t-and-i.date` | `yomipalette-play-verifier-staging` |

The `/verify`, `/trial`, `/review` and `/rtdn` paths keep their existing meaning
on each Worker. Available features depend on the code already deployed to that
Worker. Staging hosts review and trial testing.

Google Pub/Sub delivery endpoints were updated in project `tts-text-mp3`.

| Subscription | Push endpoint |
| --- | --- |
| `yomipalette-rtdn-production-push` | `https://yp-verify.t-and-i.date/rtdn` |
| `yomipalette-rtdn-staging-push` | `https://yp-verify-stg.t-and-i.date/rtdn` |

Push authentication remains enabled using
`yomipalette-rtdn-push@tts-text-mp3.iam.gserviceaccount.com`. The existing explicit
OIDC audience identifiers remain `https://yp-verify.tiaozheng.dpdns.org/rtdn`
and `https://yp-verify-stg.tiaozheng.dpdns.org/rtdn`, respectively. These match
the Workers' existing `RTDN_OIDC_AUDIENCE` values and are checked as token
identifiers. The HTTP delivery endpoints use the new domain.

The old custom domains remain attached as compatibility aliases for installed
build-20 clients and the ongoing test records. Local Wrangler configurations
list both domains so a later deployment retains that compatibility. Retiring
the aliases is a follow-up after old clients and their tests have migrated.

Build new clients with the following public endpoint settings.

```text
YOMIPALETTE_BILLING_VERIFY_URL=https://yp-verify.t-and-i.date/verify
YOMIPALETTE_TRIAL_VERIFY_URL=https://yp-verify-stg.t-and-i.date/trial
YOMIPALETTE_REVIEW_ACCESS_URL=https://yp-verify-stg.t-and-i.date/review
```

The existing purchase public key and staging trial/review public key continue
to apply. Historical artifact manifests and test evidence retain the endpoint
used when those artifacts were created.

The new domains were checked with TLS verification enabled. Domain attachment
used Cloudflare's [Custom Domains API](https://developers.cloudflare.com/api/resources/workers/subresources/domains/methods/update/).
Live staging checks registered a synthetic installation on the old domain,
refreshed its credential on the new domain, and verified the new grant signature
and 72-hour scope. Both new `/rtdn` endpoints rejected unauthenticated requests.
The synthetic registration was revoked afterward. Full authenticated RTDN
delivery verification remains with the next notification test.
