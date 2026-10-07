# Brief 227: preserve same-line UI validation around wire values

## The ask
Finish the accepted attendance feature's root validation without hiding real untranslated player text.

## Independently confirmed defect
In the completed brief-226 copy, the director planted one temporary script with:
`const payload = {"setToServerValue": "REQUEST_TIME", "label_key": "REQUEST_TIME"}`
The actual checker incorrectly exited 0. Evidence is `builds/verify/gate-wire-same-line-ui-negative.log` in the real tree. The probe file was removed. The `before.includes(SERVER_VALUE_FIELD)` exemption skips the unrelated stored UI occurrence too. The tr-call carve-out does not protect dictionary fields or other unrelated literals on that same line. This violates the original direct-value and same-line acceptance criteria. Do not accept round1 as finished.

## Do
- Narrow the exemption to the actual quoted occurrence: the direct value of the Firestore setToServerValue field, plus a tightly recognized protocol-value assertion/get comparison when needed by the real attendance regression. Merely naming a field earlier on a line is insufficient. Preserve the production game's protocol string and existing game regression unchanged.
- Add registered actual-checker fixtures for a transform followed by the same token as a stored label/dictionary value, unrelated warning literal, and field-name reference followed by a UI literal. They must fail and name REQUEST_TIME; the direct protocol occurrence remains allowed. Keep the existing same-line different-key and tr cases.
- Ensure the actual real tree still passes, including tests/test_cloud_attendance.gd's multiline _expect_equal getter expectation. Do not globally exempt REQUEST_TIME or exempt a whole file/line.
- Run the  existing and new scanner suite plus gate-locale tests; report narrow matching rules honestly.

## Scoped exception
The brief226 permission to edit exactly .github/scripts/check-locale.mjs still applies in this isolated copy. No other protected paths, workflows or acceptance tools may change. The director will independently review and accept with this exact-path allowance.

## Do not
No runtime/game/test GDScript changes, CSV additions, hidden string concatenations, asset/native/privacy/version/store changes or broad rewrites. Do not edit the director's notes.

## Acceptance
Real checker succeeds for the actual production payload and protocol assertion. All specified UI occurrences still fail, including same token beside a valid transform and unrelated use beside a mere field-name reference. Registered tests expose reverting to round1's exemption. No game bytes change.
