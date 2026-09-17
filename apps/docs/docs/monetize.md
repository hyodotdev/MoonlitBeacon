---
title: Monetization — what you can sell, and what you must not
---

# Monetization — what you can sell, and what you must not

The game got fun, so we talk about money. This document is not **how to
wire IAP**. It is **how to decide what to sell**. Code is in the last two
sections. The six sections before that are the part that actually matters.

## 1. Say this first — the scope changes

This repository's shipping plan was **direct APK distribution + itch.io**.
But:

> **itch.io cannot do in-app purchases.**

IAP is only possible through Google Play Billing or App Store StoreKit.
So putting this document into practice means a **full Google Play
release**, and that brings a privacy policy, review, store listing, and
business information with it.

**"Add IAP" is not a piece of code. It is starting a business.**
If you do not make that decision first, everything else is wasted work.

The direct-distribution APK and the itch.io build still ship without
payments. Store-build shop code is implemented, but live sales stay off
until each platform's product listing and review are done.

## 2. In an endless roguelike, only three things can be sold

Moonlit Beacon's product **is the curve itself**: every run starts at 0
and grows until the screen explodes about 30 minutes later. Let money
skip that curve and **the moment you sell it, you break the game.**

What remains is three things.

| What you can sell | What it is | Why it does not break the game |
| --- | --- | --- |
| **Content** | new characters, new modes | you are not skipping the curve — **you give one more curve** |
| **Identity** | ladder emblem, lantern color | no effect on power |
| **Goodwill** | support | paid by people who already had fun |

**You cannot sell strength.** Sell it and the ladder becomes a wallet ladder.

## 3. Archero's wall — this is the real reason

"Do not sell permanent growth" is common advice, and treating it as
morals is wrong. It is a business call.

Archero's revenue peaked and went flat. Two causes stacked.

1. Roguelike balance meant **new heroes could not be made strong.** Make
   them strong and the game breaks.
2. Yet a new hero **had to be grown from the start.** Nobody leaves a
   grown hero to grow another from 0.

Those two together made **"new character"** — the best product — unsalable.

:::danger We almost built this wall ourselves
Moonlit Beacon has a Moonlit Vault — permanent growth that buys boons
with shards. That is Archero's wall.

**We got out because boons are account-wide, not per character.**
Buy a new character and the boons you already raised still attach. You
do not grow from 0 again.

If we had built "grow each character separately," we could not sell
characters.
**When you add permanent growth, keep only this: attach it to the
account, not the character.**
:::

## 4. Do not lean on dark patterns for repeat purchases

"A game without repeat purchases dies" is true. For a solo developer
there are two paths, and one is a trap.

**Repeat consumable sales** tied to energy, gacha, and urgency timers
need live ops. Weekly events, monthly new gacha, balance patches. Solo,
three months is the limit, and **the moment you stop, revenue drops to
zero.** What you are left with is a "heavy pay-to-play" rating.

**A content ship cadence** (characters · modes) can be one every six
months. Revenue falls while you are not making anything, but **the rating
does not.** Ship the next one and it recovers.

So continue coins stay a limited convenience you buy in the shop after
seeing quantity and price. No countdown checkout at the moment you fall,
no energy wait, no randomized rewards. The long-term product center is
still permanent heroes and cosmetics.

## 5. Three dark patterns we do not use

| Pattern | Why people use it | Why we do not |
| --- | --- | --- |
| **Dual currency** (won → gems → goods) | hides the real price. "30 gems" is not instantly how much | leftover change is **not a side effect. It is the design.** Those 100 gems call the next purchase. Refunds get fuzzy and become disputes |
| **5-second revive timer** | blocks thought. 5 seconds is short to decide and long enough to react | a purchase that makes you think "why did I press that" **comes back as refunds and 1-star reviews.** With a ladder, a rushed revive also pollutes other people's records |
| **Fake limited** ("today only" every day) | time pressure | it is a lie and **two days is enough to catch it.** Once caught, every line in that game is suspect |

