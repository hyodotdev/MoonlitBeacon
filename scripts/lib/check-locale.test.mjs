import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test, { after } from 'node:test';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const checker = join(repository, '.github/scripts/check-locale.mjs');
const realNoto = join(
  repository,
  'apps/game/assets/third_party/fonts/NotoSansCJKsc-Regular.otf',
);

const sandbox = mkdtempSync(join(tmpdir(), 'moonlit-check-locale-'));
after(() => rmSync(sandbox, { recursive: true, force: true }));

const LOCALES = ['ko', 'en', 'ja', 'zh_CN', 'zh_TW'];

// Smallest tree the checker accepts: one translated key, the five resource
// paths, and the font wiring it pins. Sources carry the case under test.
function writeFixture(name, sources) {
  const root = join(sandbox, name);
  const game = join(root, 'apps/game');
  const write = (relative, content) => {
    const full = join(game, relative);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, content);
  };
  write(
    'localization/moonlit.csv',
    `keys,${LOCALES.join(',')}\nVALID_KEY,확인,valid,有効,有效,有效\n`,
  );
  write(
    'project.godot',
    '[internationalization]\n'
      + `locale/translations=PackedStringArray(${
        LOCALES.map((locale) => `"res://localization/moonlit.${locale}.translation"`).join(', ')
      })\n`,
  );
  for (const resource of [
    'Galmuri11-Multilingual.tres',
    'NotoSansCJKsc-SyntheticBold.tres',
    'Galmuri11-Bold-Multilingual.tres',
  ]) {
    write(`assets/third_party/fonts/${resource}`, '[resource]\npath="NotoSansCJKsc-Regular.otf"\n');
  }
  for (const name of ['MaplestoryLight.ttf.import', 'MaplestoryBold.ttf.import']) {
    write(`assets/third_party/fonts/${name}`, 'allow_system_fallback=false\n');
  }
  write(
    'assets/third_party/fonts/NotoSansCJKsc-Regular.otf.import',
    'allow_system_fallback=true\n',
  );
  const noto = join(game, 'assets/third_party/fonts/NotoSansCJKsc-Regular.otf');
  try {
    symlinkSync(realNoto, noto);
  } catch {
    copyFileSync(realNoto, noto);
  }
  for (const [relative, content] of Object.entries(sources)) {
    write(relative, content);
  }
  return root;
}

function runChecker(root) {
  const result = spawnSync(process.execPath, [checker], {
    cwd: root,
    encoding: 'utf8',
    timeout: 60000,
  });
  assert.equal(result.error, undefined, `checker did not start: ${result.error}`);
  return result;
}

function assertPasses(name, sources) {
  const output = runChecker(writeFixture(name, sources));
  assert.equal(output.status, 0, `${output.stderr}${output.stdout}`);
}

function assertRejectsKey(name, sources, key) {
  const output = runChecker(writeFixture(name, sources));
  assert.notEqual(output.status, 0, `checker passed but should reject ${key}`);
  assert.match(
    output.stderr,
    new RegExp(`${key} is not in the translation table`),
    `rejection names ${key}: ${output.stderr}`,
  );
  return output;
}

test('server timestamp transform is protocol, not a UI key', () => {
  assertPasses('protocol-transform', {
    'scripts/cloud_attendance.gd': 'extends RefCounted\n'
      + '\n'
      + 'static func commit_body() -> String:\n'
      + '\tvar write: Dictionary = {\n'
      + '\t\t"update": {"name": "doc", "fields": {}},\n'
      + '\t\t"updateTransforms": [{\n'
      + '\t\t\t"fieldPath": "last_claim_at",\n'
      + '\t\t\t"setToServerValue": "REQUEST_TIME",\n'
      + '\t\t}],\n'
      + '\t}\n'
      + '\treturn JSON.stringify({"writes": [write]})\n'
      + '\n'
      + 'func show(label: Label) -> void:\n'
      + '\tlabel.text = tr("VALID_KEY")\n',
  });
});

