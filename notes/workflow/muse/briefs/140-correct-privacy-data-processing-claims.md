# Brief 140: Correct privacy disclosure scope

## Correction to 139
The director rejects the current privacy draft's statement S2: “ID tokens, auth codes, emails, and display names stay inside the native sign-in calls ... The raw server UID is hashed before anything is written.” This is broader than the evidence and wrong as an SDK/backend guarantee. Keep all corrected listing improvements, but repair the draft and work note before acceptance.

## Confirmed evidence
- Native identity adapter get_id_token explicitly creates a private outcome with id_token; player_account emits id_token_ready and cloud traffic uses authentication tokens. These values are not confined to native login calls.
- cloud_schema PROFILE_FIELDS, RESERVATION_FIELDS and CHECKPOINT_FIELDS contain raw uid, and cloud_identity/cloud_checkpoint write it to owner-private Firestore documents. Only the local player_bindings cache uses a hashed UID. No statement may extend that hash to all SDK storage, logs or backend data.
- The director observed actual FirebaseAuth SDK auth-state/id-token listener logs containing the user's UID. Our bridge not intentionally logging credentials is not a blanket guarantee about SDK logs/session persistence.
- Google native request config uses profile/email identity flows; official Firebase Android Apple documentation says its default one-account-per-email setting requests name/email scopes. Do not publish an account-data-free claim because the game UI omits provider profile fields.

## Do
Replace S2 in all five translations with plain player-facing, accurate disclosure: Firebase and the chosen Google/Apple provider process identifiers, authentication/session credentials and profile fields made available by consent/provider settings to authenticate and recover the account; the game saves a public ID, private account-to-ID ownership and checkpoint records; email/profile information is not shown in public Hall rows. Qualify which local game-authored files hash UID; avoid claiming SDK authentication caches never persist anything. Keep secrets/credentials out of public ranking. Cite implementation for each application-data claim, and label provider retention/SDK details that remain to be audited.

Simplify the public draft: remove developer jargon such as payload, schema, atomic commit, best-effort and field names where those are not useful to players. Keep the source-citation table as internal review support. Explain sign-out/new guest versus signing back into an existing provider account without claiming a single install can have only one permanent ID. Explain account deletion as verified intended behavior without guaranteeing an untested native provider reauth branch; list actual iPad delete/reauth proof as pending. Do not claim optional analytics is permanently impossible or verified off just from defaults: the director must inspect final export config.

The “remote rules + TTL deployment” gate must distinguish currently deployed account/save/Hall rules from optional analytics TTL. The director already has owned-cloud deployment and native server ownership proof; an independent current ruleset readback remains appropriate. Do not introduce a mandatory 90-day TTL on persistent account checkpoints. Keep remaining provider/device/purchase/store evidence pending. Do not alter product identity, assets, runtime, scripts, tests or protected paths.

## Acceptance
Director can map local hash vs raw private backend UID vs ephemeral token use to production code. No native-only token claim, no blanket no-logs/no-SDK-persistence claim, no implication that provider profile data is never processed. All five player-facing drafts have the same substantive corrections. Existing metadata check/tests stay green. Full four-file diff only; report any ambiguity instead of inventing it.
