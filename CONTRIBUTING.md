# Contributing

Moonlit Beacon is a shipping Godot 4.7 game and a worked example of
[godot-iap](https://github.com/hyodotdev/openiap/tree/main/libraries/godot-iap)
plus [IAPKit](https://kit.openiap.dev) on Android and iOS.

## Setup

1. Install [Godot 4.7.1 Standard](https://godotengine.org/download).
2. Install Node.js 20+ and `pnpm`.
3. Clone this repository and run `pnpm install` from the repo root.
4. Open `apps/game/project.godot` in Godot.

```bash
pnpm game          # run the game
pnpm game:editor   # open the Godot editor
pnpm verify        # same checks CI runs
```

Store signing keys, IAPKit secrets, and App Store Connect keys stay on the
machine. Copy `.env.example` to `.env` and fill only what you need. Never
commit `.env`, `.godot/`, `*.jks`, `*.p8`, or `iapkit.cfg`.

Fork pull requests build the debug APK only. GitHub withholds secrets from
forks, so the store AAB step (it needs `IAPKIT_API_KEY`) and its checks are
skipped there — that skip is expected, not a failure.

## Rules that CI enforces

- Lesson numbers are written **Lesson 1**, **Lesson 2**. Do not use the
  standalone word `phase` in `apps/`, `notes/`, or `README.md`.
- File names stay `chapter-01`, `chapter-02`.
- `.godot/` is never committed. It can hold Android keystore passwords.
- `export_presets.cfg` is committed; `export_credentials.cfg` is not.
- Course clips in `apps/docs/static/video/` are silent and under 1 MB.
- Keep `com.crossplatformkorea.moonlitbeacon` as the Android/iOS application
  id. Changing it would publish a different store app.

## godot-iap

The plugin is vendored from the official `godot-iap-3.5.1` zip with a small
project patch documented in `vendor/godot-iap/README.md`.
`pnpm test:godot-iap-vendor` checks that the patch reverses to the official
bytes.

Do not copy Ninja Adventure's Godot demo scenes or scripts into `res://`.
Copy only the art files you actually use, and record them in
`apps/docs/docs/assets/manifest.md`.
