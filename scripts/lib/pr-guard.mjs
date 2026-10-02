// Decide whether one tool call would open a pull request.
//
// This exists because an agent once opened pull requests nobody had asked for.
// A rule in AGENTS.md is read once and forgotten; this is the part that does not
// depend on remembering. `scripts/guard-pull-request.mjs` runs it before every
// shell command and every MCP call and refuses the ones that create a PR.
//
// It reads the command the way a shell would, not as a string to grep. A command
// that only *mentions* `gh pr create` (a commit message, a heredoc that writes a
// docs page, a grep for the phrase) must pass, or the guard would fire on the very
// docs that explain it. Only a command that would actually run one is refused.

/** MCP tools, on any server, that create a PR or hand the job to an agent that will. */
const MCP_PR_TOOL = /^mcp__.+__(?:create_pull_request(?:_with_copilot)?|assign_copilot_to_issue)$/;

/** Words that sit in front of the real command without changing what it does. */
const WRAPPERS = new Set([
  'sudo', 'env', 'command', 'nohup', 'exec', 'time', 'builtin', 'xargs', 'stdbuf', 'nice',
  'then', 'do', 'else', '!',
]);

const SHELLS = new Set(['bash', 'sh', 'zsh', 'dash', 'ksh']);

/** `gh api` flags that take a value in the next word. */
const API_VALUE_FLAGS = new Set([
  '-X', '--method', '-H', '--header', '-f', '--raw-field', '-F', '--field', '-q', '--jq',
  '-t', '--template', '--input', '--hostname', '--cache', '-p', '--preview',
]);
/** `gh api` flags that put a body on the request, which makes it a POST. */
const API_BODY_FLAGS = new Set(['-f', '--raw-field', '-F', '--field', '--input']);

/**
 * @param {string} toolName
 * @param {unknown} toolInput
 * @returns {string | null} what was matched, or null when the call is fine
 */
export function findPullRequestCreation(toolName, toolInput) {
  if (typeof toolName !== 'string') return null;
  if (MCP_PR_TOOL.test(toolName)) return `MCP tool ${toolName}`;
  if (toolName !== 'Bash') return null;
  const command = toolInput && typeof toolInput === 'object'
    ? /** @type {{command?: unknown}} */ (toolInput).command
    : undefined;
  if (typeof command !== 'string') return null;
  return commandOpensPullRequest(command);
}

/** @param {string} command @param {number} [depth] */
export function commandOpensPullRequest(command, depth = 0) {
  if (depth > 3) return null;
  const { text, shellBodies } = splitHeredocs(command);
  const nested = [...shellBodies];
  for (const words of splitStatements(text, nested)) {
    const hit = statementOpensPullRequest(words, nested);
    if (hit) return hit;
  }
  for (const inner of nested) {
    const hit = commandOpensPullRequest(inner, depth + 1);
    if (hit) return hit;
  }
  return null;
}

/**
 * Cut heredoc bodies out of the command, so text that is only being written to a
 * file is not read as a command. A heredoc that is fed to a shell *is* a script,
 * so its body is handed back for a second look.
 *
 * @param {string} command
 * @returns {{text: string, shellBodies: string[]}}
 */
