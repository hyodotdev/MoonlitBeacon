# Brief 164: concise Google Play guest review instructions

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”
Supply accurate English reviewer entry instructions for the existing Play Console declaration.

## Where things stand
The director read the live Play Console Sign in details declaration: its 500-character other-information field still says Moonlit Beacon has no account sign-in. Version 4.0.0 now has guest, Google and Apple entry. Existing accepted App Store review notes in scripts/lib/app-store-release.mjs and notes/release/four-zero-review-entry.md describe the guest path, permanent player ID, New expedition and Resume the gate. Paid products remain optional. Google Play version 17 is on internal testing; production review and final native purchase verification are unfinished.

## Do
Write one plain-English text file, notes/release/google-play-review-entry.txt, at most 500 characters including whitespace. Describe title Tap to start, Continue as guest, automatic player ID/no developer credentials, New expedition or Resume the gate if a checkpoint exists, optional Google/Apple, and Store/Restore purchases. Do not imply that paid items are free or already verified. Compare each instruction with the production entry and title/Store source before writing.

## Do not
Touch code, game scenes, tests, package scripts, version numbers, screenshots, hosting output, configuration, or any other deliverable. No network, device or store actions. No claim that upload, purchase verification, review, merge, or production release is complete.

## Acceptance
The one text file is <=500 characters, is English and follows actual UI labels from the accepted review notes. It contains no obsolete no-account claim, credentials or links to the former public site. The director will independently read the actual entry source and verify length before copying exact bytes into the Play Console.

## Deliverables
Only notes/release/google-play-review-entry.txt.