We do this instead.

- **Show the store's local price directly.** The button shows the actual
  currency and tax-inclusive price the store returned. The app does not
  hard-code dollars or won.
- **Do not push a purchase at the moment you fall.** Continue coins are
  bought ahead in the shop, and whether to use one is the player's choice.
- **No fake discounts.** A console list price is the same whenever you
  buy. **A price that does not move is itself trust** — buying now is
  not a loss.

## 6. Duties that appear when you add payments in Korea

### Randomized items — the surest defense is not being in scope

The Game Industry Promotion Act amended on 22 March 2024 requires a
game-business operator to display the kinds and supply probabilities of
randomized items **on the game, the website, and every advertisement.**
Failing a corrective order is imprisonment or a fine.

The further amendment in force on 1 August 2025 went further.

- Not displaying probabilities, or displaying them falsely and causing
  damage, means **up to 3× damages**
- **The game company must prove it was not at fault** (burden of proof
  reversed)

**So we do not put in gacha.** Then this whole clause is irrelevant.
The surest legal defense a solo developer can take is **not being in
scope.**

:::caution "Randomized" is not only paid gacha
It includes upgrade and synthesis types too. Add a device like "you
upgrade a relic with shards and it can fail at random," and the moment
paid currency is involved a display duty can appear.
:::

### Age rating

Google Play is a self-rating operator, so you get a rating through an
**IARC questionnaire.** A solo developer does not have to apply to the
Game Rating and Administration Committee directly.

You still **have to answer the questionnaire honestly.** Presence of IAP,
randomized items, and user-to-user interaction all go into the ruling.

**A name the user typed appearing on the ladder can be treated as
user-generated content.** Then report and block tools can be required —
design that together when you turn on a global ladder.

### E-commerce law

- **Seller information display**: trade name, representative, business
  registration number, mail-order business report number, contact,
  address. Show it in the game (Settings or the bottom of the shop) or
  on a website.
- **Withdrawal of offer**: 7 days in principle. Digital content is
  limited once use starts, but **you cannot block it before use, and that
  limit must be disclosed before purchase.** If you did not disclose, you
  cannot refuse withdrawal even after use.
- Google Play's 48-hour auto-refund is **platform policy, not fulfillment
  of a legal duty.** Keep a separate refund contact (email is enough) and
  a policy notice.

## 7. Wiring it with `godot-iap`

Godot has no official IAP support. This course uses **[godot-iap][iap]** —
a cross-platform plugin that follows the OpenIAP spec and covers iOS
StoreKit 2 and Android Play Billing with one API. MIT.

[iap]: https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.5.1

| | |
| --- | --- |
| Requires | Godot 4.3+ · iOS 17+ · Android API 24+ |
| Version | godot-iap 3.5.1 |
| Repo | `libraries/godot-iap` in `hyodotdev/openiap` |
| Docs | `openiap.dev` — `llms-full.txt` can fetch the whole API at once |

Moonlit Beacon is Godot 4.7.1, so it meets the requirement.

### Install

Download `godot-iap-{version}.zip` from the release, unzip into
`addons/godot-iap/`, and turn it on in **Project Settings → Plugins**.

:::caution The rule about not putting original assets in `res://`
This repo keeps original assets outside `res://` and copies only used
files. **Plugins are the exception** — Godot requires a fixed `addons/`
path. Record version and license in
[Third-party licenses](./assets/third-party.md) instead.
:::

### Flow

```gdscript
# Connect signals first. Miss the first response if you connect after init.
GodotIapPlugin.purchase_updated.connect(_on_purchase)
GodotIapPlugin.products_fetched.connect(_on_products)
GodotIapPlugin.init_connection()

# Product list
await GodotIapPlugin.fetch_products(request)

# Purchase
GodotIapPlugin.request_purchase(props)

# Always finish after the grant
await GodotIapPlugin.finish_transaction(purchase, is_consumable)
```

