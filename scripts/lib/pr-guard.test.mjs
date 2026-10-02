import assert from 'node:assert/strict';
import test from 'node:test';

import { commandOpensPullRequest, findPullRequestCreation } from './pr-guard.mjs';

const blocked = (command) => assert.notEqual(
  commandOpensPullRequest(command), null, `should be blocked: ${command}`);
const allowed = (command) => assert.equal(
  commandOpensPullRequest(command), null, `should pass: ${command}`);

test('blocks the plain gh command, with any prefix or wrapper', () => {
  blocked('gh pr create --base main --title "feat: x"');
  blocked('cd apps/game && gh pr create --fill');
  blocked('git push -u origin feat/x && gh pr create --fill');
  blocked('FOO=1 gh pr create');
  blocked('/opt/homebrew/bin/gh pr create --web');
  blocked('sudo gh pr create');
  blocked('gh -R hyodotdev/MoonlitBeacon pr create --fill');
  blocked('gh pr create \\\n  --base main \\\n  --title "x"');
  blocked('if true; then gh pr create; fi');
});

test('blocks it when the shell runs it indirectly', () => {
  blocked('url=$(gh pr create --fill)');
  blocked('echo "$(gh pr create --fill)"');
  blocked('echo "`gh pr create --fill`"');
  blocked('bash -c "gh pr create --fill"');
  blocked("sh -lc 'git push && gh pr create'");
  blocked('eval "gh pr create --fill"');
  blocked("bash <<'EOF'\ngh pr create --fill\nEOF");
  blocked("cat <<'EOF' | bash\ngh pr create --fill\nEOF");
});

test('blocks a PR made with the body from a heredoc, the way the docs show it', () => {
  blocked([
    'gh pr create --base main --title "docs: x" --body "$(cat <<\'EOF\'',
    '## Summary',
    '- one',
    'EOF',
    ')"',
  ].join('\n'));
});

test('blocks the API routes to the same result', () => {
  blocked('gh api -X POST repos/hyodotdev/MoonlitBeacon/pulls -f title=x -f head=a -f base=main');
  blocked('gh api repos/hyodotdev/MoonlitBeacon/pulls -f title=x -f head=a');
  blocked('gh api --method POST /repos/o/r/pulls --input body.json');
  blocked('gh api --method=POST repos/o/r/pulls');
  blocked('gh api -XPOST repos/o/r/pulls');
  blocked("gh api graphql -f query='mutation { createPullRequest(input: {}) { pullRequest { id } } }'");
  blocked('curl -X POST -H "Authorization: token $T" https://api.github.com/repos/o/r/pulls -d \'{"title":"x"}\'');
  blocked('curl -s https://api.github.com/repos/o/r/pulls --data @body.json');
  blocked('hub pull-request -m x');
});

test('blocks the MCP tools that open a PR, on any server', () => {
  assert.notEqual(findPullRequestCreation('mcp__github__create_pull_request', {}), null);
  assert.notEqual(findPullRequestCreation(
    'mcp__37f72c69-5049-482e-b842-e2c93f76e513__create_pull_request', {}), null);
  assert.notEqual(findPullRequestCreation('mcp__github__create_pull_request_with_copilot', {}), null);
  assert.notEqual(findPullRequestCreation('mcp__github__assign_copilot_to_issue', {}), null);
});

test('passes everything that only reads or edits a PR', () => {
  allowed('gh pr list --state all');
  allowed('gh pr view 8 --json title');
  allowed('gh pr checkout 5');
  allowed('gh pr diff 9');
  allowed('gh pr status');
  allowed('gh pr create --help');
  allowed('gh pr create --dry-run');
  allowed('gh api repos/o/r/pulls');
  allowed('gh api "repos/o/r/pulls?state=open"');
  allowed('gh api repos/o/r/pulls/9/comments -f body=x');
  allowed('gh api -X POST repos/o/r/issues/9/labels -f "labels[]=game"');
  allowed('gh api -X PATCH repos/o/r/pulls/9 -f title=x');
  allowed('curl -s https://api.github.com/repos/o/r/pulls');
  assert.equal(findPullRequestCreation('mcp__github__list_pull_requests', {}), null);
  assert.equal(findPullRequestCreation('mcp__github__pull_request_read', {}), null);
  assert.equal(findPullRequestCreation('mcp__github__update_pull_request', {}), null);
  assert.equal(findPullRequestCreation('Read', { file_path: '/x' }), null);
});

test('passes text that only mentions the command', () => {
  allowed('git commit -m "docs: explain when to run gh pr create"');
  allowed('grep -n "gh pr create" .claude/commands/commit.md');
  allowed("sed -i '' 's/gh pr create/gh pr view/' notes/x.md");
  allowed('echo gh pr create');
  allowed("cat <<'EOF' > commit.md\ngh pr create --base main\nEOF");
  allowed("python3 - <<'EOF'\nprint('gh pr create')\nEOF");
  allowed("git commit -m \"$(cat <<'EOF'\nfeat: x\n\nNever run gh pr create unasked.\nEOF\n)\"");
});

test('reads a Bash tool call and ignores every other tool', () => {
  assert.equal(findPullRequestCreation('Bash', { command: 'gh pr create --fill' }), 'gh pr create');
  assert.equal(findPullRequestCreation('Bash', { command: 'ls' }), null);
  assert.equal(findPullRequestCreation('Bash', {}), null);
  assert.equal(findPullRequestCreation('Write', { file_path: 'a', content: 'gh pr create' }), null);
  assert.equal(findPullRequestCreation(undefined, undefined), null);
});
