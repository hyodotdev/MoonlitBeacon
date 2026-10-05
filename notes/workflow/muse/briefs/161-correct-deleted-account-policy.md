# Brief 161: Correct deleted-account policy wording

## The ask
The user asked to host and manage every public/privacy/support document on
`moonlitbeacon.hyo.dev` and finish the 4.0.0 store release accurately.

## Why, and what good feels like
Published policy must describe the actual successful account-deletion path.
The English privacy bullet currently says all local saves and the on-device
account list remain after cloud-account deletion. That is too broad.

## Where things stand
The director confirmed `production_host.gd:814-845` deletes cloud records,
then the native Auth account, forgets that account's UID binding, removes
its journey slot, and rotates to a fresh guest. `_remove_account_slot`
at lines 1806-1817 removes the account's main/backup/revision/rejected
journey files. `player_account.gd:364-374` removes only that UID binding.
Other accounts' slots/bindings and separate Vault/IAP/local-ladder/settings
files are not touched. Do not claim disk operations can never fail, that
all local data is erased, or that store purchases are cancelled.

Current public files: `apps/player-care/content/{en,ko,ja,zh-Hans,zh-Hant}.mjs`
(verify exact filenames yourself). Native/runtime/capture source is frozen;
the director is capturing iPad screenshots and preparing the Play package.

## Do
Correct the existing deletion bullet in all five privacy translations to
say successful account deletion removes its cloud records and sign-in,
its local journey save files and on-device account binding; other accounts'
local saves and separate on-device files such as purchases/Vault/settings
remain. Keep concise, natural player-facing language and current format.
Read the production path and choose precise wording. No retention promises
for provider backups or completed store transactions.

## Do not
Change game files, auth, configs, scripts, generated files, Terms text,
support text, test logic, URLs, link targets, store metadata, or unrelated
copy. Do not network, deploy, capture, commit, or touch credentials.

## Acceptance
Only the five locale content files may change, one privacy bullet in each.
Meaning matches the production deletion sequence. All existing player-care
and hosting tests pass; build/check with the custom public origin passes;
Terms paragraph text remains exact with the in-game locale CSV.
No test weakening or new implementation-mirroring test is wanted.

## Deliverables
Five corrected privacy bullets and the implementer's report.

## Settle these yourself
Select natural translation phrasing and exact filenames from the repository.

## How the director will judge
Read the entire five-file diff, compare it with production source, run the
existing site tests/build/checks, then deploy and verify changed live pages.
