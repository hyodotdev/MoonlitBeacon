# Brief 144: Correct two confirmed Chinese localization errors

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”

## Evidence and correction
The newly added Chinese descriptions/release notes call the moon gate `关门` / `關門`, meaning closing a door instead of the game's gate. Use a natural noun consistently such as `月之门` / `月之門`, including the privacy draft where it refers to saved gate progress. The Traditional Chinese offline paragraph says `可以訪客身分享線使用`; correct it to natural text explicitly saying guest play works offline (`訪客身分離線`), preserving the online requirements in the next sentence. Inspect only the added Chinese passages for similarly obvious language errors and fix narrowly. Do not alter product CSV cells, behavior claims, identities, prices or any other language as a broad rewrite.

## Deliverables and acceptance
Same four files from brief 139, with a short localization correction entry in four-zero-copy-review.md. No code/runtime/stores/network/git/credential/image changes. Director reads full final delta, independently checks store metadata and verifies all product CSV rows remain byte identical. Previous verified privacy data-processing and linked-data checklist corrections stay intact. No claim of public publication or completed native purchase tests.
