# Brief 027b: align the screenshot framing instructions

Continue brief 027 before acceptance. Its code/test diff is sound, but the report identifies contradictory instructions in notes/release/store-assets/README.md.

Update only the two passages describing combat debug-strip cropping: current capture automation hides debug UI before capture, and the three clean combat sources must keep their full viewport including the new dialogue ribbon and dash control. Title's existing 90-pixel policy stays unchanged. Also correct the adjacent tablet-source sentence: seven-inch and ten-inch images use their respective native Android tablet captures, not a Pixel phone capture. Keep the existing minimum-change recapture rules and all strict provenance requirements.

Leave the accepted-in-principle generator/config/test diff unchanged. Add this README path to the report and exact changed-file count in the build-log record where necessary. No game/runtime/capture/remote operations, no new tests or redesign. Do not claim current final screenshots or deployment completed.

The director will independently run the registered package suite and meaningful crop-negative control, then accept once, validate retained tablets, and produce the newly framed phone submission images.