test('assertion of the transform value is protocol too', () => {
  assertPasses('protocol-assertion', {
    // Mirrors the real attendance test: the expected wire value sits on a
    // line that names the field, not as a `"field": value` pair.
    'tests/test_cloud_attendance.gd': 'extends SceneTree\n'
      + '\n'
      + 'func check(write: Dictionary) -> void:\n'
      + '\tvar transforms: Array = write.get("updateTransforms", [])\n'
      + '\tassert(str((transforms[0] as Dictionary).get(\n'
      + '\t\t"setToServerValue", "")), "REQUEST_TIME")\n'
      + '\n'
      + 'func show(label: Label) -> void:\n'
      + '\tlabel.text = tr("VALID_KEY")\n',
  });
});

test('nonexistent real UI key still fails', () => {
  assertRejectsKey('missing-ui-key', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show() -> void:\n'
      + '\tgood.text = tr("VALID_KEY")\n'
      + '\tbad.text = tr("MISSING_UI_KEY")\n',
  }, 'MISSING_UI_KEY');
});

test('REQUEST_TIME passed to tr is still a UI key', () => {
  assertRejectsKey('tr-request-time', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show(label: Label) -> void:\n'
      + '\tlabel.text = tr("REQUEST_TIME")\n',
  }, 'REQUEST_TIME');
});

test('REQUEST_TIME as scene text is still a UI key', () => {
  assertRejectsKey('scene-request-time', {
    'scenes/panel.tscn': '[gd_scene load_steps=2 format=3]\n'
      + '\n'
      + '[node name="Label" type="Label"]\n'
      + 'text = "REQUEST_TIME"\n',
  }, 'REQUEST_TIME');
});

test('REQUEST_TIME stored as a label key is still a UI key', () => {
  assertRejectsKey('stored-request-time', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'const REMINDER_LABEL: String = "REQUEST_TIME"\n',
  }, 'REQUEST_TIME');
});

test('unrelated REQUEST_TIME literal is still a UI key', () => {
  assertRejectsKey('bare-request-time', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show() -> void:\n'
      + '\tpush_warning("REQUEST_TIME")\n',
  }, 'REQUEST_TIME');
});

test('transform line does not hide a missing UI key beside it', () => {
  const output = assertRejectsKey('protocol-plus-ui', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show() -> void:\n'
      + '\tvar write := {"setToServerValue": "REQUEST_TIME", "title": "MISSING_UI_KEY"}\n',
  }, 'MISSING_UI_KEY');
  assert.doesNotMatch(
    output.stderr,
    /REQUEST_TIME is not in the translation table/,
    `protocol occurrence stays exempt: ${output.stderr}`,
  );
});

test('tr use beside a transform is still a UI key', () => {
  assertRejectsKey('protocol-plus-tr', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show(label: Label) -> void:\n'
      + '\tvar write := {"setToServerValue": "REQUEST_TIME"}; label.text = tr("REQUEST_TIME")\n',
  }, 'REQUEST_TIME');
});

test('same token stored as a label beside a transform still fails', () => {
  assertRejectsKey('protocol-plus-stored', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show() -> void:\n'
      + '\tconst payload = {"setToServerValue": "REQUEST_TIME", "label_key": "REQUEST_TIME"}\n',
  }, 'REQUEST_TIME');
});

test('unrelated warning literal beside a transform still fails', () => {
  assertRejectsKey('protocol-plus-warning', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show() -> void:\n'
      + '\tvar write := {"setToServerValue": "REQUEST_TIME"}; push_warning("REQUEST_TIME")\n',
  }, 'REQUEST_TIME');
});

test('UI literal after a mere field-name reference still fails', () => {
  assertRejectsKey('field-reference-plus-ui', {
    'scripts/panel.gd': 'extends Control\n'
      + '\n'
      + 'func show() -> void:\n'
      + '\tprint("setToServerValue", "REQUEST_TIME")\n',
  }, 'REQUEST_TIME');
});