:::danger Do not skip `finish_transaction()`
An unfinished transaction is reported by the store as **incomplete and
re-notified forever.**
Android auto-refunds after three days, and then the user has the item
and the money back.

**Grant first, save, then finish.** Reverse the order and a crash between
finish and save loses the item.
:::

### Receipt verification

Do not grant from the Dictionary the store returned alone. The Moonlit
Store sends Apple's signed StoreKit JWS or Google Play's purchase token
to [IAPKit](https://kit.openiap.dev/docs/api) and takes Apple and Google
servers' judgment.

Verification runs in this order.

1. Cross-check IAPKit's `store`, `productId`, `isValid`, and `state`.
2. Save the local ledger and benefit only when Apple non-consumables are
   `ENTITLED`, and Google non-consumables are `ENTITLED` or
   `PENDING_ACKNOWLEDGMENT`.
3. Finish/acknowledge the store transaction only after save and
   idempotent grant are done.

After finish, keep a minimal purchase original (JWS or purchase token)
in the `user://` app-sandbox ledger so refund state can be checked again.
Android's current-purchase list does not return refunded one-time
products at all. On app resume, relaunch, and restore, re-verify even
completed transactions missing from the list against the stored original
via IAPKit, and revoke only transactions the server confirms as
`CANCELED`. Do not print originals or the publishable key in logs or on
screen.

Network errors, rate limits, 5xx, and success responses with the wrong
shape are distinct from an invalid purchase.
Then we neither grant a benefit nor complete the transaction, and we
re-verify the same transaction on app resume, restore, and reconnect.
Deterministic 4xx that mean a bad key or request are not described as a
temporary outage; they end as a verification failure that needs support.
In every case we do not finish before verification, and we do not revoke
a permanent entitlement already verified and saved just because of a
temporary server outage.

The app is injected at export time with only the purchase-verification
publishable key (`openiap-kit_pk_…`).
The secret key used for catalog writes and admin (`openiap-kit_sk_…`)
never goes in the app, the repo, or logs. A publishable key can be
extracted from the app by name, so verification requests limit new-sale
product IDs to 10 SKUs — 7 non-consumable and 3 consumable — plus
`hero_bundle` on a separate legacy allow-list for restoring past
purchases. Product IDs the server returns are compared exactly again.

IAPKit confirms **that a store transaction is genuine.** It does not
turn the `user://` save file itself into an online account ledger, so
tamper-proof cross-device entitlements still need login and a separate
server entitlement ledger.

## 8. So what does this game sell?

The 10 sale items are **7 permanent non-consumables** and **3 consumable
continue-coin SKUs** you can buy again after use. The game does not
hard-code prices as strings. It shows the local-currency price Android
and iPad stores return. The won and dollar figures below are list prices
to set in the consoles; the actual charge can differ by store, country,
and tax.

| Product | SKU | List price | What it gives | Is a non-buyer at a loss? |
| --- | --- | --- | --- | --- |
| Moonlit Supporter | `com.crossplatformkorea.moonlitbeacon.supporter` | ₩3,300 | ladder name and a supporter mark in credits | no |
| Shadow Dancer | `com.crossplatformkorea.moonlitbeacon.hero_dancer` | US $4.99 | violet twin-crescent and spiral moonlight style | no. balanced sidegrade |
| Beacon Keeper | `com.crossplatformkorea.moonlitbeacon.hero_keeper` | US $9.99 | jade lantern ripple and gold shock style | no. balanced sidegrade |
| Silver Moon Knight | `com.crossplatformkorea.moonlitbeacon.hero_knight` | US $14.99 | silver crescent fan and white star-shard style | no. balanced sidegrade |
| Eclipse Mage | `com.crossplatformkorea.moonlitbeacon.hero_eclipse` | US $19.99 | crimson eclipse ring and dark-red ember style | no. balanced sidegrade |
| Constellation Sage | `com.crossplatformkorea.moonlitbeacon.hero_sage` | US $24.99 | teal constellation chain and gold star-map style | no. balanced sidegrade |
| Lantern Colors | `com.crossplatformkorea.moonlitbeacon.lantern_colors` | ₩1,100 | ember, moonlight, violet, jade — 4 colors | no. detect range and combat power do not change |
| Continue Coin | `com.crossplatformkorea.moonlitbeacon.continue_coin` | US $0.49 | continue once from where you fell | optional convenience. you can start a new run without it |
| Continue Coins ×5 | `com.crossplatformkorea.moonlitbeacon.continue_coin_5` | US $1.99 | 5 continues | optional convenience. you can start a new run without it |
| Continue Coins ×10 | `com.crossplatformkorea.moonlitbeacon.continue_coin_10` | US $3.49 | 10 continues | optional convenience. you can start a new run without it |

Permanent products **do not touch a run's growth curve.** Moonlit Warden
is free and can play every terrain, guardian, and cycle on its own. Paid
heroes are balanced alternatives with different color, projectile shape,
motion, collision presentation, and feel. Price gaps are art and
presentation style, not combat-power ranks. Continue coins are a
separate convenience that resumes the current run once; without them
there is no limit on starting a new run.

`com.crossplatformkorea.moonlitbeacon.hero_bundle` is a legacy SKU
dropped from the new-sale list. Past buyers still restore Shadow Dancer
and Beacon Keeper. Origin of the two heroes earned with moon shards in
an earlier version is also preserved, and a refund revokes only that IAP
origin. New saves do not unlock paid heroes with moon shards.

Continues exist, but **there is no urgency-payment timer, energy, or
gacha.** Coins are bought ahead in the shop after checking quantity and
price, and unused coins stay.

## 9. Implementation status and pre-ship blockers

Shop UI, IAPKit server verification, permanent entitlement storage,
duplicate-transaction prevention, purchase restore, and hero-origin
preservation are implemented. Only transactions whose store, product,
and state all verify are granted, and the transaction is completed after
the entitlement is saved. Pending approval and verification-server
outages do not grant. When the store or IAPKit confirms cancel or
revoke, only that IAP origin is recovered. If a preserved legacy shard
origin remains on the same hero, the hero stays; if there is no other
origin, the selected hero is safely reverted to Moonlit Warden.
Verified non-consumable entitlements stay on the local ledger and
survive offline relaunch. Purchase restore after a clean reinstall needs
the store and IAPKit connected, but a network error or a temporarily
missing list does not revoke an already saved entitlement.
On a desktop run you launched yourself, and on the itch.io APK, the shop
not opening is expected.

The following, though, are **external blockers** code cannot stand in for.

1. The actual selling party must enter and get approved developer
   accounts, contracts, tax, and payout information in App Store Connect
   and Play Console.
2. Register an App Store In-App Purchase key and a Google Play service
   account on the IAPKit project, with the same app ID and least privilege
   only.
3. Register the SKUs above on each console with the same spelling, and
   mark the 7 permanent products as non-consumable/one-time and the 3
   continue-coin SKUs as consumable, exactly.
4. Confirm purchase and restore-after-reinstall in Play internal testing
   or TestFlight/App Store Sandbox, with a build distributed through that
   store and an allowed test account. `adb install` of a local APK cannot
   verify a Play product purchase.
5. Ship countries, real local prices, privacy policy, seller and refund
   contacts, and digital-content withdrawal notices must be decided and
   entered by the selling party. This repository does not put in
   arbitrary legal or seller information.
6. IAPKit can receive Apple ASN and Google RTDN but does not push events
   to the game client. The app re-verifies current purchases on launch
   and restore. If immediate cross-device revoke is a ship condition,
   run login and a separate server entitlement ledger first.

Follow `notes/release/iap-store-setup.md` in the repo for the actual
console input and test order.
Until this checklist is finished, keep direct-distribution APK and
itch.io copy at "no payments."
