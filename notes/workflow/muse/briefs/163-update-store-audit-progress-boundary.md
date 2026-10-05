# Brief 163: Keep the store audit's release boundary current

## Correction
Continue Brief 162's one-document edit. The classification and deletion
wording correction is accepted in principle, but §7 item 9 still states
that both stores contain only 3.0.0 and nothing has been uploaded. That is
now false: the director successfully committed Play internal track
4.0.0 versionCode 17, with five listings and 90 new screenshots, and its
read-only live audit observed internal artifact 17 published. Production
remains 3.0.0 versionCode 16. App Store review still has 3.0.0 build 11;
4.0.0 native IAP testing, PR/main merge and both-store final review remain
unfinished. Replace that stale claim with this exact limited observed
progress, keeping explicit separation between internal testing and public
production/review. Do not claim final App Store assets/build exist yet.

Only notes/release/privacy-four-zero-store-audit.md may change. Preserve
all earlier Brief 162 scope, source facts, evidence and proposals. Existing
hygiene check must pass. No networking, source/capture changes or git work.
