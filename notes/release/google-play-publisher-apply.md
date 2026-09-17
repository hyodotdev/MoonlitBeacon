# Google Play Publisher API apply procedure

This procedure applies the verified package in `builds/release/google-play-upload`
to Google Play's `internal` track. The default is a local check that uses no
network at all.

```bash
node scripts/apply-play-release.mjs --check
```

The check reconfirms AAB signing and runtime bounds, every payload hash
recorded in the manifest, the current repo input hash, 5-language listings,
phone/7-inch/10-inch image job counts, public privacy/support URLs, the
account-owner declaration, and the service-account file. The service-account
JSON must be a regular file outside the repo with mode `0600`, and only the
path is passed as `GOOGLE_APPLICATION_CREDENTIALS`. JSON and access tokens
are not put in output or child-process arguments.

Remote apply uses only the manifest-only token printed when the check result
is `ready`.

```bash
node scripts/apply-play-release.mjs \
  --apply \
  --confirm-remote-apply '<token printed by --check>'
```

Apply order:

1. Create a new edit
2. After AAB resumable upload, reconfirm the official response `versionCode`
   and lowercase-hex `sha256` exactly against the manifest AAB hash
3. Update 5-language listings
4. Delete per-language existing icon, feature graphic, phone, 7-inch, and
   10-inch images, then upload images whose manifest hashes match, in order
5. Set a `completed` release and 5-language release notes on the `internal`
   track
6. Validate the edit
7. Commit with `ERROR_IF_IN_REVIEW`

`ERROR_IF_IN_REVIEW` does not cancel an in-review change; it stops with an
error. Failure before commit discards the created edit, and a retry must
start from a new `--check`.

## Sync of the 7 non-consumable products managed by the Publisher API

Product apply is a second safety boundary, separate from the app-edit commit.
The app token and product token printed by `--check` must both be explicit on
the same command.

```bash
node scripts/apply-play-release.mjs \
  --apply \
  --include-products \
  --confirm-remote-apply '<app token>' \
  --confirm-products '<product token>'
```

`--check` performs OAuth, price conversion, product lookup, and mutation
**0 times** even when the product option is selected. The two tokens are bound
to the verified release manifest, the exact 7 non-consumable product IDs this
tool owns, 5-language copy, and the owner price policy below. The 3 continue
coins are managed in IAPKit and Play Console, so they are not mixed into this
batch mutation; they are verified with a separate remote-state check and
on-device purchase e2e.

| Product | `convertRegionPrices` pre-tax baseline | Baseline-region check |
| --- | ---: | --- |
| `supporter` | KRW 3,300 | KR final KRW 3,300, API tax KRW 0 |
| `hero_dancer` | USD 4.99 | US final USD 4.99 |
| `hero_keeper` | USD 9.99 | US final USD 9.99 |
| `hero_knight` | USD 14.99 | US final USD 14.99 |
| `hero_eclipse` | USD 19.99 | US final USD 19.99 |
| `hero_sage` | USD 24.99 | US final USD 24.99 |
| `lantern_colors` | KRW 1,100 | KR final KRW 1,100, API tax KRW 0 |

Product-inclusive apply first finishes lookups, price conversion, and
verification in steps 1–3 below. If this stage fails, it does not create an
app edit. Verification results are frozen as an immutable in-memory snapshot.
Then, **before** creating the app edit, it fsyncs an owner-only (`0600`)
schema v2 `COMMITTING` intent receipt bound to the manifest digest, AAB
SHA-256, and product-policy digest, including the parent directory. When an
edit ID is obtained, it is written to the intent first. Only after the app
commit response is verified and atomically promoted to
`COMMITTED / COMMIT_RESPONSE` with products `PENDING` do mutations 4–6 run.
The default path is `builds/release/google-play-apply-receipt.json`.

1. Paginate every One-Time Product. Existing sale SKUs may only be the locked
   7 IDs; missing SKUs are creation targets. Legacy `hero_bundle` must exist
   in a non-sale `INACTIVE` or `INACTIVE_PUBLISHED` state. Any other product,
   unexpected purchase option, CN, or wrong KR/US baseline hard-fails before
   the app edit. Legacy must have the same full resource snapshot before and
   after sync.
