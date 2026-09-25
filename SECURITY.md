# Security Policy

## Supported Versions

Only the latest store release is supported with security updates.

| Version | Supported |
| ------- | --------- |
| Latest App Store / Play release | Yes |
| Older releases | No |

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability. Use the
repository's private channel: **Security tab → Report a vulnerability**.
Only the maintainer can see the report.

Include in the report:

- What is affected (game build, docs site, workflow, dependency)
- Steps to reproduce, or the file and line if it is visible in source
- What you think the impact is

You will get an acknowledgment, and a fix or a mitigation plan, as soon as
the report is triaged. Please do not disclose the details publicly until a
fix is released.

## What Is Out of Scope Here

- The Android signing keystore, the App Store Connect API key, and the
  IAPKit admin key live outside this repository (local Keychain / CI
  secrets). A report that only shows their *names* in `.env.example` or in
  prose is not a leak — check that a real value is committed before
  reporting.
- Third-party assets under `apps/game/assets/third_party/` are redistributed
  under their own licenses (see the credits document). License questions
  about those files are not security issues.
