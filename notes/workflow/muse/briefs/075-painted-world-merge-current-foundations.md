# Brief 075: integrate the reviewed painted world with the accepted foundations

## The task / evidence
The 4.0.0 painted actor/world patch is independently reviewed: six heroes/four facings, seven spirits/four facings, twelve guardian variants/all states, six rooms and all 89 packed outputs. Director windowed capture has 31 clean images; all six corrected floors have been inspected; resource tests pass 1176 and packing byte-check passes 89. The completed source copy is the sibling run `20261002-2248-painted-world-assets/work`; its `changes.patch` is the complete reviewed change. Read its report-4.md and notes/plans/4-0-0-art-build-log.md for the measured limits. This is integration, not redesign.

Ordinary accept --check refuses only because the real asset manifest changed after the old snapshot: GateEntry and six painted held weapons are now accepted, alongside Journey, cloud services and native identity. A new snapshot must reconcile the reviewed art against those accepted bytes. The director will stage the reviewed patch as `builds/director-inputs/painted-world.patch` in your copy once the runner creates it; the sibling run's patch is also readable. Do not modify the old run, the real tree, runner state or git history.

## Do
Apply the reviewed source/binary changes into this fresh working copy. Reconcile the asset manifest/custom contracts by retaining every accepted GateEntry/weapon entry and adding the painted actor/world entries truthfully. Preserve the current painted WeaponRig and every account/entry/Journey/cloud/native file. Art owns body/actor visual metadata, room/terrain visual sources and packers/tests/harnesses as in the old patch. No new artwork, source rebuilding or mechanics changes.

For this integration only, the two reviewed minimal registry additions are authorized: add the direct painted-world contract row to the shared Godot runner, and add pack_painted_world.py --check to check:assets. Preserve every existing row/script/dependency; do not delete existing assertions. This settles the old deferred registration without granting unrelated runner changes.

Verify pack bytes, painted-world contracts, relevant current hero/terrain/guardian checks and assets/locales, importing the Godot class cache first through an isolated invocation if necessary. Report any pre-existing sandbox CA-cert/editor limitation honestly; do not weaken checks or spend a new full development loop on untouched modules. Leave final whole-tree verification/device play to the director. All locked project/export values and original source/provenance remain unchanged.

## Acceptance
The new ordinary `muse accept --check` applies cleanly to the real accepted tree, current GateEntry/weapon assets and data-safe foundations remain byte-identical, 89 outputs byte-verify and 1176 resource assertions remain green, no protected paths or credentials, no marketing recapture/store/network/history. The director repeats affected tests, renders the integrated bodies/held weapons/rooms and checks gameplay performance after acceptance.