function splitHeredocs(command) {
  const shellBodies = [];
  const pattern = /<<-?[ \t]*(['"]?)([A-Za-z_][\w-]*)\1([^\n]*)\n([\s\S]*?)\n[ \t]*\2[ \t]*(?=\n|$)/g;
  const text = command.replace(pattern, (_match, _quote, _tag, rest, body, offset) => {
    // A heredoc is a script when a shell reads it: `bash <<EOF`, `bash -s <<EOF`,
    // or `cat <<EOF | bash`.
    const lineStart = command.lastIndexOf('\n', offset - 1) + 1;
    const before = command.slice(lineStart, offset).split(/[\s;&|()]+/).filter(Boolean);
    const feedsShell = before.some((word) => SHELLS.has(baseName(word)))
      || /\|\s*(?:sudo\s+)?(?:bash|sh|zsh|dash|ksh)\b/.test(rest);
    if (feedsShell) shellBodies.push(body);
    return `<<${rest}`;
  });
  return { text, shellBodies };
}

/**
 * Split a command into statements of unquoted words, the way a shell would.
 * Command substitutions found inside double quotes are pushed to `nested`, because
 * the shell runs those even though the words around them are only text.
 *
 * @param {string} text
 * @param {string[]} nested
 * @returns {string[][]}
 */
function splitStatements(text, nested) {
  const statements = [];
  let words = [];
  let word = '';
  let inWord = false;
  let quote = null;

  const endWord = () => {
    if (inWord) words.push(word);
    word = '';
    inWord = false;
  };
  const endStatement = () => {
    endWord();
    if (words.length) statements.push(words);
    words = [];
  };

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (quote === "'") {
      if (ch === "'") quote = null;
      else word += ch;
      continue;
    }
    if (quote === '"') {
      if (ch === '\\' && i + 1 < text.length) {
        word += text[i + 1];
        i += 1;
      } else if (ch === '"') {
        quote = null;
      } else if (ch === '$' && text[i + 1] === '(') {
        const end = matchingParen(text, i + 1);
        nested.push(text.slice(i + 2, end));
        word += text.slice(i, end + 1);
        i = end;
      } else if (ch === '`') {
        const end = text.indexOf('`', i + 1);
        const stop = end < 0 ? text.length : end;
        nested.push(text.slice(i + 1, stop));
        word += text.slice(i, stop + 1);
        i = stop;
      } else {
        word += ch;
      }
      continue;
    }
    if (ch === '\\') {
      if (text[i + 1] === '\n') {
        endWord();
        i += 1;
        continue;
      }
      inWord = true;
      if (i + 1 < text.length) {
        word += text[i + 1];
        i += 1;
      }
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      inWord = true;
      continue;
    }
    if (ch === '$' && text[i + 1] === '(') {
      endStatement();
      i += 1;
      continue;
    }
    if ('\n;|&(){}`'.includes(ch)) {
      endStatement();
      continue;
    }
    if (ch === ' ' || ch === '\t') {
      endWord();
      continue;
    }
    inWord = true;
    word += ch;
  }
  endStatement();
  return statements;
}

/** Index of the `)` that closes the `(` at `open`, or the end of the text. */
function matchingParen(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i += 1) {
    if (text[i] === '(') depth += 1;
    else if (text[i] === ')') {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return text.length;
}

/** @param {string} word */
function baseName(word) {
  return word.slice(word.lastIndexOf('/') + 1);
}

/** @param {string[]} words @param {string[]} nested */
function statementOpensPullRequest(words, nested) {
  let start = 0;
  while (start < words.length) {
    const word = words[start];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(word) || WRAPPERS.has(word)) {
      start += 1;
    } else if (word.startsWith('-') && start > 0 && WRAPPERS.has(words[start - 1])) {
      start += 1;
    } else {
      break;
    }
  }
  const command = words.slice(start);
  if (command.length === 0) return null;
  const program = baseName(command[0]);
  const args = command.slice(1);

  if (program === 'gh') return ghOpensPullRequest(args);
  if (program === 'hub') return args.includes('pull-request') ? 'hub pull-request' : null;
  if (program === 'curl' || program === 'wget' || program === 'http' || program === 'https') {
    return httpOpensPullRequest(args);
  }
  if (SHELLS.has(program)) {
    // `bash -c "..."`, also as `-lc`. The next word is the script.
    const flag = args.findIndex((arg) => /^-[a-zA-Z]*c[a-zA-Z]*$/.test(arg));
    if (flag >= 0 && args[flag + 1] !== undefined) nested.push(args[flag + 1]);
    return null;
  }
  if (program === 'eval') {
    nested.push(args.join(' '));
    return null;
  }
  return null;
}

/** @param {string[]} args */
function ghOpensPullRequest(args) {
  // Reading the help or a dry run creates nothing.
  if (args.includes('--help') || args.includes('-h') || args.includes('--dry-run')) return null;
  for (let i = 0; i < args.length - 1; i += 1) {
    if (args[i] === 'pr' && args[i + 1] === 'create') return 'gh pr create';
  }
  const api = args.indexOf('api');
  if (api < 0) return null;

  let method = null;
  let sendsBody = false;
  let endpoint = null;
  let mutation = false;
  for (let i = api + 1; i < args.length; i += 1) {
    const arg = args[i];
    if (arg.startsWith('-')) {
      const [flag, attached] = arg.includes('=') ? [arg.slice(0, arg.indexOf('=')), arg.slice(arg.indexOf('=') + 1)] : [arg, null];
      const short = /^-([XHfFqtp])(.+)$/.exec(arg);
      let name = flag;
      let value = attached;
      if (short) {
        name = `-${short[1]}`;
        value = short[2];
      }
      if (API_VALUE_FLAGS.has(name)) {
        if (value === null) {
          value = args[i + 1] ?? '';
          i += 1;
        }
        if (name === '-X' || name === '--method') method = value.toUpperCase();
        if (API_BODY_FLAGS.has(name)) sendsBody = true;
        if (/createPullRequest/.test(value)) mutation = true;
      }
    } else if (endpoint === null) {
      endpoint = arg;
    } else if (/createPullRequest/.test(arg)) {
      mutation = true;
    }
  }
  if (mutation) return 'gh api graphql createPullRequest';
  if (endpoint === null) return null;
  const writes = method ? method !== 'GET' : sendsBody;
  const path = endpoint.replace(/\?.*$/, '').replace(/^\/+/, '').replace(/\/+$/, '');
  if (writes && /^repos\/[^/]+\/[^/]+\/pulls$/.test(path)) return 'gh api POST /pulls';
  return null;
}

/** @param {string[]} args */
function httpOpensPullRequest(args) {
  const url = args.find((arg) => /api\.github\.com\/repos\/[^/\s]+\/[^/\s]+\/pulls\/?(?:\?.*)?$/.test(arg));
  if (!url) return null;
  const explicit = args.findIndex((arg) => arg === '-X' || arg === '--request');
  const method = explicit >= 0 ? (args[explicit + 1] ?? '').toUpperCase() : '';
  const sendsData = args.some((arg) => /^(?:-d|--data(?:-\w+)?|--json)(?:=|$)/.test(arg) || /^-d./.test(arg));
  if (method === 'POST' || (method === '' && sendsData)) return 'HTTP POST to the GitHub pulls endpoint';
  return null;
}
