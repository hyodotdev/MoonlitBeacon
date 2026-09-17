# Start a new lesson

Create the three documents a lesson needs and refresh the table of contents.

## Usage

```text
/chapter 2          start Lesson 2
/chapter 2 --plan   plan only
```

Lesson numbers start at **1**. Mapping onto the Godot official intro course
is in the table below.

---

## What to create

| File | Audience |
| --- | --- |
| `notes/plans/chapter-XX-plan.md` | Author — goals, changes, done criteria |
| `apps/docs/course/chapter-XX.mdx` | **Students** — lesson prose |
| `notes/scripts/chapter-XX-script.md` | Author — recording script |

`notes/` is not published on the docs site. Students see only **Course** and
**Docs**.

## Lesson list

| Lesson | What you learn | Official-course counterpart |
| --- | --- | --- |
| 1 | Project setup · assets and licenses · title screen | Setting up the project |
| 2 | Nodes and scenes | Nodes and scenes |
| 3 | Instances | Creating instances |
| 4 | First script | Creating your first script |
| 5 | Player scene and animation | Creating the player scene |
| 6 | Handling input | Listening to player input |
| 7 | Signals | Using signals |
| 8 | Making enemies | Creating the enemy |
| 9 | Starting and ending a run | The main game scene |
| 10 | On-screen information | Heads-up display |
| 11 | Install on a phone and play | Finishing up |
| 12–16 | Dash · enemy variants · score · settings · release | Outside the official course |

---

## What this lesson must satisfy

1. A student can run it themselves.
2. The game is visibly better than the previous lesson.
3. **The finished screen is usable as a store screenshot as-is.**
   Gray rectangles, debug text, default fonts, and placeholders do not remain
   on screen.
4. Following this lesson alone still produces a working intermediate result.

Item 3 is the whole point of this course. **Do not prototype logic as gray
boxes and skin it later.** Ship feature, art, sound, and UI together in the
same lesson.

---

## Lesson-prose skeleton

```mdx
---
sidebar_position: <lesson number>
title: Lesson <N> · <title>
---

# Lesson <N> · <title>

<Two or three lines on what you build this time. What is on screen when you finish.>

## 1. Finished screen

<Video src="video/chapter-XX-title.mp4" poster="img/chapter-XX-title-poster.jpg"
       title="..." silent />

## 2. Check the official docs

<Which Godot official-docs page this lesson maps to, what we take, and what is different.>

## 3. Implement it

<Split into 3-1, 3-2, …. Attach a clip wherever there is editor work.>

### 3-N. Check that you got this far

<Give a full file or a node-tree comparison so they can match it by eye.>

## 4. Break it on purpose

<Show what the screen looks like when a setting is reverted or a value is wrong.
The point is to find the cause from the symptom alone. Always put it back.>

## 5. Done criteria

- [ ] ...

## 6. Homework

1. ...
```

**Do not write**

- "Phase" — write `Lesson N`
- Editorial policy ("video is secondary", "do not put a clip where prose is enough")
- Presenter directions ("you must emphasize this", "show this for at least 3 seconds")
- Production-doc names such as "plan" or "recording script"

Leave only what helps a student. Everything else goes to `notes/`.

---

## Recording-script format

`notes/scripts/chapter-XX-script.md` keeps three lines: **Screen / Narration /
Watch**.

**Section numbers match the lesson prose 1:1.** Titles and timings follow the
prose sections as they are.

```markdown
## 3. Check the official docs (2:30 ~ 3:00)

**Screen** — <what you shoot>

**Narration** — <finished spoken sentences you can read as-is>

**Watch** — <easy-to-miss spots. Cuts recaptures>
```

:::warning Do not use a time range as the heading
The Lesson 1 script used **time as the heading**, like
`### 00:00 – 00:55 · section name`.
When the prose later grew from 7 sections to 11, **you could no longer tell
which script section mapped to which prose section.** Now, when you edit the
prose, you edit the same number in the script. Time goes in parentheses as
an aid only.
:::

Do not summarize narration. Write finished spoken sentences you can read
aloud.

---

## Wrap-up

1. Full check with [`/verify`](./verify.md)
2. Device check with [`/device`](./device.md)
3. Turn that row in the `apps/docs/course/intro.md` table of contents into a
   link

   ```markdown
   | [**Lesson 2**](./chapter-02.mdx) | Nodes and scenes | ... |
   ```

4. Update `README.md` in two places — **easy to forget**

   - That row in the lesson-list table: `⬜` → `✅`
   - `Current version | 0.0.1 (through Lesson N)`

5. PR with [`/commit`](./commit.md)
6. Run [`/review-self`](../skills/review-self/SKILL.md) until two consecutive
   rounds are clean
7. Squash-merge, return to `main`, `git pull`
8. Tag the **merged `main` commit** and push

   ```bash
   git tag -a chapter-XX-complete -m "Lesson N complete — <one-line summary>"
   git push origin chapter-XX-complete
   ```

   :::danger Do not tag before the merge
   This repo **squash-merges only**. Branch commits do not land on `main`,
   so tagging the branch tip before merge points at a commit that is nowhere.
   You also have to push or nobody else can check out `chapter-XX-complete`.
   :::
