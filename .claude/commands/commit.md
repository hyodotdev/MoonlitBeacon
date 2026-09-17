# Commit

Branch → commit → (after confirmation) push → PR.

## Usage

```text
/commit [options] [path]
```

**Options**

- `--push` / `-p` : push to remote after commit (**user confirmation required**)
- `--pr` : create a PR after push
- `--all` / `-a` : commit everything in one go
- `<path>` : commit only that path (e.g. `apps/game`)

## Examples

```text
/commit apps/game
/commit --all
/commit apps/docs --push
```

---

## Push guard (absolute rule for this repo)

**Never push until the user has explicitly said "push".**
Even with `--push`, show what is going where and get confirmation immediately
before the push. The repo is still private and not yet open-sourced, so
undoing a push is painful.

Commits without confirmation are fine. A commit is local and can be undone.

## Internal-docs guard

A commit that only changes `notes/` and `.claude/` does not get a PR. End it
as a local commit. Those two folders are author-only working docs.

---

## 1. Check the branch

```bash
git branch --show-current
```

**If it is `main`**, cut a branch first.

```bash
git switch -c <type>/<topic>
```

**Branch-name rules**

Do not prefix with a tool name such as `codex/`, `claude/`, or `agent/`.

| Prefix | Used for | Example |
| --- | --- | --- |
| `feat/` | Game features | `feat/beacon-scene` |
| `fix/` | Bug fixes | `fix/vignette-scale` |
| `docs/` | Lesson prose and reference | `docs/chapter-02` |
| `media/` | Clips, posters, assets | `media/chapter-01-editor-clip` |
| `chore/` | Config and cleanup | `chore/gitignore` |
| `refactor/` | Structure changes | `refactor/title-menu` |

If a lesson number is involved, put it in the name: `docs/chapter-03-instances`.

## 2. Check current status

```bash
git status
git diff --stat
```

## 3. Staging

Stage by path. Do not mix game and docs in one commit.

```bash
git add apps/game          # game
git add apps/docs          # course site
git add notes              # author-only docs
```

## 4. Review the staging area

```bash
git diff --cached --stat
git diff --cached --name-only
```

**Must check before push**

```bash
# .godot/ must not be included — export_credentials.cfg holds the keystore password
git diff --cached --name-only | grep "\.godot/" && echo "!!! stop"

# Original asset ZIPs must not be included
git diff --cached --name-only | grep -E "_downloads/|_asset_sources/|\.zip$"

# Clips going into the repo must not exceed 1MB
find apps/docs/static/video -name "*.mp4" -size +1M
```

## 5. Commit

**Write commit messages in English.** This is an English course project.
Only the subject line follows conventional-commit form.

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <one-line summary>

<what changed and why>

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

**type**

| type | Contents |
| --- | --- |
| `feat` | New game feature |
| `fix` | Bug fix |
| `docs` | Lesson prose and reference |
| `media` | Clips, posters, images |
| `chore` | Config and cleanup |
| `refactor` | Same behavior, different structure |

**scope**

| scope | Path |
| --- | --- |
| `game` | `apps/game/` |
| `course` | `apps/docs/course/` |
| `docs` | `apps/docs/docs/` |
| `notes` | `notes/` |
| `skills` | `.claude/` |

**Do not write "Phase".** Number lessons `Lesson 1`, `Lesson 2`.
Commit messages too.

## 6. Push (after confirmation)

Show this and get confirmation before pushing.

```bash
git log origin/main..HEAD --oneline    # commits that will go up
git diff origin/main..HEAD --stat      # diff that will go up
```

Only after confirmation:

```bash
git push -u origin <branch>
```

:::warning You cannot open a PR if the remote is empty
A PR needs **the target branch on the remote**. On a first upload there is
no `main`, so a PR cannot be created.

Stand up `main` with an empty root commit first, then put the contents on a
branch and open a PR.

```bash
git commit --allow-empty -m "chore: initialize repository"   # staging must be empty or it is not really empty
git push -u origin main
git switch -c chore/initial-import
```

If you `git add` first, even `--allow-empty` commits everything staged.
That actually put 239 files into the root commit.
To undo, delete the ref with `git update-ref -d HEAD` (first commit, so
there is no `HEAD~1`).
:::

## 7. PR

