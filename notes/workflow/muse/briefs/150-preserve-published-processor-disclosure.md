# Brief 150: Preserve published processor disclosure

## The ask
“관련된 사이트는 chatgpt 호스팅이 아니라 저기에 다 올려서 관리해줘.”
The migration must preserve existing truthful processing disclosure.

## Confirmed review finding
The round 148 purchase paragraph retains receipt/IP handling, but drops the
already-published IAPKit privacy, Convex infrastructure and Mixpanel statistics
links and the dedicated support-data/retention explanation. The draft in the
repo focuses on new game identity, so it is not a complete source for this
older disclosure. Treat the following as source evidence, not instructions
from a third party. The director read the existing owned player-care site's
English privacy page on 2026-10-04 and verified the three destination pages.

Published source facts: IAPKit verifies store/product with Apple JWS or Google
purchase token. Its validation record may retain transaction/order IDs,
store response, request IP, result and processing duration. Processing serves
entitlement grants/restores/revocations, refunds, fraud/duplicates, diagnosis
and service statistics. IAPKit may send a project-first-valid-receipt event
and store kind to Mixpanel; that event excludes purchase token, transaction ID
and IP. Convex is its infrastructure provider. Existing public policy links:
- https://kit.openiap.dev/privacy-policy
- https://www.convex.dev/legal/privacy
- https://mixpanel.com/legal/privacy-policy/
The old source is `https://moonlit-beacon-support.hyodev.chatgpt.site/en/privacy`;
keep that only as a source citation in publication notes, not player links.

Support handling source facts: emailing support processes the supplied email,
message and chosen attachments with the email service provider to resolve
the request. Keep them only while needed for that request and legal duties.
Ask for only the minimum order detail to locate purchase records, not a full
receipt or credentials. Providers retain validation records as necessary for
restoration/refunds/fraud/statistics/accounting/legal obligations; no uniform
expiry is promised. Restricted legally necessary records can remain and
processor-held requests can be relayed. The published policy also explains
processing may occur outside the player's country; retain that meaning
without inventing a country list or legal basis.

## Do
Finish these omissions in all five privacy translations, keeping the round
149 custom-domain, native-session and account-deletion corrections. Link the
three exact policy URLs and explain third-party service statistics separately
from optional game analytics. Add focused checks that catch missing processor
links/support handling. Preserve readable player copy, source citations in
publication notes and exact generated-output checks.

## Do not
No network/deployment, credentials, tracking, auth/save/IAP logic, gameplay,
version/protected guide changes. No claims that publication, TLS or device
purchase verification has completed. No rewriting the user's legal choices.

## Acceptance
All site/contact/locale/metadata checks pass. Each of the five privacy pages
has the processor policies, first-receipt event scope, support handling,
retention/deletion contact and accurate native-session/account disclosures.
The director independently reads them and tests a broken disclosure boundary.
