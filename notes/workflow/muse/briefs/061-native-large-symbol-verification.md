# Brief 061: Verify the real large iOS archive

## Director evidence
After running the real dependency fetch again to regenerate absolute link paths, the scripted iOS Debug compile and archive merge succeed. Nine real frameworks and six original privacy bundles are staged correctly. The final verification fails: `export-inputs: could not read symbols (need Xcode nm)`.

The director ran the exact default `nm -gUj` invocation independently. Xcode nm exists and is healthy; Node execFileSync throws ENOBUFS after 1,056,768 output bytes because defaultExecFile has the default 1 MiB buffer. Injecting the same nm with a bounded 16 MiB buffer makes `verifyIosExportInputs` return `{ok:true,checks:[]}` on the real archive. This is a new verifier defect, not an SDK compile failure. Node 62 and Godot 188 suites pass cleanly independently.

## Do and scope
Continue this copy and fix bounded symbol-output handling for the real merged archive. Keep diagnostic distinctions between missing tool, failed command, overflow and missing entry symbol accurate. Preserve output caps, do not ignore errors, and add a meaningful regression for output larger than 1 MiB. Avoid changing already compiled native source or successful SDK/export packaging. Director repeats actual Debug/Release script builds and the game export with IAP. No gameplay/UI/cloud/project/presets/credentials/network/device/store/git edits.