```bash
gh pr create --base main --title "<type>(<scope>): <summary>" --body "$(cat <<'EOF'
## Summary

- <what changed, 1–3 lines>

## Changes

### <category>
- item

## Checked

- [ ] `godot --headless --path apps/game --quit` exit code 0
- [ ] `pnpm docs:build` passed
- [ ] Ran on a device (if applicable)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## 8. Label the PR

**If you opened a PR, you must label it.** That cuts the later cost of
"what did we change then?"

```bash
gh label list --limit 100          # see what exists first
gh api -X POST repos/hyodotdev/MoonlitBeacon/issues/<number>/labels \
  -f 'labels[]=🎮 game' -f 'labels[]=💨 ci'
```

:::danger `gh pr edit --add-label` fails silently in this repo
Projects (classic) is deprecated, so `gh pr edit` hits a GraphQL error when
it reads the PR. **Exit code is 0 and the error looks like a warning, so you
think the label stuck.**

```text
GraphQL: Projects (classic) is being deprecated ... (repository.pullRequest.projectCards)
```

For the same reason `gh pr edit --title` and `--body` do not work either.
Change title and body with
`gh api -X PATCH repos/<owner>/<repo>/pulls/<number> -f title=... -F body=@file`.

**Always confirm after attaching.** The response returns the full label set;
use that.

```bash
gh pr view <number> --json labels --jq '[.labels[].name] | join(" · ")'
```
:::

### Labels unique to this repo

| Label | When to attach |
| --- | --- |
| `🎮 game` | `apps/game/` — scenes, scripts, resources |
| `📚 course` | `apps/docs/course/` — lesson prose |
| `🎬 video` | Clips, posters, `notes/tools/capture/` |
| `🖼 assets` | Asset intake or replacement, manifest updates |

### Pick from org-wide labels

| Label | When to attach |
| --- | --- |
| `📖 documentation` | `apps/docs/docs/`, README, plans |
| `💨 ci` | `.github/workflows/` |
| `🤖 android` | APK, export preset, device work |
| `🎯 feature` | New feature |
| `🐛 bug` / `🛠 bugfix` | A bug and its fix |
| `፦ refactor` | Same behavior, different structure |
| `🎨 design` | Screen layout or presentation changes |
| `🔖 license` | License notices and source copies |
| `📘 release` | Version bump, shipping |
| `🚀 cd` | Pages deploy, deploy config |

**Do not create a label before searching with `gh label list`.**
There are 58 org-wide labels. Create one only when it really does not exist.

```bash
gh label create "<name>" --description "<description>" --color "<6-digit hex>"
```

## 9. Check CI

Opening a PR starts the workflows. **Look at the green lights before moving on.**

```bash
gh run list --limit 3
gh run view <run-id> --json jobs -q '.jobs[] | "\(.conclusion)  \(.name)"'
gh run view <run-id> --log-failed | tail -40    # on failure
```

| Workflow | When it runs |
| --- | --- |
| CI | Always — docs build · game check · repo rules |
| Android APK · AAB | PRs that change `apps/game/**` |
| Deploy Docs | Only when started manually from Actions |

---

## Commit order

If several tracks changed at once, split them in this order.

| Order | Path | Why |
| --- | --- | --- |
| 1 | `apps/game/` | Game first. Docs explain the game |
| 2 | `apps/docs/static/` | Clips and posters |
| 3 | `apps/docs/course/`, `apps/docs/docs/` | Lesson prose and reference |
| 4 | `notes/` | Plans and scripts |
| 5 | `.claude/`, `README.md` | How we work |

## Examples

**Game feature**

```text
feat(game): extract the beacon into its own scene

The brazier, flame, sparks, and smoke that lived inline in
title_menu.tscn now live in scenes/objectives/beacon.tscn.
Lesson 3 places three instances of it.

- PointLight2D energy is an export so intensity can be tuned
- The three particle systems stay as children (they must move as one)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

**Adding a clip**

```text
media(course): add Lesson 2 node-tree assembly clip

Silent 38s, 1212x736, 612KB. Inside the repo clip budget.
The 1920x1080 master with narration is in builds/footage/ (not in git).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

**Docs**

```text
docs(course): write Lesson 2 prose

- Explain nodes and scenes through the beacon scene
- Add the scene-save location rule in section 3-2
- Seven done criteria

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```
