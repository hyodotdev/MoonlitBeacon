# Store submission assets

These are the final assets actually uploaded to each store. The generation
source path is `builds/release/` (gitignored). This folder versions
**submission copies only**.

| Folder | Store | Contents |
| --- | --- | --- |
| `google-play/` | Google Play | 5 languages × (icon · feature graphic · phone/7-inch/10-inch screenshots, 6 each) |
| `app-store/` | App Store | 5 languages × (iPhone 6.5" · iPad 12.9" screenshots) + 9 IAP review images kept in the repo |

The default is to reuse already-uploaded submission assets. Recapture only
screens whose actual layout, art, visible copy, or composition has fully
changed, and add new IAP review images only for new products.
Fingerprint/provenance failure by itself is not a recapture reason. Only when
you truly must rebuild, follow [`ship-release`](../.claude/skills/ship-release/SKILL.md)
and the capture → generate → verify steps in `notes/release/`.

Current submission baseline: **1.0.2 (versionCode 11 / build 6)**

App Store Connect's submission target is 10 IAPs. The existing `continue_coin`
review image stayed as the remote asset, so it is not replaced with a newly
made local file. The only files newly uploaded and added to this folder in
this resubmission are `continue-coin-5.png` and `continue-coin-10.png`.
