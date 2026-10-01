# Brief 026c: distinguish phone from tablet freshness

## The correction
This is a final notes-only correction on unaccepted tag 20261001-1951-chronicle-capture-persistence. The director previously gave you an overly broad staleness assertion. Actual reports show the generator is pinned in phone CAPTURE_INPUTS, but is absent from all 42 entries of Android tablet source_before_build/source_after_build/source_before/source_after and from tablet build-attestation inputs. The Python ANDROID_DEVICE_CAPTURE_SOURCE_INPUTS tuple likewise does not include the generator. Production runtime excludes tools/. Thus this two-line consumer fix invalidates the phone input proof, while it does not invalidate either tablet's source/build/persistence proof. The director will independently validate the unchanged tablet reports after acceptance, and only retry the authorized phone capture if those pass.

## Do
In notes/plans/3-0-0-build-log.md, correct the new brief026 freshness paragraph and final Not done summary to say the phone capture becomes stale after this pinned-input correction. The completed seven-/ten-inch captures remain current if their unchanged strict source/build/runtime/persistence checks pass. Do not claim those post-acceptance validations have happened. Preserve the existing measured tests and corrected local Android build checkpoints. This is the third round for record precision; the code fix was verified in the first round.

## Do not / acceptance
No code, tests, source inputs, fingerprints, capture proof files, assets, network, device or git changes. Do not rerun expensive tests. Generator hash must remain 0ecda3d2703b322cd33403c1fec7bacc03277153b95e42f7a29f8a902095cb05. Cumulative paths remain exactly the same three original deliverables. Avoid suggesting a whole-tablet recapture for a hash that is not in their contract.