2. Convert the 7 baselines with official `monetization.convertRegionPrices`
   for that day. Every response must share the same `regionsVersion` and
   supported-region set. KRW products reconfirm the Korean consumer target
   final price and API-computed tax 0; USD products reconfirm the US target
   price exactly.
3. Use every currently supported region in the response except CN. Make every
   region `AVAILABLE`. Omit `newRegionsConfig` for the 5 new heroes. If
   existing `supporter` and `lantern_colors` have `AVAILABLE` or already
   converted `NO_LONGER_AVAILABLE` settings, preserve the USD/EUR prices
   read in preflight and send `NO_LONGER_AVAILABLE`. Do not attach the
   setting newly to products that never had it.
4. One `batchUpdate` upserts the 7 products with `allowMissing=true`,
   `updateMask=listings,purchaseOptions`. Each product has only 5-language
   listings, one deterministic `buy` option, `legacyCompatible=true`, and
   `multiQuantityEnabled=false`.
5. Do not repeat the same transition on options already ACTIVE in the
   `batchUpdate` response. If any DRAFT/INACTIVE targets remain, one
   `purchaseOptions.batchUpdateStates` activates only those `buy` options.
   A new creation includes all 7 here.
6. `batchGet` plus a full paginated list verify all 7 regions, that day's
   prices, 5 languages, and ACTIVE, and compare that legacy `hero_bundle`
   remains non-sale with the full resource unchanged.

A normal migration target like the current hero products that exist in only
the US region is allowed only when the existing `buy` structure and US
baseline are exact. `newRegionsConfig` present only on existing `supporter`
and `lantern_colors` is allowed as a conversion to `NO_LONGER_AVAILABLE`
without changing existing USD/EUR. After sync those two products must have
this state and price exactly, and the 5 new heroes must have no setting.
`hero_bundle` preserves the full resource including existing
`newRegionsConfig` and is not included in any update/activate request.

If a product-mutation call or response verification fails, report the remote
result as uncertain. The receipt stays `PENDING` and a normal `--apply` rerun
is blocked. If the process exits just before or after commit, or receipt
promotion is not confirmed, a `COMMITTING` intent remains. Running
product-only resume as below confirms the receipt is bound to the current
manifest, AAB, and product policy, then revalidates that the official track
release list has the same `internal` release name and `versionCode` in a
committed safe lifecycle. Only a `COMMITTING` intent whose exact release is
confirmed is promoted to `COMMITTED / TRACK_RELEASE` with products `PENDING`.
Then it reruns from a new price conversion and product preflight and does not
touch the app edit or AAB. The receipt becomes `APPLIED` only after final
readback and legacy preservation pass. If there is no exact release or the
lifecycle is outside the allow-list, stop with 0 product mutations and keep
the intent.

Existing schema v1 `PENDING/APPLIED` receipts can still be verified and
resumed. A new normal `--apply --include-products` does not try to apply a
duplicate version while any valid receipt remains. If a new package is
prepared, always use tokens printed by a new `--check`, and store the previous
intent separately after confirming remote state.

```bash
node scripts/apply-play-release.mjs \
  --resume-products \
  --confirm-remote-apply '<app token>' \
  --confirm-products '<product token>'
```

If the app was applied first and there is no receipt at all, do not bypass
with `--resume-products` or `--apply --include-products` for the same
versionCode. The adoption mode below first finishes that day's price
conversion and a read-only preflight of the existing 8 products in the same
run, then revalidates that `internal` has exactly one release with the exact
release name, versionCode, allowed lifecycle, and a single active artifact.
It stops if any existing receipt is present; after verification it atomically
create-if-absent a schema v2 `COMMITTED/PENDING` receipt with `TRACK_RELEASE`
proof and `editId: null`. Only after that receipt has durable readback does
it reuse the existing 7-product batch update, activate, and final readback.

```bash
node scripts/apply-play-release.mjs \
  --adopt-committed-release \
  --confirm-remote-apply '<app token>' \
  --confirm-products '<product token>'
```

