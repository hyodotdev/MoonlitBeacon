# Course practice checkpoints · Lessons 1–16

Runnable end states for the full course. Each lesson's output
is a complete standalone Godot project a learner creates from a fresh clone
and compares against their own blank project — never a file they paste over
their work.

```bash
node scripts/course-create.mjs --lesson 5
node scripts/course-create.mjs --lesson 16 --out builds/course/lesson-16
node scripts/course-create.mjs --list
node scripts/course-create.mjs --help
```

Outputs default to `builds/course/lesson-NN/` (gitignored). A custom folder
must be new or empty; the command refuses existing learner work, source
folders, path traversal, and symlink escapes. Only the assets each lesson
introduced are copied — never whole packs or caches.

Read the full walkthrough at [Practice checkpoints · Lessons 1–16](https://moonlitbeacon.hyo.dev/MoonlitBeacon/course/practice-foundation):
exact setup, per-lesson file changes and editor steps, one modification
exercise each, and what differs from the historical clips.

Reuse: [REUSE.md](./REUSE.md) lists every binary's upstream source and
license. No native plugins, secrets, ignored original packs, tracked ZIPs,
gray placeholders, or default fonts anywhere in these sources.
