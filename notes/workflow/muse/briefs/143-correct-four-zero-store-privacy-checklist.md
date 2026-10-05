# Brief 143: Correct the release checklist's account data disclosures

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”

## Confirmed remaining defect after 140
notes/release/store-page.md lines around 93–104 now name 4.0.0 but still state that an analytics-disabled release collects only purchase verification data and keeps only Purchase History/Diagnostic Data labels. That is false for the implemented 4.0.0 account, private cloud saves and public Hall. Optional analytics being off does not remove the mandatory authentication/account/game progress flows.

## Correction
Replace only that checklist's stale privacy assumptions with an evidence-based release audit that covers Firebase account/provider processing, public player ID/private auth ownership, linked gameplay/checkpoint/score/Hall data and existing IAP verification. Distinguish actual collected/provider-processed data from fields the game publicly displays; email/profile processing must follow SDK scopes and final native consent/build evidence, never guessed as absent. Do not prescribe unchecked store label answers as final. Clarify optional gameplay analytics remains a separate default-off feature whose shipped config must be inspected. Update the distinct copy-review note to record this confirmed correction and keep both final store privacy answers and public-site publication pending until performed by the director. Leave all product CSV fields, current good 4.0.0 copy and corrected privacy draft intact unless a direct factual inconsistency needs repair. Keep player-facing privacy prose plain; raw references/schema/audit plumbing belongs in internal evidence, not published player text.

## Acceptance
Director checks the full patch and independently runs check:store-metadata plus related existing store tests. No 4.0.0 privacy checklist says only purchase data is collected or that gameplay/account data is unlinked. No claim that actual provider/purchase/device tests, public-site edit, store review, remote merge or submission have occurred. Same four-file scope as brief 139; no production code, stores, images, credentials, network or git history changes.