This project's Korean seller payment profile currently returns Korean
transaction tax as Google's computed `0` from `convertRegionPrices`. So KRW
baselines use the consumer target finals KRW 3,300 and KRW 1,100 as-is, and
tax 0 is also verified explicitly. Deploy code does not guess and change the
payment profile's tax rate or tax liability. If account settings change and
API tax changes, preflight must hard-fail again.

If the commit response itself is cut off, do not invent a receipt. Follow the
output `app commit success=uncertain, versionCode=...` and check Play Console
first.

## production promotion

A **separate safety boundary** that moves a versionCode already committed on
`internal` to the public `production` track. It does not touch AAB, listings,
images, or products at all. So apply's `track` stays exactly `internal`, and
promotion does not change that setting.

```bash
node scripts/apply-play-release.mjs \
  --promote-production \
  --confirm-promotion '<promotion token printed by --check>'
```

The promotion token carries a different prefix (`google-play-promotion:`) and
target track from `--confirm-remote-apply` / `--confirm-products`. So an apply
token cannot be reused for promotion, and a promotion token cannot be reused
for apply. `--promote-production` rejects other confirm tokens or
`--include-products` used together.

Order:

1. Re-query exactly one committed release on `internal`. Release name and
   versionCode must match, lifecycle must be on the allow-list, and there
   must be one active artifact. Otherwise stop before creating an edit.
2. Query `production` and refuse a duplicate promotion if the same
   versionCode is already there.
3. Record an owner-only (`0600`) `COMMITTING` intent receipt bound to the
   manifest digest, versionCode, and source/target tracks. Default path is
   `builds/release/google-play-promotion-receipt.json`.
4. Create a new edit and write the edit ID to the intent first.
5. Set only that versionCode on the `production` track with the same release
   name, release notes, and `completed` state, then reconfirm the response.
6. Validate the edit and commit with `ERROR_IF_IN_REVIEW`. When the commit
   response is confirmed, promote the receipt to `COMMITTED / COMMIT_RESPONSE`.
7. GET the `production` track again and change the receipt to
   `APPLIED / TRACK_RELEASE` only after the exact release is confirmed.

If a receipt already exists, do not start a new promotion in any state. If
the commit response is cut off, print `promotion commit success=uncertain`
and leave the intent `COMMITTING`. Then check the real state in Play Console
first.

:::danger Pass IAP purchase e2e before promotion
Promotion verifies **release identity only**. It does not confirm that the 7
non-consumables managed by the Publisher API and the 3 consumable coins
managed by IAPKit/Play Console are actually ACTIVE, or that purchases
actually work. Promoting to production before products are ready shows users
a broken shop.

Promote only after `--check`'s product section and `internal`-track on-device
purchase e2e both pass. The procedure is in
[`ship-release`](../../.claude/skills/ship-release/SKILL.md).

This precondition is not enforced in code because this document already has
the normal procedure of storing the apply receipt separately after remote
confirmation. Blocking on local-file presence would wrongly stop that flow.
:::

Official contracts:

- [Get started with the Google Play Developer API](https://developers.google.com/android-publisher/getting_started)
- [Create an edit](https://developers.google.com/android-publisher/api-ref/rest/v3/edits/insert)
- [Upload an AAB](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles/upload)
- [File upload methods](https://developers.google.com/android-publisher/upload)
- [Update a track](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks/update)
- [List track releases](https://developers.google.com/android-publisher/api-ref/rest/v3/applications.tracks.releases/list)
- [Edit commit and in-review change protection](https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit)
- [One-Time Products contract](https://developers.google.com/android-publisher/api-ref/rest/v3/monetization.onetimeproducts)
- [Region price conversion](https://developers.google.com/android-publisher/api-ref/rest/v3/monetization/convertRegionPrices)
- [List One-Time Products](https://developers.google.com/android-publisher/api-ref/rest/v3/monetization.onetimeproducts/list)
- [Batch-get One-Time Products](https://developers.google.com/android-publisher/api-ref/rest/v3/monetization.onetimeproducts/batchGet)
- [Batch-change Purchase Option states](https://developers.google.com/android-publisher/api-ref/rest/v3/monetization.onetimeproducts.purchaseOptions/batchUpdateStates)
- [Service-account OAuth 2.0](https://developers.google.com/identity/protocols/oauth2/service-account)
