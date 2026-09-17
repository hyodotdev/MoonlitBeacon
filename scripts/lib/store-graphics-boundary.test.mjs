import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import test from 'node:test';

test('store screenshot cleanup does not delete files outside a symbolic link', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-store-graphics-boundary-'));
  try {
    const outside = join(root, 'outside');
    const release = join(root, 'builds/release');
    const linkedOutput = join(release, 'screenshots');
    const victim = join(outside, 'stale.png');
    mkdirSync(outside, { recursive: true });
    mkdirSync(release, { recursive: true });
    writeFileSync(victim, 'must survive');
    symlinkSync(outside, linkedOutput, 'dir');

    const source = `
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_boundary", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = Path(sys.argv[2])
module.RELEASE_OUTPUT_ROOT = module.REPO_ROOT / "builds/release"
module._remove_stale_screenshots(Path(sys.argv[3]), set())
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        source,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
        linkedOutput,
      ],
      {
        cwd: resolve('.'),
        encoding: 'utf8',
      },
    );
    assert.notEqual(result.status, 0);
    assert.match(`${result.stdout}\n${result.stderr}`, /symbolic link/u);
    assert.equal(readFileSync(victim, 'utf8'), 'must survive');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('derived store screenshots must match the current contract deterministic SHA-256', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-store-graphics-hash-'));
  try {
    const release = join(root, 'builds/release');
    mkdirSync(join(release, 'play'), { recursive: true });

    const source = `
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_hash", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = Path(sys.argv[2])
module.RELEASE_OUTPUT_ROOT = module.REPO_ROOT / "builds/release"
actual_a = module.RELEASE_OUTPUT_ROOT / "play/a.png"
actual_b = module.RELEASE_OUTPUT_ROOT / "play/b.png"
actual_a.write_bytes(b"first-image")
actual_b.write_bytes(b"second-image")

def regenerate(_entries, _reviews, _ffmpeg, _hb_view, _font, _work,
               play_root, _app_store_root, _iap_root):
    expected_a = play_root / "a.png"
    expected_b = play_root / "b.png"
    expected_a.parent.mkdir(parents=True)
    expected_a.write_bytes(b"first-image")
    expected_b.write_bytes(b"second-image")
    return [expected_a, expected_b]

module._render_all_screenshot_outputs = regenerate
module._assert_generated_screenshots_deterministic(
    [], [], [actual_a, actual_b], "ffmpeg", "hb-view")
actual_a.write_bytes(b"second-image")
actual_b.write_bytes(b"first-image")
try:
    module._assert_generated_screenshots_deterministic(
        [], [], [actual_a, actual_b], "ffmpeg", "hb-view")
except RuntimeError as error:
    if "differs from deterministic regeneration" not in str(error):
        raise
else:
    raise RuntimeError("swapped screenshots were accepted")
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        source,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      {
        cwd: resolve('.'),
        encoding: 'utf8',
      },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Play-only generation handles only the 90 Android images and does not call App Store boundaries', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-play-only-boundary-'));
  try {
    const probe = `
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_play_only", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.RELEASE_OUTPUT_ROOT = root / "builds/release"
module.PLAY_SCREENSHOT_OUTPUT = module.RELEASE_OUTPUT_ROOT / "play"
module.STALE_PLAY_SCREENSHOT_OUTPUT = module.PLAY_SCREENSHOT_OUTPUT / "screenshots"
module.APP_STORE_SCREENSHOT_OUTPUT = module.RELEASE_OUTPUT_ROOT / "app-store"
module.IAP_REVIEW_OUTPUT_ROOT = module.APP_STORE_SCREENSHOT_OUTPUT / "iap-review"
module.RELEASE_OUTPUT_ROOT.mkdir(parents=True)
apple_marker = module.APP_STORE_SCREENSHOT_OUTPUT / "keep.txt"
apple_marker.parent.mkdir(parents=True)
apple_marker.write_text("untouched", encoding="utf-8")

entries = [{"output": f"{index:02d}.png"} for index in range(1, 7)]
selected = []
module._validate_device_capture_reports_for_targets = (
    lambda _entries, devices: selected.extend(tuple(devices)))
module._validate_play_device_capture_reports(entries)
if selected != list(module.PLAY_TABLET_FORMATS):
    raise RuntimeError(f"wrong Play device targets: {selected}")
if any(module.DEVICE_CAPTURE_TARGETS[target]["platform"] != "android"
       for target in selected):
    raise RuntimeError("Play validator selected an iOS target")

rendered = []
def phone(_ffmpeg, _hb, _font, entry, _index, locale, _work, _root):
    path = module.PLAY_SCREENSHOT_OUTPUT / locale / "screenshots" / entry["output"]
    rendered.append(("phone", locale, entry["output"]))
    return path
def tablet(_ffmpeg, _hb, _font, entry, _index, locale, device, _spec,
           _work, _root):
    path = module.PLAY_SCREENSHOT_OUTPUT / locale / device / entry["output"]
    rendered.append((device, locale, entry["output"]))
    return path
module._render_play_screenshot = phone
module._render_play_tablet_screenshot = tablet
module._render_app_store_screenshot = lambda *args: (_ for _ in ()).throw(
    RuntimeError("App Store renderer was called"))
module._render_iap_review_screenshot = lambda *args: (_ for _ in ()).throw(
    RuntimeError("IAP review renderer was called"))
outputs = module._render_play_screenshot_outputs(
    entries, "ffmpeg", "hb-view", Path("font"), root / "work",
    module.PLAY_SCREENSHOT_OUTPUT)
if len(outputs) != 90 or len(set(rendered)) != 90:
    raise RuntimeError(f"Play renderer did not produce exactly 90 outputs: {len(outputs)}")

# A successful publish removes unknown locale/device/non-PNG leftovers via root replacement.
(module.PLAY_SCREENSHOT_OUTPUT / "fr-FR" / "screenshots").mkdir(parents=True)
(module.PLAY_SCREENSHOT_OUTPUT / "fr-FR" / "screenshots/stale.jpg").write_bytes(b"stale")
outside = root / "outside-must-survive.bin"
outside.write_bytes(b"outside")
(module.PLAY_SCREENSHOT_OUTPUT / "fr-FR" / "screenshots/external-link").symlink_to(
    outside)
(module.PLAY_SCREENSHOT_OUTPUT / "en-US" / "old-tablet").mkdir(parents=True)
(module.PLAY_SCREENSHOT_OUTPUT / "en-US" / "old-tablet/stale.png").write_bytes(b"stale")
(module.PLAY_SCREENSHOT_OUTPUT / "en-US" / "screenshots").mkdir(parents=True)
(module.PLAY_SCREENSHOT_OUTPUT / "en-US" / "screenshots/stale.jpg").write_bytes(b"stale")

module.shutil.which = lambda name: name
module._screenshot_entries = lambda: entries
module._validate_capture_report = lambda _entries: None
module._validate_play_device_capture_reports = lambda _entries: None
module._validate_device_capture_reports = lambda _entries: (_ for _ in ()).throw(
    RuntimeError("full device validator was called"))
module._validate_marketing_glyphs = lambda _entries: ("hb-shape", "hb-view")
def staged_render(_entries, _ffmpeg, _hb, _font, _work, play_root):
    staged = []
    for entry in entries:
        for locale in module.SCREENSHOT_LOCALES:
            play_locale = module.PLAY_LOCALES[locale]
            for device in ("screenshots", *module.PLAY_TABLET_FORMATS):
                path = play_root / play_locale / device / entry["output"]
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(f"{locale}:{device}:{entry['output']}".encode())
                staged.append(path)
    return staged
module._render_play_screenshot_outputs = staged_render
module._validate_generated_play_screenshots = (
    lambda _entries, root=None: sorted(root.rglob("*.png")))
built = module._build_play_screenshots()
if len(built) != 90 or any(not path.is_file() for path in built):
    raise RuntimeError("Play-only builder did not publish exactly 90 outputs")
if (module.PLAY_SCREENSHOT_OUTPUT / "fr-FR").exists() \
        or (module.PLAY_SCREENSHOT_OUTPUT / "en-US/old-tablet").exists() \
        or (module.PLAY_SCREENSHOT_OUTPUT / "en-US/screenshots/stale.jpg").exists():
    raise RuntimeError("Play-only publish retained stale output tree entries")
if apple_marker.read_text(encoding="utf-8") != "untouched":
    raise RuntimeError("Play-only builder changed an App Store file")
if outside.read_bytes() != b"outside":
    raise RuntimeError("Play-only stale cleanup followed an external symlink")
print(json.dumps({"outputs": len(built), "devices": selected}))
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.deepEqual(JSON.parse(result.stdout.trim().split('\n').at(-1)), {
      devices: ['seven-inch-tablet', 'ten-inch-tablet'],
      outputs: 90,
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Play checks reject unknown locale, device, and non-PNG stale files', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-play-stale-tree-'));
  try {
    const probe = `
import importlib.util
import shutil
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_stale", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.RELEASE_OUTPUT_ROOT = root / "builds/release"
module.PLAY_SCREENSHOT_OUTPUT = module.RELEASE_OUTPUT_ROOT / "play"
entries = [{"output": f"{index:02d}.png"} for index in range(1, 7)]
module._validate_screenshot_file = lambda *args: None

def reset():
    shutil.rmtree(module.PLAY_SCREENSHOT_OUTPUT, ignore_errors=True)
    for _label, directory, _size in module._play_screenshot_output_sets():
        directory.mkdir(parents=True, exist_ok=True)
        for entry in entries:
            (directory / entry["output"]).write_bytes(b"png")

def reject(label, add_stale):
    reset()
    add_stale()
    try:
        module._validate_play_screenshot_outputs(entries)
    except RuntimeError:
        return
    raise RuntimeError(f"stale Play tree was accepted: {label}")

reset()
if len(module._validate_play_screenshot_outputs(entries)) != 90:
    raise RuntimeError("valid Play tree did not contain 90 outputs")
reject("locale", lambda: (module.PLAY_SCREENSHOT_OUTPUT / "fr-FR").mkdir())
reject("device", lambda: (
    module.PLAY_SCREENSHOT_OUTPUT / "en-US" / "old-tablet").mkdir())
reject("non-png", lambda: (
    module.PLAY_SCREENSHOT_OUTPUT / "en-US" / "screenshots" / "stale.jpg"
).write_bytes(b"stale"))
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Play render failure preserves the existing canonical root byte-exact', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-play-atomic-failure-'));
  try {
    const probe = `
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_atomic", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.RELEASE_OUTPUT_ROOT = root / "builds/release"
module.PLAY_SCREENSHOT_OUTPUT = module.RELEASE_OUTPUT_ROOT / "play"
module.STALE_PLAY_SCREENSHOT_OUTPUT = module.PLAY_SCREENSHOT_OUTPUT / "screenshots"
old = module.PLAY_SCREENSHOT_OUTPUT / "keep.bin"
old.parent.mkdir(parents=True)
old.write_bytes(b"known-good")
module.shutil.which = lambda name: name
module._screenshot_entries = lambda: [{"output": "01.png"}]
module._validate_capture_report = lambda _entries: None
module._validate_play_device_capture_reports = lambda _entries: None
module._validate_marketing_glyphs = lambda _entries: ("hb-shape", "hb-view")
def fail_after_write(_entries, _ffmpeg, _hb, _font, _work, play_root):
    output = play_root / "en-US/screenshots/01.png"
    output.parent.mkdir(parents=True)
    output.write_bytes(b"partial-new")
    raise RuntimeError("render-failed")
module._render_play_screenshot_outputs = fail_after_write
try:
    module._build_play_screenshots()
except RuntimeError as error:
    if str(error) != "render-failed":
        raise
else:
    raise RuntimeError("render failure was accepted")
if old.read_bytes() != b"known-good" \
        or sorted(path.name for path in module.PLAY_SCREENSHOT_OUTPUT.iterdir()) != ["keep.bin"]:
    raise RuntimeError("failed Play render changed canonical root")
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Play atomic exchange failure preserves the existing canonical root as-is', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-play-exchange-failure-'));
  try {
    const probe = `
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_exchange", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.RELEASE_OUTPUT_ROOT = root / "builds/release"
module.PLAY_SCREENSHOT_OUTPUT = module.RELEASE_OUTPUT_ROOT / "play"
old = module.PLAY_SCREENSHOT_OUTPUT / "old.bin"
old.parent.mkdir(parents=True)
old.write_bytes(b"known-good")
staged = module.RELEASE_OUTPUT_ROOT / ".staging/play"
staged.mkdir(parents=True)
(staged / "new.bin").write_bytes(b"candidate")
def fail_exchange(first, second):
    if not first.is_dir() or not second.is_dir() \
            or (second / "old.bin").read_bytes() != b"known-good":
        raise RuntimeError("canonical root disappeared before exchange")
    raise OSError("injected exchange failure")
module._atomic_exchange_directories = fail_exchange
try:
    module._publish_play_screenshot_root(staged)
except OSError as error:
    if str(error) != "injected exchange failure":
        raise
else:
    raise RuntimeError("atomic exchange failure was accepted")
if old.read_bytes() != b"known-good" \
        or sorted(path.name for path in module.PLAY_SCREENSHOT_OUTPUT.iterdir()) \
            != ["old.bin"]:
    raise RuntimeError("failed atomic exchange changed canonical root")
if (staged / "new.bin").read_bytes() != b"candidate":
    raise RuntimeError("failed atomic exchange changed staging root")
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Play-only production contract excludes every shared IAP artwork', () => {
  const probe = `
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_play_assets", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
play = module._production_outputs(play_only=True)
full = module._production_outputs()
print(json.dumps({
    "play": sorted(path.relative_to(module.STORE_ROOT).as_posix() for path in play),
    "full_iap": sum("/iap/" in f"/{path.relative_to(module.STORE_ROOT).as_posix()}" for path in full),
}))
`;
  const result = spawnSync(
    process.execPath,
    [
      'scripts/python.mjs',
      '-B',
      '-c',
      probe,
      resolve('apps/game/tools/build_store_graphics.py'),
    ],
    { cwd: resolve('.'), encoding: 'utf8' },
  );
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.deepEqual(JSON.parse(result.stdout.trim().split('\n').at(-1)), {
    full_iap: 8,
    play: [
      'play/feature-graphic-1024x500.png',
      'play/icon-512.png',
    ],
  });
});

test('package scripts expose full, Play, and App Store screenshot contracts', () => {
  const packageJson = JSON.parse(readFileSync(resolve('package.json'), 'utf8'));
  assert.match(packageJson.scripts['store:screenshots'], /--screenshots$/u);
  assert.match(
    packageJson.scripts['check:store-screenshots'],
    /--check-screenshots$/u,
  );
  assert.match(
    packageJson.scripts['store:screenshots:play'],
    /--play-screenshots$/u,
  );
  assert.match(
    packageJson.scripts['check:store-screenshots:play'],
    /--check-play-screenshots$/u,
  );
  assert.match(
    packageJson.scripts['store:screenshots:app-store'],
    /--app-store-screenshots$/u,
  );
  assert.match(
    packageJson.scripts['store:screenshots:app-store:android-pixel-avd'],
    /--app-store-screenshots --app-store-iphone-source=android-pixel-avd$/u,
  );
  assert.match(
    packageJson.scripts['check:store-screenshots:app-store'],
    /--check-app-store-screenshots$/u,
  );
  assert.equal(
    packageJson.scripts.verify.includes('check:store-screenshots'),
    false,
    'ordinary verify must not require a full recapture for non-visual changes alone',
  );
});

test('App Store CLI requires an explicit create mode and checks read provenance mode', () => {
  const probe = `
import contextlib
import importlib.util
import io
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_cli", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module._production_outputs = lambda play_only=False: {}
module._screenshot_entries = lambda: []
calls = []
module._build_screenshots = lambda mode: calls.append(("full", mode)) or []
module._build_app_store_screenshots = (
    lambda mode: calls.append(("app-store", mode)) or [])
module._validate_generated_app_store_screenshots = (
    lambda _entries: calls.append(("check-app-store",)) or [])

def run(*args):
    sys.argv = ["build_store_graphics.py", *args]
    with contextlib.redirect_stdout(io.StringIO()):
        return module.main()

run("--screenshots")
run(
    "--app-store-screenshots",
    "--app-store-iphone-source=android-pixel-avd",
)
run("--check-app-store-screenshots")
expected = [
    ("full", module.APP_STORE_IPHONE_SOURCE_PHYSICAL),
    ("app-store", module.APP_STORE_IPHONE_SOURCE_ANDROID_AVD),
    ("check-app-store",),
]
if calls != expected:
    raise RuntimeError(f"wrong CLI dispatch: {calls}")

sys.argv = [
    "build_store_graphics.py",
    "--check-app-store-screenshots",
    "--app-store-iphone-source=android-pixel-avd",
]
with contextlib.redirect_stderr(io.StringIO()):
    try:
        module.main()
    except SystemExit as error:
        if error.code != 2:
            raise
    else:
        raise RuntimeError("check accepted a generation-only source override")
if calls != expected:
    raise RuntimeError("invalid CLI reached screenshot validation")
`;
  const result = spawnSync(
    process.execPath,
    [
      'scripts/python.mjs',
      '-B',
      '-c',
      probe,
      resolve('apps/game/tools/build_store_graphics.py'),
    ],
    { cwd: resolve('.'), encoding: 'utf8' },
  );
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test('App Store atomic exchange failure preserves the existing canonical tree', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-app-store-exchange-'));
  try {
    const probe = `
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_app_exchange", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.RELEASE_OUTPUT_ROOT = root / "builds/release"
module.APP_STORE_SCREENSHOT_OUTPUT = module.RELEASE_OUTPUT_ROOT / "app-store"
old = module.APP_STORE_SCREENSHOT_OUTPUT / "old.bin"
old.parent.mkdir(parents=True)
old.write_bytes(b"known-good")
staged = module.RELEASE_OUTPUT_ROOT / ".staging/app-store"
staged.mkdir(parents=True)
(staged / "new.bin").write_bytes(b"candidate")
def fail_exchange(first, second):
    if first != staged or second != module.APP_STORE_SCREENSHOT_OUTPUT:
        raise RuntimeError("wrong exchange roots")
    if (second / "old.bin").read_bytes() != b"known-good":
        raise RuntimeError("canonical disappeared before exchange")
    raise OSError("injected app-store exchange failure")
module._atomic_exchange_directories = fail_exchange
try:
    module._publish_app_store_screenshot_root(staged)
except OSError as error:
    if str(error) != "injected app-store exchange failure":
        raise
else:
    raise RuntimeError("App Store exchange failure was accepted")
if old.read_bytes() != b"known-good" \
        or (staged / "new.bin").read_bytes() != b"candidate":
    raise RuntimeError("failed exchange changed either generation")
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('screenshot, locale, and IAP SKU literal contracts reject swaps and meaningless copy', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-store-manifest-contract-'));
  try {
    const source = `
import copy
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
temporary_manifest = Path(sys.argv[3]) / "screenshots.json"
spec = importlib.util.spec_from_file_location("store_manifest_contract", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = json.loads(manifest_path.read_text(encoding="utf-8"))

def write_and_validate(manifest):
    temporary_manifest.write_text(
        json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    module.SCREENSHOT_MANIFEST = temporary_manifest
    module._screenshot_entries()
    module._iap_review_entries()

def reject(mutator, label):
    changed = copy.deepcopy(original)
    mutator(changed)
    try:
        write_and_validate(changed)
    except RuntimeError:
        return
    raise RuntimeError(f"manifest swap was accepted: {label}")

write_and_validate(original)

reject(
    lambda data: (
        data["screenshots"][0].__setitem__("output", data["screenshots"][1]["output"]),
        data["screenshots"][1].__setitem__("output", original["screenshots"][0]["output"]),
    ),
    "01/02 output-only swap",
)

def swap_scene_contract(data, first, second):
    for field in ("scene", "localized_sources", "crop_bottom", "labels"):
        data["screenshots"][first][field], data["screenshots"][second][field] = (
            data["screenshots"][second][field], data["screenshots"][first][field]
        )

reject(lambda data: swap_scene_contract(data, 0, 1), "01/02 whole semantic swap")
reject(lambda data: swap_scene_contract(data, 3, 4), "04/05 whole semantic swap")

def swap_sources(data):
    data["screenshots"][0]["localized_sources"], data["screenshots"][1]["localized_sources"] = (
        data["screenshots"][1]["localized_sources"],
        data["screenshots"][0]["localized_sources"],
    )

reject(swap_sources, "01/02 localized source swap")

def swap_labels(data):
    data["screenshots"][0]["labels"], data["screenshots"][1]["labels"] = (
        data["screenshots"][1]["labels"], data["screenshots"][0]["labels"]
    )

reject(swap_labels, "01/02 label map swap")

def swap_label_locales(data):
    labels = data["screenshots"][0]["labels"]
    labels["en-US"], labels["ko-KR"] = labels["ko-KR"], labels["en-US"]

reject(swap_label_locales, "en/ko label swap")
reject(
    lambda data: [entry.__setitem__(
        "labels", {locale: "TODO" for locale in module.SCREENSHOT_LOCALES}
    ) for entry in data["screenshots"]],
    "placeholder labels",
)

def swap_iap_outputs(data):
    first, second = data["iap_review"][0], data["iap_review"][1]
    first["output"], second["output"] = second["output"], first["output"]

reject(swap_iap_outputs, "IAP output swap")

canonical_game_locales = dict(module.GAME_LOCALES)
module.GAME_LOCALES = dict(canonical_game_locales)
module.GAME_LOCALES["en-US"], module.GAME_LOCALES["ko-KR"] = (
    module.GAME_LOCALES["ko-KR"], module.GAME_LOCALES["en-US"]
)
try:
    write_and_validate(original)
except RuntimeError:
    pass
else:
    raise RuntimeError("swapped GAME_LOCALES was accepted")
module.GAME_LOCALES = canonical_game_locales

for attribute, locale, wrong_value in (
    ("PLAY_LOCALES", "zh-Hans", "zh-TW"),
    ("APP_STORE_LOCALES", "ko-KR", "en-US"),
    ("MARKETING_TEXT_LANGUAGES", "ja-JP", "zh-cn"),
):
    canonical = dict(getattr(module, attribute))
    changed = dict(canonical)
    changed[locale] = wrong_value
    setattr(module, attribute, changed)
    try:
        write_and_validate(original)
    except RuntimeError:
        pass
    else:
        raise RuntimeError(f"wrong {attribute} literal was accepted")
    setattr(module, attribute, canonical)

canonical_screenshot_locales = module.SCREENSHOT_LOCALES
module.SCREENSHOT_LOCALES = tuple(reversed(canonical_screenshot_locales))
try:
    write_and_validate(original)
except RuntimeError:
    pass
else:
    raise RuntimeError("reordered SCREENSHOT_LOCALES was accepted")
module.SCREENSHOT_LOCALES = canonical_screenshot_locales

canonical_brands = dict(module.BRAND_LABELS)
module.BRAND_LABELS = dict(canonical_brands)
module.BRAND_LABELS["ja-JP"] = "月光烽火"
try:
    write_and_validate(original)
except RuntimeError:
    pass
else:
    raise RuntimeError("wrong Japanese brand literal was accepted")
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        source,
        resolve('apps/game/tools/build_store_graphics.py'),
        resolve('notes/release/store-assets/screenshots.json'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Python release gate validates every first-party state_guard field', () => {
  const source = `
import copy
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_state_guard", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

expected_android_inputs = {
    "apps/game/android/build/gradlew",
    "apps/game/android/build/gradle/wrapper/gradle-wrapper.jar",
    "apps/game/android/build/gradle/wrapper/gradle-wrapper.properties",
    "apps/game/android/build/libs/debug/godot-lib.template_debug.aar",
    "apps/game/android/build/res/values/themes.xml",
}
if set(module.ANDROID_DEBUG_CAPTURE_INPUTS) != expected_android_inputs:
    raise RuntimeError("Android debug capture fingerprint inputs are incomplete")
if module.STORE_CAPTURE_HERO_PORTRAIT_PATH != \
        "res://assets/custom/actors/heroes/keeper/idle.png":
    raise RuntimeError("keeper preview portrait contract is not independent")
if module.STORE_CAPTURE_HERO_BODY_PATH != \
        "res://assets/custom/actors/heroes/keeper/portrait.png":
    raise RuntimeError("keeper preview body contract is not independent")
expected_hero_copy = {
    "ko": {
        "name": "봉화지기",
        "description": (
            "하트 6칸 · 이속 -15% · 피해 +25% · 대시 쿨 +30% · "
            "달빛 파문·질긴 목숨"
        ),
        "states": {
            "SHRINE_SELECTED": "선택 중",
            "SHRINE_OWNED": "해금됨",
            "HERO_PREVIEW_IAP_LOCKED": "잠김 · 기기 스토어에서 구매",
        },
    },
    "en": {
        "name": "Beacon Keeper",
        "description": (
            "6 hearts · move -15% · dmg +25% · dash CD +30% · "
            "Moonlit Ripple/Tenacious Life"
        ),
        "states": {
            "SHRINE_SELECTED": "Selected",
            "SHRINE_OWNED": "Unlocked",
            "HERO_PREVIEW_IAP_LOCKED": "Locked · purchase in device store",
        },
    },
    "ja": {
        "name": "烽火の守り人",
        "description": (
            "ハート6 · 移速 -15% · ダメージ +25% · ダッシュCD +30% · "
            "月光の波紋・不屈の命"
        ),
        "states": {
            "SHRINE_SELECTED": "選択中",
            "SHRINE_OWNED": "解放済み",
            "HERO_PREVIEW_IAP_LOCKED": "未購入 · 端末ストアで購入",
        },
    },
    "zh_CN": {
        "name": "烽火守护者",
        "description": (
            "6颗心 · 移速 -15% · 伤害 +25% · 冲刺冷却 +30% · "
            "月光波纹·坚韧生命"
        ),
        "states": {
            "SHRINE_SELECTED": "已选择",
            "SHRINE_OWNED": "已解锁",
            "HERO_PREVIEW_IAP_LOCKED": "未购买 · 在设备商店购买",
        },
    },
    "zh_TW": {
        "name": "烽火守護者",
        "description": (
            "6顆心 · 移速 -15% · 傷害 +25% · 衝刺冷卻 +30% · "
            "月光波紋·堅韌生命"
        ),
        "states": {
            "SHRINE_SELECTED": "已選擇",
            "SHRINE_OWNED": "已解鎖",
            "HERO_PREVIEW_IAP_LOCKED": "未購買 · 在裝置商店購買",
        },
    },
}
if module.STORE_CAPTURE_HERO_COPY != expected_hero_copy:
    raise RuntimeError("keeper preview localized copy contract is incomplete")
if module.STORE_CAPTURE_HERO_NAME_SOURCE_KEY != "HERO_KEEPER_NAME" \
        or module.STORE_CAPTURE_HERO_DESCRIPTION_SOURCE_KEY \
        != "HERO_KEEPER_DESC":
    raise RuntimeError("keeper preview source-key contract is not independent")
if module.STORE_CAPTURE_HERO_STATE_SOURCE_KEYS != (
        "SHRINE_SELECTED", "SHRINE_OWNED", "HERO_PREVIEW_IAP_LOCKED"):
    raise RuntimeError("keeper preview state-key contract is incomplete")
expected_field_guardian_textures = (
    "res://assets/custom/actors/guardians/field.png",
    "res://assets/custom/actors/guardians/field_windup_cross.png",
    "res://assets/custom/actors/guardians/field_windup_radial.png",
    "res://assets/custom/actors/guardians/field_recover.png",
    "res://assets/custom/actors/guardians/field_storm.png",
    "res://assets/custom/actors/guardians/field_storm_windup_cross.png",
    "res://assets/custom/actors/guardians/field_storm_windup_radial.png",
    "res://assets/custom/actors/guardians/field_storm_recover.png",
)
if module.STORE_CAPTURE_FIELD_GUARDIAN_TEXTURE_PATHS != \
        expected_field_guardian_textures:
    raise RuntimeError("field guardian frame texture contract is incomplete")
if module.STORE_CAPTURE_FIELD_GUARDIAN_PATHS != (
    "res://resources/guardian_field.tres",
    "res://resources/guardian_field_storm.tres",
):
    raise RuntimeError("field guardian resource contract is not independent")

expected_kinds = {
    "01-moonlight-barrage.png": "moonlight_barrage",
    "02-field-guardian.png": "field_guardian",
    "04-title.png": "title",
    "05-moonlit-shrine.png": "shrine",
    "06-hero-preview.png": "hero_preview",
    "builds/shots/store-localized/ko-KR/iap-review/hero-keeper.png": "iap_review",
}
for capture_path, expected_kind in expected_kinds.items():
    actual_kind = module._store_capture_state_kind(capture_path)
    if actual_kind != expected_kind:
        raise RuntimeError(f"wrong state kind mapping: {capture_path}={actual_kind}")

core_source = "builds/shots/store-localized/en-US/03-missile-core-drop.png"
core_guard = {
    "schema": 1,
    "kind": "missile_core_recovery",
    "scene": "arena",
    "over": False,
    "asset_locale": "en-US",
    "game_locale": "en",
    "level": 10,
    "cycle": 1,
    "zone_index": 0,
    "terrain_path": "res://resources/rooms/forest.tres",
    "world_key": "WORLD_FOREST",
    "lit_beacons": 0,
    "transitioning": False,
    "escape_active": False,
    "time_key": "TIME_NIGHT",
    "time_tone": module.STORE_CAPTURE_NIGHT_TONE,
    "applied_time_tone": module.STORE_CAPTURE_NIGHT_TONE,
    "time_tone_applied": True,
    "banner_key": "MISSILE_DROPPED",
    "expected_banner_text": "Missile output 8->7",
    "actual_banner_text": "Missile output 8->7",
    "banner_visible": True,
    "banner_locked": True,
    "missile_power_before": 8,
    "missile_power_after": 7,
    "ejected_cores_outstanding": 1,
    "core_capture_paused": True,
    "ejected_core_count": 1,
    "core_visible_in_tree": True,
    "core_effective_alpha": 1.0,
    "core_opaque": True,
    "core_onscreen": True,
    "core_texture_path": "res://assets/custom/items/pickups/power_gem.png",
    "core_texture_matches": True,
    "core_visible_draw_rect_positive": True,
}
module._validate_missile_core_capture_guard(
    {"capture_guard": core_guard}, core_source, "en-US", "en")
unpaused_core_guard = copy.deepcopy(core_guard)
unpaused_core_guard["core_capture_paused"] = False
try:
    module._validate_missile_core_capture_guard(
        {"capture_guard": unpaused_core_guard}, core_source, "en-US", "en")
except RuntimeError:
    pass
else:
    raise RuntimeError("unpaused missile core guard was accepted")
wrong_core_scene = copy.deepcopy(core_guard)
wrong_core_scene["terrain_path"] = module.STORE_CAPTURE_CAMP_TERRAIN_PATH
try:
    module._validate_missile_core_capture_guard(
        {"capture_guard": wrong_core_scene}, core_source, "en-US", "en")
except RuntimeError:
    pass
else:
    raise RuntimeError("wrong-terrain missile core guard was accepted")
for field, value in (
    ("ejected_core_count", 2),
    ("core_visible_in_tree", False),
    ("core_effective_alpha", 0.0),
    ("core_effective_alpha", float("inf")),
    ("core_opaque", False),
    ("core_onscreen", False),
    ("core_texture_path", "res://icon.svg"),
    ("core_texture_matches", False),
    ("core_visible_draw_rect_positive", False),
):
    invalid_core = copy.deepcopy(core_guard)
    invalid_core[field] = value
    try:
        module._validate_missile_core_capture_guard(
            {"capture_guard": invalid_core}, core_source, "en-US", "en")
    except RuntimeError:
        continue
    raise RuntimeError(f"invalid visible core was accepted: {field}")

def common(kind, locale="ko"):
    return {
        "schema": 1,
        "nonce": "a" * 64,
        "observation": 17,
        "observation_after": 18,
        "kind": kind,
        "game_locale": locale,
    }

VIEWPORT_RECT = [0.0, 0.0, 808.0, 360.0]
SAFE_RECT = [28.0, 28.0, 752.0, 304.0]

def safe_layout(controls, ready_fields=("safe_ui_ready",),
                viewport_field="viewport_rect"):
    layout = {
        viewport_field: copy.deepcopy(VIEWPORT_RECT),
        "safe_rect": copy.deepcopy(SAFE_RECT),
        "safe_area_inside_viewport": True,
    }
    for field in ready_fields:
        layout[field] = True
    for index, control in enumerate(controls):
        layout[f"{control}_rect"] = [
            40.0 + index * 2.0,
            40.0 + index * 2.0,
            100.0,
            30.0,
        ]
        layout[f"{control}_inside_safe_area"] = True
    return layout

title_safe = safe_layout(module.STORE_CAPTURE_TITLE_DIRECT_SAFE_CONTROLS)
arena_safe = safe_layout(module.STORE_CAPTURE_ARENA_SAFE_CONTROLS)
shrine_safe = safe_layout(
    ("shrine_frame",), ("shrine_safe_ui_ready",))
preview_safe = safe_layout(
    ("shrine_frame", "preview_frame", "close"),
    ("shrine_safe_ui_ready", "preview_safe_ui_ready"))
iap_safe = safe_layout(
    ("shop_frame", "card"), ("iap_safe_ui_ready",), "screen_rect")

title = common("title") | title_safe | {
    "scene": "title",
    "ready": True,
    "screen_visible": True,
    "title_visible": True,
    "subtitle_visible": True,
    "title_source_key": "TITLE_NAME",
    "subtitle_source_key": "TITLE_SUBTITLE",
    "title_auto_translate": True,
    "subtitle_auto_translate": True,
    "title_translation_text": "달빛 봉화",
    "subtitle_translation_text": "밤을 밝히는 마지막 불빛",
    "title_text_nonempty": True,
    "title_characters_visible": True,
    "title_font_size_positive": True,
    "title_font_alpha_readable": True,
    "title_rendered_text_ready": True,
    "subtitle_text_nonempty": True,
    "subtitle_characters_visible": True,
    "subtitle_font_size_positive": True,
    "subtitle_font_alpha_readable": True,
    "subtitle_rendered_text_ready": True,
    "title_inside_viewport": True,
    "subtitle_inside_viewport": True,
    "title_opaque": True,
    "subtitle_opaque": True,
    "version_visible": True,
    "version_text": "v1.0.1",
    "version_text_nonempty": True,
    "version_characters_visible": True,
    "version_font_size_positive": True,
    "version_font_alpha_readable": True,
    "version_rendered_text_ready": True,
    "version_inside_viewport": True,
    "version_opaque": True,
    "tap_prompt_visible": True,
    "tap_prompt_source_key": "TAP_TO_START",
    "tap_prompt_auto_translate": True,
    "tap_prompt_translation_text": "화면을 탭하여 시작",
    "tap_prompt_text_nonempty": True,
    "tap_prompt_characters_visible": True,
    "tap_prompt_font_size_positive": True,
    "tap_prompt_font_alpha_readable": True,
    "tap_prompt_rendered_text_ready": True,
    "tap_prompt_inside_viewport": True,
    "tap_prompt_readable_alpha": True,
    "tap_prompt_effective_alpha": 1.0,
    "tap_prompt_full_alpha": True,
    "tap_prompt_blink_stopped": True,
    "tap_prompt_modulate_white": True,
    "tap_prompt_capture_locked": True,
    "settings_button_visible": True,
    "settings_button_enabled": True,
    "settings_button_source_key": "SETTINGS_TITLE",
    "settings_button_auto_translate": True,
    "settings_button_translation_text": "설정",
    "settings_button_inside_viewport": True,
    "settings_button_copy_valid": True,
    "settings_button_text_nonempty": True,
    "settings_button_font_size_positive": True,
    "settings_button_font_alpha_readable": True,
    "settings_button_rendered_text_ready": True,
    "settings_button_opaque": True,
    "shrine_button_visible": True,
    "shrine_button_enabled": True,
    "shrine_button_source_key": "SHRINE_OPEN",
    "shrine_button_auto_translate": True,
    "shrine_button_translation_text": "제단",
    "shrine_button_inside_viewport": True,
    "shrine_button_copy_valid": True,
    "shrine_button_text_nonempty": True,
    "shrine_button_font_size_positive": True,
    "shrine_button_font_alpha_readable": True,
    "shrine_button_rendered_text_ready": True,
    "shrine_button_opaque": True,
    "ladder_button_visible": True,
    "ladder_button_enabled": True,
    "ladder_button_source_key": "LADDER_OPEN",
    "ladder_button_auto_translate": True,
    "ladder_button_translation_text": "순위",
    "ladder_button_inside_viewport": True,
    "ladder_button_copy_valid": True,
    "ladder_button_text_nonempty": True,
    "ladder_button_font_size_positive": True,
    "ladder_button_font_alpha_readable": True,
    "ladder_button_rendered_text_ready": True,
    "ladder_button_opaque": True,
    "direct_distribution": True,
    "storefront_enabled": False,
    "storefront_feature_matches": True,
    "store_button_visible": False,
    "store_button_enabled": False,
    "store_button_visibility_matches_storefront": True,
    "store_button_enabled_matches_storefront": True,
    "store_button_source_key": "IAP_OPEN",
    "store_button_auto_translate": True,
    "store_button_translation_text": "상점",
    "store_button_inside_viewport": True,
    "store_button_copy_valid": True,
    "store_button_text_nonempty": True,
    "store_button_font_size_positive": True,
    "store_button_font_alpha_readable": True,
    "store_button_rendered_text_ready": False,
    "store_button_opaque": False,
    "night_forest_node_present": True,
    "night_forest_scene_path": "res://scenes/gameplay/night_forest.tscn",
    "night_forest_expected_scene_path": "res://scenes/gameplay/night_forest.tscn",
    "night_forest_scene_matches": True,
    "night_forest_visible_in_tree": True,
    "night_forest_effective_alpha": 1.0,
    "night_forest_opaque": True,
    "night_forest_ground_resource_path": (
        "res://assets/custom/world/terrain/forest_floor.png"
    ),
    "night_forest_expected_ground_resource_path": (
        "res://assets/custom/world/terrain/forest_floor.png"
    ),
    "night_forest_ground_resource_matches": True,
    "night_forest_drawable_visible_in_tree": True,
    "night_forest_drawable_effective_alpha": 1.0,
    "night_forest_drawable_opaque": True,
    "night_forest_draw_rect_positive": True,
    "night_forest_draw_rect_intersects_viewport": True,
    "night_forest_visual_ready": True,
    "vignette_node_present": True,
    "vignette_node_class": "Sprite2D",
    "vignette_texture_class": "GradientTexture2D",
    "vignette_expected_texture_class": "GradientTexture2D",
    "vignette_texture_unique_id": "GradientTexture2D_vignette",
    "vignette_expected_texture_unique_id": "GradientTexture2D_vignette",
    "vignette_texture_dimensions_match": True,
    "vignette_texture_matches": True,
    "vignette_visible_in_tree": True,
    "vignette_effective_alpha": 1.0,
    "vignette_opaque": True,
    "vignette_draw_rect_positive": True,
    "vignette_draw_rect_intersects_viewport": True,
    "vignette_visual_ready": True,
    "beacon_node_present": True,
    "beacon_scene_path": "res://scenes/objectives/beacon.tscn",
    "beacon_expected_scene_path": "res://scenes/objectives/beacon.tscn",
    "beacon_scene_matches": True,
    "beacon_visible_in_tree": True,
    "beacon_effective_alpha": 1.0,
    "beacon_opaque": True,
    "beacon_clearing_resource_path": (
        "res://assets/custom/world/beacon/clearing.png"
    ),
    "beacon_expected_clearing_resource_path": (
        "res://assets/custom/world/beacon/clearing.png"
    ),
    "beacon_clearing_resource_matches": True,
    "beacon_drawable_visible_in_tree": True,
    "beacon_drawable_effective_alpha": 1.0,
    "beacon_drawable_opaque": True,
    "beacon_draw_rect_positive": True,
    "beacon_draw_rect_intersects_viewport": True,
    "beacon_visual_ready": True,
    "panels_closed": True,
    "accepting_input": True,
    "screen_inside_viewport": True,
    "drawn_after_ready": True,
}
arena = common("arena_ready") | arena_safe | {
    "scene": "arena", "ready": True, "over": False,
}
barrage = common("moonlight_barrage") | arena_safe | {
    "scene": "arena",
    "ready": True,
    "over": False,
    "level": 20,
    "cycle": 3,
    "zone_index": 0,
    "terrain_path": module.STORE_CAPTURE_CAMP_TERRAIN_PATH,
    "world_key": "WORLD_CAMP",
    "lit_beacons": 0,
    "transitioning": False,
    "escape_active": False,
    "time_key": "TIME_NIGHT",
    "time_tone": module.STORE_CAPTURE_NIGHT_TONE,
    "applied_time_tone": module.STORE_CAPTURE_NIGHT_TONE,
    "time_tone_applied": True,
    "missile_power": 8,
    "missile_max": 8,
    "missile_volley": 8,
    "homing_active": True,
    "missile_visual_probe_count": 1,
    "missile_visible_in_tree": True,
    "missile_effective_alpha": 1.0,
    "missile_opaque": True,
    "missile_draw_after_launch": True,
    "missile_head_geometry_ready": True,
    "missile_trail_geometry_ready": True,
    "visible_enemy_sprite_count": 3,
    "enemy_formation_visible": True,
    "max_volley_live": True,
    "barrage_visible": True,
}
shrine = common("shrine") | shrine_safe | {
    "shrine_visible": True,
    "preview_visible": False,
    "hero_card_count": 6,
    "hero_cards_visible_rect_count": 6,
    "shrine_opaque": True,
    "shrine_frame_inside_viewport": True,
    "shrine_drawn_after_open": True,
}
preview = common("hero_preview") | preview_safe | {
    "shrine_visible": True,
    "shrine_opaque": True,
    "shrine_frame_inside_viewport": True,
    "shrine_drawn_after_open": True,
    "preview_visible": True,
    "hero_path": module.STORE_CAPTURE_HERO_PATH,
    "portrait_visible": True,
    "portrait_texture_ready": True,
    "portrait_resource_path": module.STORE_CAPTURE_HERO_PORTRAIT_PATH,
    "portrait_expected_resource_path": module.STORE_CAPTURE_HERO_PORTRAIT_PATH,
    "portrait_resource_matches": True,
    "portrait_visible_rect_ready": True,
    "portrait_opaque": True,
    "body_visible": True,
    "body_texture_ready": True,
    "body_resource_path": module.STORE_CAPTURE_HERO_BODY_PATH,
    "body_expected_resource_path": module.STORE_CAPTURE_HERO_BODY_PATH,
    "body_resource_matches": True,
    "body_visible_rect_ready": True,
    "body_opaque": True,
    "copy_locale": "ko",
    "name_source_key": "HERO_KEEPER_NAME",
    "name_expected_source_key": "HERO_KEEPER_NAME",
    "name_source_matches": True,
    "name_text": expected_hero_copy["ko"]["name"],
    "name_expected_text": expected_hero_copy["ko"]["name"],
    "name_copy_valid": True,
    "name_text_nonempty": True,
    "name_characters_visible": True,
    "name_font_size_positive": True,
    "name_font_alpha_readable": True,
    "name_visible_rect_ready": True,
    "name_opaque": True,
    "name_rendered_text_ready": True,
    "state_source_key": "HERO_PREVIEW_IAP_LOCKED",
    "state_expected_source_key": "HERO_PREVIEW_IAP_LOCKED",
    "state_source_matches": True,
    "state_text": expected_hero_copy["ko"]["states"][
        "HERO_PREVIEW_IAP_LOCKED"
    ],
    "state_expected_text": expected_hero_copy["ko"]["states"][
        "HERO_PREVIEW_IAP_LOCKED"
    ],
    "state_copy_valid": True,
    "state_text_nonempty": True,
    "state_characters_visible": True,
    "state_font_size_positive": True,
    "state_font_alpha_readable": True,
    "state_visible_rect_ready": True,
    "state_opaque": True,
    "state_rendered_text_ready": True,
    "description_source_key": "HERO_KEEPER_DESC",
    "description_expected_source_key": "HERO_KEEPER_DESC",
    "description_source_matches": True,
    "description_text": expected_hero_copy["ko"]["description"],
    "description_expected_text": expected_hero_copy["ko"]["description"],
    "description_copy_valid": True,
    "description_text_nonempty": True,
    "description_characters_visible": True,
    "description_font_size_positive": True,
    "description_font_alpha_readable": True,
    "description_visible_rect_ready": True,
    "description_opaque": True,
    "description_rendered_text_ready": True,
    "close_visible": True,
    "close_inside_viewport": True,
    "close_opaque": True,
    "preview_opaque": True,
    "preview_frame_inside_viewport": True,
    "preview_drawn_after_open": True,
}
guardian = common("field_guardian") | arena_safe | {
    "scene": "arena",
    "ready": True,
    "over": False,
    "level": 20,
    "cycle": 3,
    "zone_index": 2,
    "terrain_path": module.STORE_CAPTURE_FIELD_TERRAIN_PATH,
    "terrain_encounter": 1,
    "world_key": "WORLD_FIELD",
    "time_key": "TIME_DAY",
    "time_tone": [1.54999995231628, 1.37999999523163, 1.12000000476837, 1],
    "applied_time_tone": [
        1.54999995231628, 1.37999999523163, 1.12000000476837, 1
    ],
    "time_tone_applied": True,
    "lit_beacons": 3,
    "total_beacons": 3,
    "transitioning": False,
    "escape_active": False,
    "guardian_alive": True,
    "guardian_visible": True,
    "guardian_on_screen": True,
    "hud_boss_visible": True,
    "guardian_name": "푸른 들판의 날개",
    "guardian_kind_path": "res://resources/guardian_field.tres",
    "guardian_visual_node_present": True,
    "guardian_visual_node_class": "AnimatedSprite2D",
    "guardian_root_visible_in_tree": True,
    "guardian_sprite_visible_in_tree": True,
    "guardian_root_effective_alpha": 1.0,
    "guardian_sprite_effective_alpha": 1.0,
    "guardian_root_opaque": True,
    "guardian_sprite_opaque": True,
    "guardian_current_animation": "idle",
    "guardian_current_frame": 0,
    "guardian_frame_texture_present": True,
    "guardian_frame_texture_path": module.STORE_CAPTURE_FIELD_GUARDIAN_TEXTURE_PATHS[0],
    "guardian_frame_texture_matches_field": True,
    "guardian_draw_rect_positive": True,
    "guardian_draw_rect_intersects_viewport": True,
    "guardian_capture_active": True,
    "friendly_projectile_count": 0,
    "guardian_draw_rect": [470.0, 164.0, 60.0, 60.0],
    "guardian_focus_rect": [177.76, 86.4, 452.48, 230.4],
    "guardian_draw_rect_fully_inside_viewport": True,
    "guardian_draw_rect_inside_focus": True,
    "guardian_draw_center_inside_focus": True,
    "guardian_player_canvas_distance": 100.0,
    "guardian_separated_from_player": True,
    "guardian_central_composition": True,
    "guardian_visual_ready": True,
}
hero_product = "com.crossplatformkorea.moonlitbeacon.hero_keeper"
hero_iap = common("iap_review") | iap_safe | {
    "shop_visible": True,
    "shop_opaque": True,
    "shop_drawn_after_open": True,
    "shop_frame_inside_viewport": True,
    "preview_visible": False,
    "product_id": hero_product,
    "card_visible": True,
    "card_visible_rect_ready": True,
    "card_opaque": True,
    "title_visible": True,
    "title_text": "봉화지기",
    "title_expected_text": "봉화지기",
    "title_text_nonempty": True,
    "title_copy_valid": True,
    "title_characters_visible": True,
    "title_font_size_positive": True,
    "title_font_alpha_readable": True,
    "title_rendered_text_ready": True,
    "title_visible_rect_ready": True,
    "title_opaque": True,
    "review_fallback_verified": True,
    "review_status_visible": True,
    "review_status_text": module.IAP_REVIEW_FALLBACK_STATUS_TEXT,
    "review_status_expected_text": module.IAP_REVIEW_FALLBACK_STATUS_TEXT,
    "review_status_copy_valid": True,
    "review_status_rendered_text_ready": True,
    "review_status_visible_rect_ready": True,
    "review_status_opaque": True,
    "price_visible": True,
    "price_text": module.IAP_REVIEW_FALLBACK_PRICE_TEXT,
    "price_expected_text": module.IAP_REVIEW_FALLBACK_PRICE_TEXT,
    "price_copy_valid": True,
    "price_rendered_text_ready": True,
    "price_visible_rect_ready": True,
    "price_opaque": True,
    "portrait_visible": True,
    "portrait_visible_rect_ready": True,
    "portrait_opaque": True,
    "hero_resource_path": module.STORE_CAPTURE_IAP_HERO_VISUALS[hero_product][0],
    "hero_expected_resource_path": module.STORE_CAPTURE_IAP_HERO_VISUALS[hero_product][0],
    "portrait_resource_path": module.STORE_CAPTURE_IAP_HERO_VISUALS[hero_product][1],
    "portrait_expected_resource_path": module.STORE_CAPTURE_IAP_HERO_VISUALS[hero_product][1],
    "portrait_product_specific": True,
    "action_visible": True,
    "action_enabled": False,
    "action_text": "구매",
    "action_expected_text": "구매",
    "action_text_nonempty": True,
    "action_copy_valid": True,
    "action_font_size_positive": True,
    "action_font_alpha_readable": True,
    "action_rendered_text_ready": True,
    "action_visible_rect_ready": True,
    "action_opaque": True,
    "restore_visible": True,
    "restore_enabled": False,
    "restore_text": "구매 복원",
    "restore_expected_text": "구매 복원",
    "restore_text_nonempty": True,
    "restore_copy_valid": True,
    "restore_font_size_positive": True,
    "restore_font_alpha_readable": True,
    "restore_rendered_text_ready": True,
    "restore_visible_rect_ready": True,
    "restore_opaque": True,
    "card_fully_inside_viewport": True,
    "card_inside_screen": True,
}
supporter_product = "com.crossplatformkorea.moonlitbeacon.supporter"
supporter_iap = common("iap_review") | iap_safe | {
    "shop_visible": True,
    "shop_opaque": True,
    "shop_drawn_after_open": True,
    "shop_frame_inside_viewport": True,
    "preview_visible": False,
    "product_id": supporter_product,
    "card_visible": True,
    "card_visible_rect_ready": True,
    "card_opaque": True,
    "title_visible": True,
    "title_text": "달빛 후원자",
    "title_expected_text": "달빛 후원자",
    "title_text_nonempty": True,
    "title_copy_valid": True,
    "title_characters_visible": True,
    "title_font_size_positive": True,
    "title_font_alpha_readable": True,
    "title_rendered_text_ready": True,
    "title_visible_rect_ready": True,
    "title_opaque": True,
    "review_fallback_verified": True,
    "review_status_visible": True,
    "review_status_text": module.IAP_REVIEW_FALLBACK_STATUS_TEXT,
    "review_status_expected_text": module.IAP_REVIEW_FALLBACK_STATUS_TEXT,
    "review_status_copy_valid": True,
    "review_status_rendered_text_ready": True,
    "review_status_visible_rect_ready": True,
    "review_status_opaque": True,
    "price_visible": True,
    "price_text": module.IAP_REVIEW_FALLBACK_PRICE_TEXT,
    "price_expected_text": module.IAP_REVIEW_FALLBACK_PRICE_TEXT,
    "price_copy_valid": True,
    "price_rendered_text_ready": True,
    "price_visible_rect_ready": True,
    "price_opaque": True,
    "artwork_visible": True,
    "artwork_kind": "supporter_app_icon",
    "artwork_item_count": 1,
    "artwork_node_present": True,
    "artwork_expected_kind": "supporter_app_icon",
    "artwork_expected_item_count": 1,
    "artwork_textures_ready": True,
    "artwork_visible_rect_ready": True,
    "artwork_opaque": True,
    "artwork_product_specific": True,
    "action_visible": True,
    "action_enabled": False,
    "action_text": "구매",
    "action_expected_text": "구매",
    "action_text_nonempty": True,
    "action_copy_valid": True,
    "action_font_size_positive": True,
    "action_font_alpha_readable": True,
    "action_rendered_text_ready": True,
    "action_visible_rect_ready": True,
    "action_opaque": True,
    "restore_visible": True,
    "restore_enabled": False,
    "restore_text": "구매 복원",
    "restore_expected_text": "구매 복원",
    "restore_text_nonempty": True,
    "restore_copy_valid": True,
    "restore_font_size_positive": True,
    "restore_font_alpha_readable": True,
    "restore_rendered_text_ready": True,
    "restore_visible_rect_ready": True,
    "restore_opaque": True,
    "card_fully_inside_viewport": True,
    "card_inside_screen": True,
}
lantern_product = "com.crossplatformkorea.moonlitbeacon.lantern_colors"
lantern_iap = copy.deepcopy(supporter_iap) | {
    "product_id": lantern_product,
    "title_text": "봉화 색상 꾸러미",
    "title_expected_text": "봉화 색상 꾸러미",
    "price_text": module.IAP_REVIEW_FALLBACK_PRICE_TEXT,
    "price_expected_text": module.IAP_REVIEW_FALLBACK_PRICE_TEXT,
    "artwork_kind": "lantern_palette_flames",
    "artwork_item_count": 4,
    "artwork_expected_kind": "lantern_palette_flames",
    "artwork_expected_item_count": 4,
}

valid = [
    (title, "title", None),
    (arena, "arena_ready", None),
    (barrage, "moonlight_barrage", None),
    (shrine, "shrine", None),
    (preview, "hero_preview", None),
    (guardian, "field_guardian", None),
    (hero_iap, "iap_review", hero_product),
    (supporter_iap, "iap_review", supporter_product),
    (lantern_iap, "iap_review", lantern_product),
]
for index, (guard, kind, product_id) in enumerate(valid):
    module._validate_store_capture_state_guard(
        {"state_guard": guard}, f"valid-{index}.png", "ko", kind, product_id)

storefront_title = copy.deepcopy(title)
storefront_title.update(safe_layout(module.STORE_CAPTURE_TITLE_SAFE_CONTROLS))
storefront_title.update({
    "direct_distribution": False,
    "storefront_enabled": True,
    "store_button_visible": True,
    "store_button_enabled": True,
    "store_button_rendered_text_ready": True,
    "store_button_opaque": True,
})
module._validate_store_capture_state_guard(
    {"state_guard": storefront_title}, "valid-storefront.png", "ko", "title",
    None, False)

for locale, copy_contract in expected_hero_copy.items():
    for state_source_key, state_text in copy_contract["states"].items():
        localized_preview = copy.deepcopy(preview)
        localized_preview.update({
            "game_locale": locale,
            "copy_locale": locale,
            "name_text": copy_contract["name"],
            "name_expected_text": copy_contract["name"],
            "state_source_key": state_source_key,
            "state_expected_source_key": state_source_key,
            "state_text": state_text,
            "state_expected_text": state_text,
            "description_text": copy_contract["description"],
            "description_expected_text": copy_contract["description"],
        })
        module._validate_store_capture_state_guard(
            {"state_guard": localized_preview},
            f"valid-{locale}-{state_source_key}.png",
            locale,
            "hero_preview",
            None,
        )

invalid = [
    (title, "title", None, "version_text", "1.0.1"),
    (title, "title", None, "title_source_key", "달빛 봉화"),
    (title, "title", None, "title_translation_text", "TITLE_NAME"),
    (title, "title", None, "tap_prompt_readable_alpha", False),
    (title, "title", None, "tap_prompt_effective_alpha", 0.999),
    (title, "title", None, "tap_prompt_effective_alpha", float("nan")),
    (title, "title", None, "tap_prompt_full_alpha", False),
    (title, "title", None, "tap_prompt_blink_stopped", False),
    (title, "title", None, "tap_prompt_modulate_white", False),
    (title, "title", None, "tap_prompt_capture_locked", False),
    (title, "title", None, "settings_button_inside_viewport", False),
    (title, "title", None, "ladder_button_opaque", False),
    (title, "title", None, "direct_distribution", False),
    (title, "title", None, "storefront_enabled", True),
    (title, "title", None, "storefront_feature_matches", False),
    (title, "title", None, "store_button_visible", True),
    (title, "title", None, "store_button_enabled", True),
    (title, "title", None, "store_button_visibility_matches_storefront", False),
    (title, "title", None, "store_button_enabled_matches_storefront", False),
    (title, "title", None, "store_button_source_key", "STORE"),
    (title, "title", None, "store_button_translation_text", "Store"),
    (title, "title", None, "store_button_rendered_text_ready", True),
    (title, "title", None, "store_button_opaque", True),
    (title, "title", None, "night_forest_scene_path",
     "res://scenes/gameplay/arena.tscn"),
    (title, "title", None, "night_forest_expected_scene_path",
     "res://scenes/gameplay/arena.tscn"),
    (title, "title", None, "night_forest_ground_resource_path",
     "res://assets/custom/world/beacon/clearing.png"),
    (title, "title", None, "night_forest_expected_ground_resource_path",
     "res://assets/custom/world/beacon/clearing.png"),
    (title, "title", None, "vignette_node_class", "Node2D"),
    (title, "title", None, "vignette_texture_class", "CompressedTexture2D"),
    (title, "title", None, "vignette_expected_texture_class",
     "CompressedTexture2D"),
    (title, "title", None, "vignette_texture_unique_id", "wrong_vignette"),
    (title, "title", None, "vignette_expected_texture_unique_id",
     "wrong_vignette"),
    (title, "title", None, "beacon_scene_path",
     "res://scenes/gameplay/night_forest.tscn"),
    (title, "title", None, "beacon_expected_scene_path",
     "res://scenes/gameplay/night_forest.tscn"),
    (title, "title", None, "beacon_clearing_resource_path",
     "res://assets/custom/world/terrain/forest_floor.png"),
    (title, "title", None, "beacon_expected_clearing_resource_path",
     "res://assets/custom/world/terrain/forest_floor.png"),
    (title, "title", None, "night_forest_effective_alpha", 0.98),
    (title, "title", None, "night_forest_effective_alpha", float("inf")),
    (title, "title", None, "night_forest_drawable_effective_alpha", 0.0),
    (title, "title", None, "night_forest_drawable_effective_alpha",
     float("inf")),
    (title, "title", None, "vignette_effective_alpha", 0.0),
    (title, "title", None, "vignette_effective_alpha", float("inf")),
    (title, "title", None, "beacon_effective_alpha", 0.0),
    (title, "title", None, "beacon_effective_alpha", float("inf")),
    (title, "title", None, "beacon_drawable_effective_alpha", 0.0),
    (title, "title", None, "beacon_drawable_effective_alpha", float("inf")),
    (arena, "arena_ready", None, "observation", 0),
    (arena, "arena_ready", None, "observation_after", 17),
    (arena, "arena_ready", None, "over", True),
    (barrage, "moonlight_barrage", None, "missile_volley", 7),
    (barrage, "moonlight_barrage", None, "time_key", "TIME_DAY"),
    (barrage, "moonlight_barrage", None, "missile_visual_probe_count", 0),
    (barrage, "moonlight_barrage", None, "visible_enemy_sprite_count", 2),
    (barrage, "moonlight_barrage", None, "visible_enemy_sprite_count", 3.5),
    (barrage, "moonlight_barrage", None, "missile_effective_alpha", 0.0),
    (barrage, "moonlight_barrage", None, "missile_effective_alpha", float("inf")),
    (barrage, "moonlight_barrage", None, "missile_draw_after_launch", False),
    (barrage, "moonlight_barrage", None, "missile_head_geometry_ready", False),
    (shrine, "shrine", None, "shrine_opaque", False),
    (shrine, "shrine", None, "hero_cards_visible_rect_count", 5),
    (preview, "hero_preview", None, "body_visible", False),
    (preview, "hero_preview", None, "portrait_visible_rect_ready", False),
    (preview, "hero_preview", None, "body_opaque", False),
    (preview, "hero_preview", None, "portrait_resource_path",
     "res://assets/custom/actors/heroes/dancer/portrait.png"),
    (preview, "hero_preview", None, "portrait_expected_resource_path",
     "res://assets/custom/actors/heroes/dancer/portrait.png"),
    (preview, "hero_preview", None, "portrait_resource_matches", False),
    (preview, "hero_preview", None, "body_resource_path",
     "res://assets/custom/actors/heroes/dancer/idle.png"),
    (preview, "hero_preview", None, "body_expected_resource_path",
     "res://assets/custom/actors/heroes/dancer/idle.png"),
    (preview, "hero_preview", None, "body_resource_matches", False),
    (preview, "hero_preview", None, "copy_locale", "en"),
    (preview, "hero_preview", None, "name_source_key", "HERO_KEEPER_DESC"),
    (preview, "hero_preview", None, "name_expected_source_key",
     "HERO_KEEPER_DESC"),
    (preview, "hero_preview", None, "name_text", ""),
    (preview, "hero_preview", None, "name_expected_text", ""),
    (preview, "hero_preview", None, "state_source_key", "HERO_KEEPER_NAME"),
    (preview, "hero_preview", None, "state_expected_source_key",
     "SHRINE_OWNED"),
    (preview, "hero_preview", None, "state_text", ""),
    (preview, "hero_preview", None, "state_expected_text", ""),
    (preview, "hero_preview", None, "description_source_key",
     "HERO_KEEPER_NAME"),
    (preview, "hero_preview", None, "description_expected_source_key",
     "HERO_KEEPER_NAME"),
    (preview, "hero_preview", None, "description_text", ""),
    (preview, "hero_preview", None, "description_expected_text", ""),
    (guardian, "field_guardian", None, "zone_index", 1),
    (guardian, "field_guardian", None, "guardian_kind_path", ""),
    (guardian, "field_guardian", None, "guardian_kind_path", "wrong.tres"),
    (guardian, "field_guardian", None, "applied_time_tone", module.STORE_CAPTURE_NIGHT_TONE),
    (guardian, "field_guardian", None, "applied_time_tone", [1.55001, 1.38, 1.12, 1]),
    (guardian, "field_guardian", None, "applied_time_tone", [float("nan"), 1.38, 1.12, 1]),
    (guardian, "field_guardian", None, "applied_time_tone", ["1.55", 1.38, 1.12, 1]),
    (guardian, "field_guardian", None, "guardian_visual_node_class", "Sprite2D"),
    (guardian, "field_guardian", None, "guardian_root_effective_alpha", 0.0),
    (guardian, "field_guardian", None, "guardian_sprite_effective_alpha", float("inf")),
    (guardian, "field_guardian", None, "guardian_current_animation", ""),
    (guardian, "field_guardian", None, "guardian_current_frame", -1),
    (guardian, "field_guardian", None, "guardian_frame_texture_path",
     "res://assets/custom/actors/guardians/wisp.png"),
    (guardian, "field_guardian", None, "guardian_capture_active", False),
    (guardian, "field_guardian", None, "friendly_projectile_count", 1),
    (guardian, "field_guardian", None, "friendly_projectile_count", 0.5),
    (guardian, "field_guardian", None, "guardian_draw_rect",
     [20.0, 164.0, 60.0, 60.0]),
    (guardian, "field_guardian", None, "guardian_draw_rect",
     [470.0, 164.0, float("nan"), 60.0]),
    (guardian, "field_guardian", None, "guardian_focus_rect",
     [0.0, 0.0, 808.0, 360.0]),
    (guardian, "field_guardian", None,
     "guardian_draw_rect_fully_inside_viewport", False),
    (guardian, "field_guardian", None,
     "guardian_draw_rect_inside_focus", False),
    (guardian, "field_guardian", None,
     "guardian_draw_center_inside_focus", False),
    (guardian, "field_guardian", None,
     "guardian_player_canvas_distance", 71.999),
    (guardian, "field_guardian", None,
     "guardian_player_canvas_distance", float("inf")),
    (guardian, "field_guardian", None,
     "guardian_separated_from_player", False),
    (guardian, "field_guardian", None,
     "guardian_central_composition", False),
    (hero_iap, "iap_review", hero_product, "portrait_visible", False),
    (hero_iap, "iap_review", hero_product, "hero_resource_path", "res://resources/heroes/dancer.tres"),
    (hero_iap, "iap_review", hero_product, "shop_opaque", False),
    (hero_iap, "iap_review", hero_product, "shop_frame_inside_viewport", False),
    (hero_iap, "iap_review", hero_product, "card_inside_screen", False),
    (hero_iap, "iap_review", hero_product, "card_opaque", False),
    (hero_iap, "iap_review", hero_product, "portrait_opaque", False),
    (hero_iap, "iap_review", hero_product, "action_visible_rect_ready", False),
    (hero_iap, "iap_review", hero_product, "review_fallback_verified", False),
    (hero_iap, "iap_review", hero_product, "review_status_visible", False),
    (hero_iap, "iap_review", hero_product, "review_status_opaque", False),
    (hero_iap, "iap_review", hero_product, "price_visible", False),
    (hero_iap, "iap_review", hero_product, "price_opaque", False),
    (hero_iap, "iap_review", hero_product, "action_enabled", True),
    (hero_iap, "iap_review", hero_product, "restore_enabled", True),
    (supporter_iap, "iap_review", supporter_product, "artwork_textures_ready", False),
    (supporter_iap, "iap_review", supporter_product, "artwork_opaque", False),
    (lantern_iap, "iap_review", lantern_product, "artwork_opaque", False),
    (lantern_iap, "iap_review", lantern_product, "artwork_product_specific", False),
]
safe_contracts = (
    (title, "title", None, "viewport_rect", ("safe_ui_ready",),
     module.STORE_CAPTURE_TITLE_DIRECT_SAFE_CONTROLS),
    (arena, "arena_ready", None, "viewport_rect", ("safe_ui_ready",),
     module.STORE_CAPTURE_ARENA_SAFE_CONTROLS),
    (barrage, "moonlight_barrage", None, "viewport_rect",
     ("safe_ui_ready",), module.STORE_CAPTURE_ARENA_SAFE_CONTROLS),
    (guardian, "field_guardian", None, "viewport_rect",
     ("safe_ui_ready",), module.STORE_CAPTURE_ARENA_SAFE_CONTROLS),
    (shrine, "shrine", None, "viewport_rect",
     ("shrine_safe_ui_ready",), ("shrine_frame",)),
    (preview, "hero_preview", None, "viewport_rect",
     ("shrine_safe_ui_ready", "preview_safe_ui_ready"),
     ("shrine_frame", "preview_frame", "close")),
    (hero_iap, "iap_review", hero_product, "screen_rect",
     ("iap_safe_ui_ready",), ("shop_frame", "card")),
)
for guard, kind, product_id, viewport_field, ready_fields, controls in safe_contracts:
    invalid.extend((
        (guard, kind, product_id, "safe_area_inside_viewport", False),
        (guard, kind, product_id, viewport_field, [0.0, 0.0, 0.0, 360.0]),
        (guard, kind, product_id, "safe_rect", [-0.52, 0.0, 808.0, 360.0]),
        (guard, kind, product_id, "safe_rect", [0.0, 0.0, float("nan"), 360.0]),
    ))
    invalid.extend(
        (guard, kind, product_id, ready_field, False)
        for ready_field in ready_fields
    )
    for control in controls:
        invalid.extend((
            (guard, kind, product_id, f"{control}_rect",
             [27.48, 40.0, 100.0, 30.0]),
            (guard, kind, product_id, f"{control}_rect",
             [40.0, 40.0, True, 30.0]),
            (guard, kind, product_id, f"{control}_inside_safe_area", False),
        ))
invalid.extend(
    (title, "title", None, field, False)
    for field in (
        "title_text_nonempty",
        "title_characters_visible",
        "title_font_size_positive",
        "title_font_alpha_readable",
        "title_rendered_text_ready",
        "subtitle_text_nonempty",
        "subtitle_characters_visible",
        "subtitle_font_size_positive",
        "subtitle_font_alpha_readable",
        "subtitle_rendered_text_ready",
        "version_text_nonempty",
        "version_characters_visible",
        "version_font_size_positive",
        "version_font_alpha_readable",
        "version_rendered_text_ready",
        "tap_prompt_text_nonempty",
        "tap_prompt_characters_visible",
        "tap_prompt_font_size_positive",
        "tap_prompt_font_alpha_readable",
        "tap_prompt_rendered_text_ready",
        "settings_button_text_nonempty",
        "settings_button_font_size_positive",
        "settings_button_font_alpha_readable",
        "settings_button_rendered_text_ready",
        "shrine_button_text_nonempty",
        "shrine_button_font_size_positive",
        "shrine_button_font_alpha_readable",
        "shrine_button_rendered_text_ready",
        "ladder_button_text_nonempty",
        "ladder_button_font_size_positive",
        "ladder_button_font_alpha_readable",
        "ladder_button_rendered_text_ready",
        "store_button_auto_translate",
        "store_button_inside_viewport",
        "store_button_copy_valid",
        "store_button_text_nonempty",
        "store_button_font_size_positive",
        "store_button_font_alpha_readable",
        "night_forest_node_present",
        "night_forest_scene_matches",
        "night_forest_visible_in_tree",
        "night_forest_opaque",
        "night_forest_ground_resource_matches",
        "night_forest_drawable_visible_in_tree",
        "night_forest_drawable_opaque",
        "night_forest_draw_rect_positive",
        "night_forest_draw_rect_intersects_viewport",
        "night_forest_visual_ready",
        "vignette_node_present",
        "vignette_texture_dimensions_match",
        "vignette_texture_matches",
        "vignette_visible_in_tree",
        "vignette_opaque",
        "vignette_draw_rect_positive",
        "vignette_draw_rect_intersects_viewport",
        "vignette_visual_ready",
        "beacon_node_present",
        "beacon_scene_matches",
        "beacon_visible_in_tree",
        "beacon_opaque",
        "beacon_clearing_resource_matches",
        "beacon_drawable_visible_in_tree",
        "beacon_drawable_opaque",
        "beacon_draw_rect_positive",
        "beacon_draw_rect_intersects_viewport",
        "beacon_visual_ready",
    )
)
invalid.extend(
    (preview, "hero_preview", None, field, False)
    for field in (
        "name_source_matches",
        "name_copy_valid",
        "name_text_nonempty",
        "name_characters_visible",
        "name_font_size_positive",
        "name_font_alpha_readable",
        "name_visible_rect_ready",
        "name_opaque",
        "name_rendered_text_ready",
        "state_source_matches",
        "state_copy_valid",
        "state_text_nonempty",
        "state_characters_visible",
        "state_font_size_positive",
        "state_font_alpha_readable",
        "state_visible_rect_ready",
        "state_opaque",
        "state_rendered_text_ready",
        "description_source_matches",
        "description_copy_valid",
        "description_text_nonempty",
        "description_characters_visible",
        "description_font_size_positive",
        "description_font_alpha_readable",
        "description_visible_rect_ready",
        "description_opaque",
        "description_rendered_text_ready",
    )
)
invalid.extend(
    (guardian, "field_guardian", None, field, False)
    for field in (
        "guardian_visual_node_present",
        "guardian_root_visible_in_tree",
        "guardian_sprite_visible_in_tree",
        "guardian_root_opaque",
        "guardian_sprite_opaque",
        "guardian_frame_texture_present",
        "guardian_frame_texture_matches_field",
        "guardian_draw_rect_positive",
        "guardian_draw_rect_intersects_viewport",
        "guardian_visual_ready",
    )
)
invalid.extend(
    (hero_iap, "iap_review", hero_product, field, False)
    for field in (
        "title_text_nonempty",
        "title_copy_valid",
        "title_characters_visible",
        "title_font_size_positive",
        "title_font_alpha_readable",
        "title_rendered_text_ready",
        "review_status_copy_valid",
        "review_status_rendered_text_ready",
        "review_status_visible_rect_ready",
        "price_copy_valid",
        "price_rendered_text_ready",
        "price_visible_rect_ready",
        "action_text_nonempty",
        "action_copy_valid",
        "action_font_size_positive",
        "action_font_alpha_readable",
        "action_rendered_text_ready",
        "restore_text_nonempty",
        "restore_copy_valid",
        "restore_font_size_positive",
        "restore_font_alpha_readable",
        "restore_rendered_text_ready",
    )
)
invalid.extend((
    (hero_iap, "iap_review", hero_product,
     "title_expected_text", "다른 상품"),
    (hero_iap, "iap_review", hero_product, "title_text", ""),
    (hero_iap, "iap_review", hero_product,
     "action_expected_text", "장착"),
    (hero_iap, "iap_review", hero_product, "action_text", ""),
    (hero_iap, "iap_review", hero_product,
     "restore_expected_text", "다시 시도"),
    (hero_iap, "iap_review", hero_product, "restore_text", ""),
    (hero_iap, "iap_review", hero_product,
     "review_status_text", "상품을 불러올 수 없습니다"),
    (hero_iap, "iap_review", hero_product,
     "review_status_expected_text", "상품을 불러올 수 없습니다"),
    (hero_iap, "iap_review", hero_product,
     "price_text", "$9.99"),
    (hero_iap, "iap_review", hero_product,
     "price_expected_text", "$9.99"),
))
# Independent title literals still reject when actual/expected are both set to the same wrong value.
for actual_field, expected_field, wrong_value in (
    ("night_forest_scene_path", "night_forest_expected_scene_path",
     "res://same-wrong/forest.tscn"),
    ("night_forest_ground_resource_path",
     "night_forest_expected_ground_resource_path",
     "res://same-wrong/ground.png"),
    ("vignette_texture_class", "vignette_expected_texture_class",
     "SameWrongTexture2D"),
    ("vignette_texture_unique_id", "vignette_expected_texture_unique_id",
     "same_wrong_vignette"),
    ("beacon_scene_path", "beacon_expected_scene_path",
     "res://same-wrong/beacon.tscn"),
    ("beacon_clearing_resource_path",
     "beacon_expected_clearing_resource_path",
     "res://same-wrong/clearing.png"),
):
    shared_wrong_title_art = copy.deepcopy(title)
    shared_wrong_title_art[actual_field] = wrong_value
    shared_wrong_title_art[expected_field] = wrong_value
    invalid.append((shared_wrong_title_art, "title", None,
                    actual_field, wrong_value))
# Independent SKU literals still reject when actual and expected are both set to the same wrong value.
shared_wrong_title = copy.deepcopy(hero_iap)
shared_wrong_title["title_text"] = "같이 틀린 이름"
shared_wrong_title["title_expected_text"] = "같이 틀린 이름"
invalid.append((shared_wrong_title, "iap_review", hero_product,
                "title_text", "같이 틀린 이름"))
shared_wrong_status = copy.deepcopy(hero_iap)
shared_wrong_status["review_status_text"] = "같이 틀린 안내"
shared_wrong_status["review_status_expected_text"] = "같이 틀린 안내"
invalid.append((shared_wrong_status, "iap_review", hero_product,
                "review_status_text", "같이 틀린 안내"))
shared_wrong_price = copy.deepcopy(hero_iap)
shared_wrong_price["price_text"] = "$9.99"
shared_wrong_price["price_expected_text"] = "$9.99"
invalid.append((shared_wrong_price, "iap_review", hero_product,
                "price_text", "$9.99"))
shared_wrong_action = copy.deepcopy(hero_iap)
shared_wrong_action["action_text"] = "장착"
shared_wrong_action["action_expected_text"] = "장착"
invalid.append((shared_wrong_action, "iap_review", hero_product,
                "action_text", "장착"))
shared_wrong_restore = copy.deepcopy(hero_iap)
shared_wrong_restore["restore_text"] = "복원 중"
shared_wrong_restore["restore_expected_text"] = "복원 중"
invalid.append((shared_wrong_restore, "iap_review", hero_product,
                "restore_text", "복원 중"))
# Keeper independent literal/source contracts still reject when actual/expected are
# both polluted or when name/description source keys are swapped.
shared_wrong_preview_name = copy.deepcopy(preview)
shared_wrong_preview_name["name_text"] = "같이 틀린 이름"
shared_wrong_preview_name["name_expected_text"] = "같이 틀린 이름"
invalid.append((shared_wrong_preview_name, "hero_preview", None,
                "name_text", "같이 틀린 이름"))
shared_wrong_preview_description = copy.deepcopy(preview)
shared_wrong_preview_description["description_text"] = "같이 틀린 설명"
shared_wrong_preview_description["description_expected_text"] = "같이 틀린 설명"
invalid.append((shared_wrong_preview_description, "hero_preview", None,
                "description_text", "같이 틀린 설명"))
shared_wrong_preview_name_source = copy.deepcopy(preview)
shared_wrong_preview_name_source["name_source_key"] = "HERO_KEEPER_DESC"
shared_wrong_preview_name_source["name_expected_source_key"] = "HERO_KEEPER_DESC"
invalid.append((shared_wrong_preview_name_source, "hero_preview", None,
                "name_source_key", "HERO_KEEPER_DESC"))
shared_wrong_preview_description_source = copy.deepcopy(preview)
shared_wrong_preview_description_source["description_source_key"] = \
    "HERO_KEEPER_NAME"
shared_wrong_preview_description_source["description_expected_source_key"] = \
    "HERO_KEEPER_NAME"
invalid.append((shared_wrong_preview_description_source, "hero_preview", None,
                "description_source_key", "HERO_KEEPER_NAME"))
shared_wrong_preview_state = copy.deepcopy(preview)
shared_wrong_preview_state["state_source_key"] = "HERO_KEEPER_NAME"
shared_wrong_preview_state["state_expected_source_key"] = "HERO_KEEPER_NAME"
shared_wrong_preview_state["state_text"] = "봉화지기"
shared_wrong_preview_state["state_expected_text"] = "봉화지기"
invalid.append((shared_wrong_preview_state, "hero_preview", None,
                "state_source_key", "HERO_KEEPER_NAME"))
for index, (guard, kind, product_id, field, value) in enumerate(invalid):
    changed = copy.deepcopy(guard)
    changed[field] = value
    try:
        module._validate_store_capture_state_guard(
            {"state_guard": changed}, f"invalid-{index}.png", "ko", kind, product_id)
    except RuntimeError:
        continue
    raise RuntimeError(f"invalid state guard was accepted: {kind}.{field}")

legacy_fake = copy.deepcopy(supporter_iap)
for field in (
    "artwork_node_present",
    "artwork_expected_kind",
    "artwork_expected_item_count",
    "artwork_textures_ready",
    "artwork_visible_rect_ready",
    "artwork_product_specific",
):
    legacy_fake.pop(field)
legacy_fake["artwork_kind"] = "supporter"
legacy_fake["artwork_texture_count"] = 1
try:
    module._validate_store_capture_state_guard(
        {"state_guard": legacy_fake}, "legacy-fake.png", "ko",
        "iap_review", supporter_product)
except RuntimeError:
    pass
else:
    raise RuntimeError("legacy fake artwork guard was accepted")
`;
  const result = spawnSync(
    process.execPath,
    [
      'scripts/python.mjs',
      '-B',
      '-c',
      source,
      resolve('apps/game/tools/build_store_graphics.py'),
    ],
    { cwd: resolve('.'), encoding: 'utf8' },
  );
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test('phone report physical safe area is recomputed from the real PNG scale', () => {
  const probe = String.raw`
import copy
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_phone_safe", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

viewport = [0.0, 0.0, 808.0, 360.0]
safe = [12.0, 12.0, 784.0, 336.0]
state = {"viewport_rect": viewport, "safe_rect": safe}
proof = {
    "png_size": [2424, 1080],
    "viewport_scale": {"x": 3.0, "y": 3.0},
    "minimum_physical_inset": 34,
    "physical_insets": {"left": 36.0, "top": 36.0, "right": 36.0, "bottom": 36.0},
}
capture = {"physical_safe_layout": proof}
module._validate_capture_physical_safe_layout(
    capture, state, 2424, 1080, "phone-valid.png")
module._validate_capture_physical_safe_layout(
    capture,
    {"screen_rect": viewport, "safe_rect": safe},
    2424,
    1080,
    "iap-valid.png",
    viewport_field="screen_rect",
)

def rejected(label, candidate_capture, candidate_state, width=2424, height=1080):
    try:
        module._validate_capture_physical_safe_layout(
            candidate_capture, candidate_state, width, height, f"{label}.png")
    except RuntimeError:
        return
    raise RuntimeError(f"invalid phone physical safe proof was accepted: {label}")

full_viewport = {"viewport_rect": viewport, "safe_rect": viewport}
rejected("full viewport", {
    "physical_safe_layout": {
        **proof,
        "physical_insets": {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0},
    },
}, full_viewport)

safe_33 = [11.0, 11.0, 786.0, 338.0]
rejected("33px inset", {
    "physical_safe_layout": {
        **proof,
        "physical_insets": {"left": 33.0, "top": 33.0, "right": 33.0, "bottom": 33.0},
    },
}, {"viewport_rect": viewport, "safe_rect": safe_33})

tampered = copy.deepcopy(capture)
tampered["physical_safe_layout"]["physical_insets"]["left"] = 360.0
rejected("tampered proof", tampered, state)
rejected("missing proof", {}, state)
rejected("anisotropic PNG", capture, state, 2424, 1000)
`;
  const result = spawnSync(
    process.execPath,
    [
      'scripts/python.mjs',
      '-B',
      '-c',
      probe,
      resolve('apps/game/tools/build_store_graphics.py'),
    ],
    { cwd: resolve('.'), encoding: 'utf8' },
  );
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test('Pixel phone gate rechecks real AVD config bytes and persistence restore', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-phone-device-proof-'));
  try {
    const probe = String.raw`
import copy
import base64
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_phone_device", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
contract = module.ANDROID_PHONE_CAPTURE_CONTRACT
capture_root = root / "builds/shots/store-localized"
capture_root.mkdir(parents=True)
if not module._android_capture_jarsigner_output_is_signed(
        0,
        "capture-report.unsigned.json\njar verified.\n"):
    raise RuntimeError("signed payload filename was mistaken for unsigned entry")
for invalid_jarsigner_output in (
    "jar is unsigned.\n",
    "jar verified.\nThis jar contains unsigned entries\n",
):
    if module._android_capture_jarsigner_output_is_signed(
            0, invalid_jarsigner_output):
        raise RuntimeError("unsigned jarsigner output was accepted")
config_path = capture_root / "avd-config.ini"
config_bytes = (
    f"abi.type={contract['abi_type']}\n"
    f"hw.device.name={contract['hw_device_name']}\n"
    f"hw.lcd.density={contract['density_dpi']}\n"
    f"hw.lcd.height={contract['config_size'][1]}\n"
    f"hw.lcd.width={contract['config_size'][0]}\n"
    f"image.sysdir.1={contract['image_sysdir']}\n"
).encode()
config_path.write_bytes(config_bytes)
normalized = module._parse_android_avd_config(config_bytes, "Pixel fixture")
normalized_bytes = (
    json.dumps(normalized, ensure_ascii=False, separators=(",", ":")) + "\n"
).encode()
settings_before = b"locale=ko\n"
settings_observed = b"locale=en\n"
before = {
    name: (hashlib.sha256(settings_before).hexdigest()
           if name == "settings.cfg" else None)
    for name in module.ANDROID_CAPTURE_PERSISTENT_FILES
}
observed = dict(before)
observed["settings.cfg"] = hashlib.sha256(settings_observed).hexdigest()
capture_id = "9" * 64
anchor_relative = "builds/shots/store-localized/persistence-evidence.json"
anchor_transcript = {
    "schema": 1,
    "capture_id": capture_id,
    "persistent_data_files": list(module.ANDROID_CAPTURE_PERSISTENT_FILES),
    "persistent_data_sha256_before": before,
    "persistent_data_sha256_observed": observed,
    "persistent_data_sha256_restored": dict(before),
    "settings_bytes": {
        "original_base64": base64.b64encode(settings_before).decode(),
        "observed_base64": base64.b64encode(settings_observed).decode(),
        "restored_base64": base64.b64encode(settings_before).decode(),
    },
}
anchor_bytes = (json.dumps(anchor_transcript, indent=2) + "\n").encode()
(root / anchor_relative).write_bytes(anchor_bytes)
report = {
    "avd_name": contract["avd_name"],
    "api_level": contract["api_level"],
    "physical_size": {
        "width": 1080, "height": 2424,
        "raw": "Physical size: 1080x2424",
    },
    "density": {"dpi": 420, "raw": "Physical density: 420"},
    "avd_config": {
        "schema": 1,
        "target": "pixel-phone",
        "avd_name": contract["avd_name"],
        "normalized": normalized,
        "source_sha256": hashlib.sha256(config_bytes).hexdigest(),
        "normalized_sha256": hashlib.sha256(normalized_bytes).hexdigest(),
        "evidence_path": "builds/shots/store-localized/avd-config.ini",
    },
    "persistent_data_files": list(module.ANDROID_CAPTURE_PERSISTENT_FILES),
    "persistent_data_sha256_before": before,
    "persistent_data_sha256_observed": observed,
    "persistent_data_sha256_restored": dict(before),
    "persistent_data_mutated_during_capture": True,
    "persistent_data_restored_byte_exact": True,
    "persistent_data_unchanged": True,
    "settings_restore": {
        "original_present": True,
        "original_sha256": before["settings.cfg"],
        "observed_sha256": observed["settings.cfg"],
        "restored_sha256": before["settings.cfg"],
        "byte_exact": True,
    },
    "persistence_anchor": {
        "schema": 1,
        "capture_id": capture_id,
        "path": anchor_relative,
        "sha256": hashlib.sha256(anchor_bytes).hexdigest(),
    },
}
signature_relative = (
    "builds/shots/store-localized/"
    + module.ANDROID_CAPTURE_SIGNATURE_FILENAME
)
signature_bytes = b"fixture-signed-persistence-jar"
(root / signature_relative).write_bytes(signature_bytes)
unsigned_report_bytes = (json.dumps(report, indent=2) + "\n").encode()
report["persistence_signature"] = {
    "schema": 1,
    "format": "jar",
    "signature_algorithm": "SHA256withRSA",
    "digest_algorithm": "SHA-256",
    "certificate_sha256": module.ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256,
    "path": signature_relative,
    "sha256": hashlib.sha256(signature_bytes).hexdigest(),
    "report_entry": module.ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
    "report_sha256": hashlib.sha256(unsigned_report_bytes).hexdigest(),
    "anchor_entry": module.ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
    "anchor_sha256": hashlib.sha256(anchor_bytes).hexdigest(),
    "capture_id": capture_id,
}
def verify_fixture_signature(path, source):
    if path.resolve() == (root / signature_relative).resolve() \
            or path.read_bytes() != signature_bytes:
        raise RuntimeError("signature verifier did not use an immutable byte copy")
    return ({
        module.ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY: unsigned_report_bytes,
        module.ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY: anchor_bytes,
    }, module.ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256)
module._verified_android_capture_signature_payloads = verify_fixture_signature

def validate(candidate):
    module._validate_android_capture_persistence(
        candidate, "Pixel fixture", capture_root)
    module._validate_android_avd_capture_evidence(
        candidate, "pixel-phone", contract, "Pixel fixture", capture_root)

validate(report)

def rejected(label, mutate):
    candidate = copy.deepcopy(report)
    mutate(candidate)
    try:
        validate(candidate)
    except RuntimeError:
        return
    raise RuntimeError(f"invalid Pixel proof was accepted: {label}")

rejected("missing files", lambda value: value.pop("persistent_data_files"))
rejected("restored mismatch", lambda value: value[
    "persistent_data_sha256_restored"].__setitem__("settings.cfg", "c" * 64))
rejected("settings mismatch", lambda value: value[
    "settings_restore"].__setitem__("restored_sha256", "d" * 64))
def self_consistent_all_null(value):
    for field in (
        "persistent_data_sha256_before",
        "persistent_data_sha256_observed",
        "persistent_data_sha256_restored",
    ):
        value[field] = {
            name: None for name in module.ANDROID_CAPTURE_PERSISTENT_FILES
        }
    value["persistent_data_mutated_during_capture"] = False
    value["settings_restore"] = {
        "original_present": False,
        "original_sha256": None,
        "observed_sha256": None,
        "restored_sha256": None,
        "byte_exact": True,
    }
rejected("self-consistent all-null persistence", self_consistent_all_null)
rejected("wrong API", lambda value: value.__setitem__("api_level", 36))
rejected("wrong size", lambda value: value[
    "physical_size"].__setitem__("width", 2400))
def landscape_png_size_is_not_native_wm_size(value):
    value["physical_size"] = {
        "width": 2424, "height": 1080,
        "raw": "Physical size: 2424x1080",
    }
rejected("landscape PNG size used as native wm size",
         landscape_png_size_is_not_native_wm_size)
rejected("wrong density", lambda value: value[
    "density"].__setitem__("dpi", 160))
rejected("forged normalized", lambda value: value[
    "avd_config"]["normalized"].__setitem__("abi_type", "x86_64"))

anchor_path = root / anchor_relative
anchor_path.write_bytes(anchor_bytes + b"tampered")
try:
    validate(report)
except RuntimeError:
    pass
else:
    raise RuntimeError("tampered persistence anchor was accepted")
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('validation rejects the legacy shared IAP review source', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-store-stale-iap-source-'));
  try {
    const stale = join(
      root,
      'builds/shots/store-localized/ko-KR/iap-review.png',
    );
    mkdirSync(join(stale, '..'), { recursive: true });
    writeFileSync(stale, 'legacy shared review image');

    const probe = `
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_stale_iap", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = Path(sys.argv[2])
module.STALE_IAP_REVIEW_SOURCE = Path(sys.argv[3])
module._validate_generated_screenshots([])
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
        stale,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.notEqual(result.status, 0);
    assert.match(
      `${result.stdout}\n${result.stderr}`,
      /legacy shared IAP review source ko-KR\/iap-review\.png/u,
    );
    assert.equal(existsSync(stale), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('generation cleanup removes only the legacy shared IAP file', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-store-clean-iap-source-'));
  try {
    const stale = join(
      root,
      'builds/shots/store-localized/ko-KR/iap-review.png',
    );
    const current = join(
      root,
      'builds/shots/store-localized/ko-KR/iap-review/hero-eclipse.png',
    );
    mkdirSync(join(current, '..'), { recursive: true });
    writeFileSync(stale, 'legacy shared review image');
    writeFileSync(current, 'current product review image');

    const probe = `
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_clean_iap", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = Path(sys.argv[2])
module.STALE_IAP_REVIEW_SOURCE = Path(sys.argv[3])
module.shutil.which = lambda command: "/usr/bin/false"
def stop_after_cleanup():
    raise RuntimeError("stop-after-stale-cleanup")
module._screenshot_entries = stop_after_cleanup
try:
    module._build_screenshots()
except RuntimeError as error:
    if str(error) != "stop-after-stale-cleanup":
        raise
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
        stale,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.equal(existsSync(stale), false);
    assert.equal(readFileSync(current, 'utf8'), 'current product review image');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('per-platform screenshots keep phone, tablet, iPhone, and iPad sources separate', () => {
  const probe = `
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_device_sources", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
entry = {
    "output": "01-moonlight-barrage.png",
    "localized_sources": {
        "ko-KR": "builds/shots/store-localized/ko-KR/01-moonlight-barrage.png",
    },
}
devices = [None, "seven-inch-tablet", "ten-inch-tablet", "iphone-6.5", "ipad-13"]
print(json.dumps({
    "paths": [str(module._entry_source(entry, "ko-KR", device)) for device in devices],
    "app_store_physical": [
        str(module._app_store_entry_source(
            entry, "ko-KR", device, module.APP_STORE_IPHONE_SOURCE_PHYSICAL))
        for device in ("iphone-6.5", "ipad-13")
    ],
    "app_store_avd": [
        str(module._app_store_entry_source(
            entry, "ko-KR", device,
            module.APP_STORE_IPHONE_SOURCE_ANDROID_AVD))
        for device in ("iphone-6.5", "ipad-13")
    ],
}, sort_keys=True))
`;
  const result = spawnSync(
    process.execPath,
    [
      'scripts/python.mjs',
      '-B',
      '-c',
      probe,
      resolve('apps/game/tools/build_store_graphics.py'),
    ],
    { cwd: resolve('.'), encoding: 'utf8' },
  );
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const { app_store_avd: appStoreAvd, app_store_physical: appStorePhysical, paths } = JSON.parse(
    result.stdout.trim().split('\n').at(-1),
  );
  assert.equal(new Set(paths).size, 5);
  assert.match(paths[0], /store-localized\/ko-KR\/01-moonlight-barrage\.png$/u);
  assert.match(paths[1], /store-platform\/android\/seven-inch-tablet\/ko-KR\/01-moonlight-barrage\.png$/u);
  assert.match(paths[2], /store-platform\/android\/ten-inch-tablet\/ko-KR\/01-moonlight-barrage\.png$/u);
  assert.match(paths[3], /store-platform\/ios\/iphone-6\.5\/ko-KR\/01-moonlight-barrage\.png$/u);
  assert.match(paths[4], /store-platform\/ios\/ipad-13\/ko-KR\/01-moonlight-barrage\.png$/u);
  assert.equal(appStorePhysical[0], paths[3]);
  assert.equal(appStorePhysical[1], paths[4]);
  assert.equal(appStoreAvd[0], paths[0]);
  assert.equal(appStoreAvd[1], paths[4]);
});

test('App Store iPhone source mode rejects physical/fallback mixing and missing proofs', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-app-store-source-mode-'));
  try {
    const probe = `
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_source_mode", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.DEVICE_CAPTURE_ROOT = root / "builds/shots/store-platform"
module.SCREENSHOT_CAPTURE_REPORT = (
    root / "builds/shots/store-localized/capture-report.json")
module._validate_capture_report = lambda _entries: {"pixel": True}

selected = []
def validate_devices(_entries, devices):
    selected.append(tuple(devices))
    return {
        device: {
            "report": {},
            "report_path": root / f"{device}.json",
            "report_sha256": device,
            "hashes": {},
        }
        for device in devices
    }
module._validate_device_capture_reports_for_targets = validate_devices

fallback = module._validate_app_store_capture_sources(
    [], module.APP_STORE_IPHONE_SOURCE_ANDROID_AVD)
if selected[-1] != ("ipad-13",) \
        or set(fallback["device_contexts"]) != {"ipad-13"}:
    raise RuntimeError("fallback did not retain physical iPad-only evidence")

physical = module._validate_app_store_capture_sources(
    [], module.APP_STORE_IPHONE_SOURCE_PHYSICAL)
if selected[-1] != ("iphone-6.5", "ipad-13") \
        or set(physical["device_contexts"]) != {"iphone-6.5", "ipad-13"}:
    raise RuntimeError("physical mode did not require both iOS devices")

# Fail closed when fallback and physical iPhone raw both exist — origin would be ambiguous.
iphone = module.DEVICE_CAPTURE_ROOT / "ios/iphone-6.5/en-US"
iphone.mkdir(parents=True)
(iphone / "01.png").write_bytes(b"physical")
try:
    module._validate_app_store_capture_sources(
        [], module.APP_STORE_IPHONE_SOURCE_ANDROID_AVD)
except RuntimeError:
    pass
else:
    raise RuntimeError("mixed physical/fallback iPhone evidence was accepted")

# In physical mode, a missing report on either side must not allow neither/missing evidence.
def missing_ipad(_entries, devices):
    return {"iphone-6.5": {}} if "iphone-6.5" in devices else {}
module._validate_device_capture_reports_for_targets = missing_ipad
try:
    module._validate_app_store_capture_sources(
        [], module.APP_STORE_IPHONE_SOURCE_PHYSICAL)
except RuntimeError:
    pass
else:
    raise RuntimeError("missing physical iPad evidence was accepted")

print(json.dumps({"selected": selected}, sort_keys=True))
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('App Store provenance binds all 60 sources 1:1 and rejects every tamper', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-app-store-provenance-'));
  try {
    const probe = `
import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2]).resolve()
spec = importlib.util.spec_from_file_location("store_graphics_provenance", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.__file__ = str(root / "apps/game/tools/build_store_graphics.py")
module.RELEASE_OUTPUT_ROOT = root / "builds/release"
module.APP_STORE_SCREENSHOT_OUTPUT = module.RELEASE_OUTPUT_ROOT / "app-store"
module.IAP_REVIEW_OUTPUT_ROOT = module.APP_STORE_SCREENSHOT_OUTPUT / "iap-review"
module.SCREENSHOT_CAPTURE_REPORT = (
    root / "builds/shots/store-localized/capture-report.json")
module.DEVICE_CAPTURE_ROOT = root / "builds/shots/store-platform"
module._validate_screenshot_file = lambda *args: None
module._png_size = lambda path: (
    (2732, 2048) if "/ios/ipad-13/" in path.as_posix()
    else (2424, 1080))

(root / "apps/game/tools").mkdir(parents=True)
(root / "apps/game/tools/build_store_graphics.py").write_bytes(
    b"fixture renderer")

def digest(contents):
    return hashlib.sha256(contents).hexdigest()

def write(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(contents)

outputs = [f"{index:02d}-scene.png" for index in range(1, 7)]
entries = []
pixel_captures = []
ipad_captures = []
for index, output in enumerate(outputs, 1):
    localized = {}
    for locale in module.SCREENSHOT_LOCALES:
        phone_relative = (
            f"builds/shots/store-localized/{locale}/{output}")
        ipad_relative = (
            f"builds/shots/store-platform/ios/ipad-13/{locale}/{output}")
        localized[locale] = phone_relative
        for device, relative, captures in (
            ("pixel", phone_relative, pixel_captures),
            ("ipad", ipad_relative, ipad_captures),
        ):
            source_bytes = f"source:{device}:{locale}:{index}".encode()
            proof_relative = relative + ".proof.json"
            write(root / relative, source_bytes)
            write(
                root / proof_relative,
                f"proof:{device}:{locale}:{index}".encode(),
            )
            captures.append({
                "kind": f"scene-{index}",
                "proof_path": proof_relative,
                "sha256": digest(source_bytes),
                "source": relative,
            })
        for target in module.APP_STORE_FORMATS:
            store_locale = module.APP_STORE_LOCALES[locale]
            output_path = (
                module.APP_STORE_SCREENSHOT_OUTPUT
                / store_locale / target / output)
            write(
                output_path,
                f"output:{target}:{locale}:{index}".encode(),
            )
    entries.append({"localized_sources": localized, "output": output})

pixel_report = {
    "api_level": 34,
    "apk_path": "builds/shots/store-localized/capture-debug.apk",
    "apk_sha256": "a" * 64,
    "avd_name": "Pixel_10_API_34",
    "captured_at": "2026-08-03T00:00:00Z",
    "captures": pixel_captures,
    "input_sha256": {"package.json": "b" * 64},
    "persistence_anchor": {"capture_id": "c" * 64},
    "runtime_sha256": "d" * 64,
}
pixel_report_bytes = (
    json.dumps(pixel_report, sort_keys=True) + "\\n").encode()
write(module.SCREENSHOT_CAPTURE_REPORT, pixel_report_bytes)
ipad_report_path = (
    module.DEVICE_CAPTURE_ROOT / "ios/ipad-13/capture-report.json")
ipad_report = {
    "build_artifact_path": "builds/ios-device/ipad.app.zip",
    "build_artifact_sha256": "e" * 64,
    "captured_at": "2026-08-03T00:01:00Z",
    "captures": ipad_captures,
    "model_identifier": "iPadFixture1,1",
    "source_before": {
        "runtime_sha256": "f" * 64,
        "source_input_sha256": {"package.json": "1" * 64},
    },
}
write(
    ipad_report_path,
    (json.dumps(ipad_report, sort_keys=True) + "\\n").encode(),
)
context = {
    "device_contexts": {
        "ipad-13": {
            "hashes": {},
            "report": ipad_report,
            "report_path": ipad_report_path,
            "report_sha256": digest(ipad_report_path.read_bytes()),
        },
    },
    "iphone_source_mode": module.APP_STORE_IPHONE_SOURCE_ANDROID_AVD,
    "pixel_report": pixel_report,
}

provenance = module._build_app_store_screenshot_provenance(
    entries, module.APP_STORE_SCREENSHOT_OUTPUT, context)
if [item["id"] for item in provenance["sets"]] \
        != ["iphone-6.5", "ipad-13"]:
    raise RuntimeError("provenance set order/IDs are wrong")
for item in provenance["sets"]:
    if len(item["mappings"]) != 30:
        raise RuntimeError("provenance set did not contain exactly 30 mappings")
iphone_set, ipad_set = provenance["sets"]
if iphone_set["capture_origin"]["platform"] != "ANDROID" \
        or iphone_set["capture_origin"]["native_ios_capture"] is not False:
    raise RuntimeError("AVD iPhone marketing origin was mislabeled")
if ipad_set["capture_origin"]["platform"] != "IOS" \
        or ipad_set["capture_origin"]["native_ios_capture"] is not True:
    raise RuntimeError("physical iPad origin was not retained")
if any("/ios/iphone-6.5/" in mapping["source_path"]
       for mapping in iphone_set["mappings"]):
    raise RuntimeError("AVD sources were copied/mislabeled as physical iPhone")
if any("/ios/ipad-13/" not in mapping["source_path"]
       for mapping in ipad_set["mappings"]):
    raise RuntimeError("fallback replaced physical iPad sources")
if (module.DEVICE_CAPTURE_ROOT / "ios/iphone-6.5").exists():
    raise RuntimeError("fallback created a fake iPhone evidence root")

module._write_app_store_screenshot_provenance(
    module.APP_STORE_SCREENSHOT_OUTPUT, provenance)
module._validate_app_store_capture_sources = lambda _entries, _mode: context
module._validate_app_store_screenshot_provenance(
    entries, module.APP_STORE_SCREENSHOT_OUTPUT)
provenance_path = module._app_store_provenance_path(
    module.APP_STORE_SCREENSHOT_OUTPUT)
original_provenance = provenance_path.read_bytes()

def expect_validation_rejected(label, mutate, restore):
    mutate()
    try:
        module._validate_app_store_screenshot_provenance(
            entries, module.APP_STORE_SCREENSHOT_OUTPUT)
    except RuntimeError:
        restore()
        return
    restore()
    raise RuntimeError(f"provenance tamper was accepted: {label}")

expect_validation_rejected(
    "missing provenance",
    lambda: provenance_path.unlink(),
    lambda: write(provenance_path, original_provenance),
)

def mutate_manifest():
    changed = copy.deepcopy(provenance)
    changed["sets"][0]["mappings"][1] = copy.deepcopy(
        changed["sets"][0]["mappings"][0])
    write(
        provenance_path,
        (json.dumps(changed, sort_keys=True) + "\\n").encode(),
    )
expect_validation_rejected(
    "duplicate/mutated mapping",
    mutate_manifest,
    lambda: write(provenance_path, original_provenance),
)

first_output = (
    module.APP_STORE_SCREENSHOT_OUTPUT
    / module.APP_STORE_LOCALES[module.SCREENSHOT_LOCALES[0]]
    / "iphone-6.5" / outputs[0])
original_output = first_output.read_bytes()
expect_validation_rejected(
    "output bytes",
    lambda: first_output.write_bytes(original_output + b"tampered"),
    lambda: first_output.write_bytes(original_output),
)

original_report = module.SCREENSHOT_CAPTURE_REPORT.read_bytes()
expect_validation_rejected(
    "stale capture report",
    lambda: module.SCREENSHOT_CAPTURE_REPORT.write_bytes(
        original_report + b"stale"),
    lambda: module.SCREENSHOT_CAPTURE_REPORT.write_bytes(original_report),
)

first_proof = root / pixel_captures[0]["proof_path"]
original_proof = first_proof.read_bytes()
expect_validation_rejected(
    "proof bytes",
    lambda: first_proof.write_bytes(original_proof + b"tampered"),
    lambda: first_proof.write_bytes(original_proof),
)

def expect_builder_rejected(label, mutate, restore):
    mutate()
    try:
        module._build_app_store_screenshot_provenance(
            entries, module.APP_STORE_SCREENSHOT_OUTPUT, context)
    except RuntimeError:
        restore()
        return
    restore()
    raise RuntimeError(f"invalid provenance source was accepted: {label}")

second_source = root / pixel_captures[1]["source"]
original_second_source = second_source.read_bytes()
original_second_hash = pixel_captures[1]["sha256"]
def reuse_raw():
    reused = (root / pixel_captures[0]["source"]).read_bytes()
    second_source.write_bytes(reused)
    pixel_captures[1]["sha256"] = digest(reused)
def restore_raw():
    second_source.write_bytes(original_second_source)
    pixel_captures[1]["sha256"] = original_second_hash
expect_builder_rejected("raw PNG reuse", reuse_raw, restore_raw)

missing_capture = pixel_captures.pop()
try:
    try:
        module._build_app_store_screenshot_provenance(
            entries, module.APP_STORE_SCREENSHOT_OUTPUT, context)
    except RuntimeError:
        pass
    else:
        raise RuntimeError("missing capture mapping was accepted")
finally:
    pixel_captures.append(missing_capture)

second_output = (
    module.APP_STORE_SCREENSHOT_OUTPUT
    / module.APP_STORE_LOCALES[module.SCREENSHOT_LOCALES[0]]
    / "iphone-6.5" / outputs[1])
original_second_output = second_output.read_bytes()
expect_builder_rejected(
    "duplicate output bytes",
    lambda: second_output.write_bytes(first_output.read_bytes()),
    lambda: second_output.write_bytes(original_second_output),
)
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('per-platform canonical sources require both the current device report and file proofs', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-device-capture-gate-'));
  try {
    const probe = String.raw`
import hashlib
import base64
import importlib.util
import io
import json
import plistlib
import shutil
import stat
import struct
import sys
import zipfile
from pathlib import Path

module_path = Path(sys.argv[1])
root = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("store_graphics_device_gate", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REPO_ROOT = root
module.DEVICE_CAPTURE_ROOT = root / "builds/shots/store-platform"

RUNTIME_HASH = "1" * 64
INPUT_HASH = "2" * 64
SOURCE_INPUTS = {"fixture-input": INPUT_HASH}
module._runtime_fingerprint = lambda: RUNTIME_HASH
module._device_capture_source_fingerprints = lambda platform: SOURCE_INPUTS
# This test focuses on report/file/device gates. Every first-party state field and the
# safe-area rect itself are covered by the Python state_guard test immediately above.
module._validate_store_capture_state_guard = lambda *args, **kwargs: None
module._validate_missile_core_capture_guard = lambda *args, **kwargs: None

locales = module.SCREENSHOT_LOCALES
filenames = tuple(module.DEVICE_CAPTURE_SCREENSHOT_KINDS)
entries = []
signed_payloads = {}
module._verified_android_capture_signature_payloads = lambda path, source: (
    signed_payloads[path.read_bytes()],
    module.ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256,
)

def png_bytes(label, width=1616, height=720):
    return (b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR"
            + struct.pack(">II", width, height) + label.encode("utf-8"))

def digest(value):
    return hashlib.sha256(value).hexdigest()

def persistence_evidence(target):
    settings_before = f"locale=before:{target}\n".encode()
    settings_observed = f"locale=observed:{target}\n".encode()
    before = {
        name: (digest(settings_before) if name == "settings.cfg" else None)
        for name in module.ANDROID_CAPTURE_PERSISTENT_FILES
    }
    observed = dict(before)
    observed["settings.cfg"] = digest(settings_observed)
    restored = dict(before)
    capture_id = digest(f"capture:{target}".encode())
    anchor_relative = (
        f"builds/tablet-evidence/{target}/fixture/"
        "persistence-evidence.json"
    )
    transcript = {
        "schema": 1,
        "capture_id": capture_id,
        "persistent_data_files": list(module.ANDROID_CAPTURE_PERSISTENT_FILES),
        "persistent_data_sha256_before": before,
        "persistent_data_sha256_observed": observed,
        "persistent_data_sha256_restored": restored,
        "settings_bytes": {
            "original_base64": base64.b64encode(settings_before).decode(),
            "observed_base64": base64.b64encode(settings_observed).decode(),
            "restored_base64": base64.b64encode(settings_before).decode(),
        },
    }
    anchor_bytes = (json.dumps(transcript, indent=2) + "\n").encode()
    write_bytes(anchor_relative, anchor_bytes)
    return {
        "persistent_data_files": list(module.ANDROID_CAPTURE_PERSISTENT_FILES),
        "persistent_data_sha256_before": before,
        "persistent_data_sha256_observed": observed,
        "persistent_data_sha256_restored": restored,
        "persistent_data_mutated_during_capture": True,
        "persistent_data_restored_byte_exact": True,
        "persistent_data_unchanged": True,
        "settings_restore": {
            "original_present": True,
            "original_sha256": before["settings.cfg"],
            "observed_sha256": observed["settings.cfg"],
            "restored_sha256": restored["settings.cfg"],
            "byte_exact": True,
        },
        "persistence_anchor": {
            "schema": 1,
            "capture_id": capture_id,
            "path": anchor_relative,
            "sha256": digest(anchor_bytes),
        },
    }

def ios_persistence_evidence():
    files = sorted(module.IOS_CAPTURE_PERSISTENT_FILES)
    hashes = {name: None for name in files}
    return {
        "persistent_data_files": files,
        "persistent_data_sha256_before": dict(hashes),
        "persistent_data_sha256_after": dict(hashes),
        "persistent_data_sha256_restored": dict(hashes),
        "persistent_data_mutated_during_capture": [],
        "persistent_data_restored_byte_exact": True,
        "persistent_data_unchanged": True,
        "control_files_disarmed": True,
        "settings_restore": {
            "original_present": False,
            "original_sha256": None,
            "observed_sha256": None,
            "restored_sha256": None,
            "byte_exact": True,
        },
    }

def attach_persistence_signature(target, report):
    anchor = report["persistence_anchor"]
    anchor_bytes = (root / anchor["path"]).read_bytes()
    unsigned_report_bytes = (
        json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    ).encode("utf-8")
    signature_relative = (
        f"builds/tablet-evidence/{target}/fixture/"
        f"{module.ANDROID_CAPTURE_SIGNATURE_FILENAME}"
    )
    signature_bytes = f"fixture-signed-jar:{target}".encode("utf-8")
    signature_path = write_bytes(signature_relative, signature_bytes)
    report["persistence_signature"] = {
        "schema": 1,
        "format": "jar",
        "signature_algorithm": "SHA256withRSA",
        "digest_algorithm": "SHA-256",
        "certificate_sha256": module.ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256,
        "path": signature_relative,
        "sha256": digest(signature_bytes),
        "report_entry": module.ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
        "report_sha256": digest(unsigned_report_bytes),
        "anchor_entry": module.ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
        "anchor_sha256": anchor["sha256"],
        "capture_id": anchor["capture_id"],
    }
    signed_payloads[signature_bytes] = {
        module.ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY: unsigned_report_bytes,
        module.ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY: anchor_bytes,
    }

def avd_config_bytes(contract):
    width, height = contract["config_size"]
    return (
        f"abi.type = {contract['abi_type']}\n"
        f"hw.device.name = {contract['hw_device_name']}\n"
        f"hw.lcd.density = {contract['density_dpi']}\n"
        f"hw.lcd.height = {height}\n"
        f"hw.lcd.width = {width}\n"
        f"image.sysdir.1 = {contract['image_sysdir']}\n"
    ).encode("utf-8")

def write_bytes(relative_path, value):
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)
    return path

def write_json(relative_path, value):
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n").encode()
    path = write_bytes(relative_path, data)
    return path, digest(data)

def ios_app_zip(target, bundle_id, executable_suffix=b"", pck_suffix=b"",
                resource_mode=0o644, extra_entry=None):
    plist_bytes = plistlib.dumps({
        "CFBundleIdentifier": bundle_id,
        "CFBundleExecutable": "MoonlitBeacon",
        "CFBundleShortVersionString": "1.0.1",
        "CFBundleVersion": "2",
    }, fmt=plistlib.FMT_BINARY, sort_keys=True)
    executable = f"executable:{target}".encode() + executable_suffix
    pck = f"pck:{target}".encode() + pck_suffix
    resource = f"resource:{target}".encode()
    records = {
        ".": ("directory", 0o755, b""),
        "Info.plist": ("file", 0o644, plist_bytes),
        "MoonlitBeacon": ("file", 0o755, executable),
        "MoonlitBeacon.pck": ("file", 0o644, pck),
        "Resources": ("directory", 0o755, b""),
        "Resources/fixture.dat": ("file", resource_mode, resource),
    }
    children = {path: [] for path, value in records.items()
                if value[0] == "directory"}
    for path in records:
        if path == ".":
            continue
        parent, _, name = path.rpartition("/")
        children[parent or "."].append(name)
    tree = hashlib.sha256()
    def add_length_prefixed(value):
        tree.update(len(value).to_bytes(8, "big"))
        tree.update(value)
    def visit(path):
        kind, mode, payload = records[path]
        for value in (kind.encode(), path.encode(), str(mode).encode(), payload):
            add_length_prefixed(value)
        if kind == "directory":
            for name in sorted(children[path]):
                visit(name if path == "." else f"{path}/{name}")
    visit(".")

    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path, (kind, mode, payload) in records.items():
            archive_name = "MoonlitBeacon.app" if path == "." \
                else f"MoonlitBeacon.app/{path}"
            if kind == "directory":
                archive_name += "/"
            info = zipfile.ZipInfo(archive_name, (2026, 8, 3, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            entry_type = stat.S_IFDIR if kind == "directory" else stat.S_IFREG
            info.external_attr = (entry_type | mode) << 16
            if kind == "directory":
                info.external_attr |= 0x10
            archive.writestr(info, payload)
        if extra_entry is not None:
            info = zipfile.ZipInfo(extra_entry, (2026, 8, 3, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            archive.writestr(info, b"unexpected")
    return output.getvalue(), {
        "app_tree_sha256": tree.hexdigest(),
        "executable_sha256": digest(executable),
        "pck_sha256": digest(pck),
    }

def ios_device_details(target, target_contract):
    transport = "localNetwork" if target == "ipad-13" else "wired"
    return {
        "info": {"outcome": "success"},
        "result": {
            "identifier": f"coredevice-{target}",
            "hardwareProperties": {
                "reality": "physical",
                "udid": f"fixture-{target}",
                "productType": f"{target_contract['model_prefix']}Fixture1,1",
            },
            "deviceProperties": {
                "name": f"Fixture {target}",
                "osVersionNumber": "26.5",
                "osBuildUpdate": "23F84",
                "bootState": "booted",
                "developerModeStatus": "enabled",
            },
            "connectionProperties": {
                "pairingState": "paired",
                "transportType": transport,
                "tunnelState": "connected",
                "tunnelIPAddress": "fd00::1",
            },
        },
    }

def ios_processes(target, process_id):
    return {
        "info": {
            "outcome": "success",
            "commandType": "devicectl.device.info.processes",
        },
        "result": {
            "deviceIdentifier": f"coredevice-{target}",
            "runningProcesses": [{
                "executable": (
                    f"file:///private/fixture/{target}/"
                    "MoonlitBeacon.app/MoonlitBeacon"
                ),
                "processIdentifier": process_id,
            }],
        },
    }

def ios_activation_launch(target, process_id):
    return {
        "info": {
            "outcome": "success",
            "commandType": "devicectl.device.process.launch",
        },
        "result": {
            "deviceIdentifier": f"coredevice-{target}",
            "process": {
                "executable": (
                    f"file:///private/fixture/{target}/"
                    "MoonlitBeacon.app/MoonlitBeacon"
                ),
                "processIdentifier": process_id,
            },
            "launchOptions": {
                "activatedWhenStarted": True,
                "terminateExistingInstances": False,
                "startStopped": False,
                "arguments": [],
            },
        },
    }

def controls_for(kind, expected_direct_distribution=True):
    state_kind = "arena_ready" if kind == "missile_core_recovery" else kind
    return module._device_capture_controls(
        state_kind, expected_direct_distribution)

def runtime_state(
        kind, nonce, observation, expected_direct_distribution=True,
        viewport_height=360.0):
    state = {
        "nonce": nonce,
        "observation": observation,
        "viewport_rect": [0.0, 0.0, 808.0, viewport_height],
        "safe_rect": [28.0, 28.0, 752.0, viewport_height - 56.0],
    }
    for index, control in enumerate(
            controls_for(kind, expected_direct_distribution)):
        state[f"{control}_rect"] = [40.0 + index, 40.0 + index, 80.0, 24.0]
    return state

def safe_layout(state, kind, expected_direct_distribution=True):
    return {
        "viewport_rect": state["viewport_rect"],
        "safe_rect": state["safe_rect"],
        "logical_insets": {"left": 28.0, "top": 28.0, "right": 28.0, "bottom": 28.0},
        "controls": {
            f"{control}_rect": state[f"{control}_rect"]
            for control in controls_for(kind, expected_direct_distribution)
        },
    }

def physical_layout(width, height, state):
    viewport = state["viewport_rect"]
    safe = state["safe_rect"]
    scale_x = width / viewport[2]
    scale_y = height / viewport[3]
    return {
        "png_size": [width, height],
        "viewport_scale": {"x": scale_x, "y": scale_y},
        "minimum_physical_inset": 34,
        "physical_insets": {
            "left": (safe[0] - viewport[0]) * scale_x,
            "top": (safe[1] - viewport[1]) * scale_y,
            "right": (
                viewport[0] + viewport[2] - safe[0] - safe[2]
            ) * scale_x,
            "bottom": (
                viewport[1] + viewport[3] - safe[1] - safe[3]
            ) * scale_y,
        },
    }

def canonical_source(platform, target, locale, filename):
    return f"builds/shots/store-platform/{platform}/{target}/{locale}/{filename}"

def report_path(platform, target):
    return root / f"builds/shots/store-platform/{platform}/{target}/capture-report.json"

def load_report(platform, target):
    return json.loads(report_path(platform, target).read_text())

def save_report(platform, target, report):
    report_path(platform, target).write_text(
        json.dumps(report, ensure_ascii=False, sort_keys=True) + "\n")

def reset_fixture():
    shutil.rmtree(root / "builds", ignore_errors=True)
    entries.clear()
    signed_payloads.clear()
    for filename in filenames:
        sources = {}
        for locale in locales:
            relative_path = f"builds/shots/store-localized/{locale}/{filename}"
            write_bytes(relative_path, png_bytes(f"phone:{locale}:{filename}"))
            sources[locale] = relative_path
        entries.append({"output": filename, "localized_sources": sources})

    snapshot = {
        "runtime_sha256": RUNTIME_HASH,
        "source_input_sha256": SOURCE_INPUTS,
    }
    for target, target_contract in module.DEVICE_CAPTURE_TARGETS.items():
        platform = target_contract["platform"]
        if platform == "android":
            source_width, source_height = target_contract["source_size"]
            viewport_height = source_height * 808.0 / source_width
        elif target == "ipad-13":
            source_width, source_height = 2266, 1488
            viewport_height = source_height * 808.0 / source_width
        else:
            source_width, source_height = 1616, 720
            viewport_height = 360.0
        xcode_method = platform == "ios" and target == "ipad-13"
        installed_bundle_id = (
            "com.crossplatformkorea.moonlitbeacon.storecapture"
            if platform == "ios" else "com.crossplatformkorea.moonlitbeacon"
        )
        install_relative = None
        install_hash = None
        installed_relative = None
        installed_hash = None
        installed_identity_hash = None
        if platform == "ios":
            artifact_relative = (
                f"builds/ios-device-evidence/{target}/fixture/build/"
                "MoonlitBeacon.app.zip"
            )
            artifact_bytes, ios_hashes = ios_app_zip(
                target, installed_bundle_id)
            artifact = write_bytes(artifact_relative, artifact_bytes)
            executable_hash = ios_hashes["executable_sha256"]
            pck_hash = ios_hashes["pck_sha256"]
            app_tree_hash = ios_hashes["app_tree_sha256"]
            install_url = (
                f"file:///private/fixture/{target}/MoonlitBeacon.app/"
            )
            install_relative = (
                f"builds/ios-device-evidence/{target}/fixture/install.json"
            )
            _, install_hash = write_json(install_relative, {
                "info": {
                    "outcome": "success",
                    "commandType": "devicectl.device.install.app",
                },
                "result": {
                    "deviceIdentifier": f"coredevice-{target}",
                    "installedApplications": [{
                        "bundleID": installed_bundle_id,
                        "installationURL": install_url,
                    }],
                },
            })
            installed_relative = (
                f"builds/ios-device-evidence/{target}/fixture/installed-app.json"
            )
            installed_app = {
                "bundleIdentifier": installed_bundle_id,
                "bundleVersion": "2",
                "version": "1.0.1",
                "builtByDeveloper": True,
                "removable": True,
                "url": install_url,
            }
            _, installed_hash = write_json(installed_relative, {
                "info": {
                    "outcome": "success",
                    "commandType": "devicectl.device.info.apps",
                },
                "result": {
                    "deviceIdentifier": f"coredevice-{target}",
                    "matchingBundleIdentifier": installed_bundle_id,
                    "apps": [installed_app],
                },
            })
            installed_identity_hash = digest(json.dumps({
                "bundleIdentifier": installed_app["bundleIdentifier"],
                "bundleVersion": installed_app["bundleVersion"],
                "version": installed_app["version"],
                "url": installed_app["url"],
            }, ensure_ascii=False, separators=(",", ":")).encode())
        else:
            artifact_relative = f"builds/device-evidence/{target}/capture-build.bin"
            artifact = write_bytes(
                artifact_relative, f"artifact:{target}".encode())
        artifact_hash = digest(artifact.read_bytes())
        if platform == "android":
            attestation = {
                "schema": 1,
                "apk_sha256": artifact_hash,
                "runtime_sha256": RUNTIME_HASH,
                "input_sha256": SOURCE_INPUTS,
            }
        else:
            attestation = {
                "schema": 2,
                "artifact_sha256": artifact_hash,
                "production_bundle_id": "com.crossplatformkorea.moonlitbeacon",
                "installed_bundle_id": installed_bundle_id,
                "isolated_capture_bundle": True,
                "content_equivalence": (
                    "same-fresh-exported-pck-production-runtime"
                ),
                "app_tree_sha256": app_tree_hash,
                "executable_sha256": executable_hash,
                "pck_sha256": pck_hash,
                "exported_pck_sha256": pck_hash,
                "runtime_sha256": RUNTIME_HASH,
                "input_sha256": SOURCE_INPUTS,
            }
        attestation_relative = (
            f"builds/ios-device-evidence/{target}/fixture/build-attestation.json"
            if platform == "ios" else
            f"builds/device-evidence/{target}/build-attestation.json"
        )
        _, attestation_hash = write_json(attestation_relative, attestation)
        captures = []
        counter = 0
        for locale in locales:
            for filename in filenames:
                counter += 1
                kind = module.DEVICE_CAPTURE_SCREENSHOT_KINDS[filename]
                source = canonical_source(platform, target, locale, filename)
                evidence = f"builds/device-evidence/{target}/{locale}/{filename}"
                image = png_bytes(
                    f"{target}:{locale}:{filename}",
                    source_width,
                    source_height,
                )
                write_bytes(source, image)
                write_bytes(evidence, image)
                nonce = f"{counter:064x}"
                expected_direct_distribution = platform == "android"
                before = runtime_state(
                    kind, nonce, 10, expected_direct_distribution,
                    viewport_height)
                after = runtime_state(
                    kind, nonce, 11, expected_direct_distribution,
                    viewport_height)
                proof_relative = (
                    f"builds/device-evidence/{target}/{locale}/"
                    f"{filename[:-4]}.proof.json"
                )
                if kind == "missile_core_recovery":
                    missile_before = {"proof": f"before:{target}:{locale}"}
                    missile_after = {"proof": f"after:{target}:{locale}"}
                    proof = {
                        "before": missile_before,
                        "after": missile_after,
                        "runtime_before": before,
                        "runtime_after": after,
                    }
                else:
                    missile_before = None
                    missile_after = None
                    proof = {"before": before, "after": after, "normalized": before}
                write_json(proof_relative, proof)
                capture = {
                    "source": source,
                    "evidence_path": evidence,
                    "proof_path": proof_relative,
                    "asset_locale": locale,
                    "game_locale": module.GAME_LOCALES[locale],
                    "filename": filename,
                    "kind": kind,
                    "runtime_nonce": nonce,
                    "clean_ui_proof": "title-hidden"
                        if kind in ("title", "shrine", "hero_preview")
                        else "combat-hidden",
                    "width": source_width,
                    "height": source_height,
                    "sha256": digest(image),
                    "runtime_before": before,
                    "runtime_after": after,
                    "safe_layout": safe_layout(
                        before, kind, expected_direct_distribution),
                    "physical_safe_layout": physical_layout(
                        source_width, source_height, before),
                }
                if platform == "android":
                    capture["installed_apk_sha256"] = artifact_hash
                else:
                    capture["installed_artifact_sha256"] = artifact_hash
                    capture["installed_identity_sha256"] = installed_identity_hash
                    capture["native_device_framebuffer"] = True
                    if target == "ipad-13":
                        handoff_nonce = digest(
                            f"handoff:{target}:{locale}:{filename}".encode()
                        )
                        process_id = 4000 + counter
                        requested = 1_800_000_000_000 + counter * 1000
                        proof_root = (
                            f"builds/ios-device-evidence/{target}/fixture/"
                            f"handoff-{counter:02d}"
                        )
                        before_details, before_details_hash = write_json(
                            f"{proof_root}-details-before.json",
                            ios_device_details(target, target_contract),
                        )
                        after_details, after_details_hash = write_json(
                            f"{proof_root}-details-after.json",
                            ios_device_details(target, target_contract),
                        )
                        before_processes, before_processes_hash = write_json(
                            f"{proof_root}-processes-before.json",
                            ios_processes(target, process_id),
                        )
                        after_processes, after_processes_hash = write_json(
                            f"{proof_root}-processes-after.json",
                            ios_processes(target, process_id),
                        )
                        activation_launch, activation_launch_hash = write_json(
                            f"{proof_root}-activation-launch.json",
                            ios_activation_launch(target, process_id),
                        )
                        activation_processes, activation_processes_hash = (
                            write_json(
                                f"{proof_root}-activation-processes.json",
                                ios_processes(target, process_id),
                            )
                        )
                        capture.update({
                            "capture_method": (
                                "xcode-devices-take-screenshot-handoff"
                            ),
                            "rsd_host": None,
                            "rsd_port": None,
                            "xcode_handoff_nonce": handoff_nonce,
                            "xcode_handoff_expected_filename": (
                                f"moonlit-{handoff_nonce}.png"
                            ),
                            "xcode_handoff_requested_at": (
                                "2027-01-15T08:00:00.000Z"
                            ),
                            "xcode_handoff_requested_at_unix_ms": requested,
                            "xcode_handoff_birthtime_unix_ms": requested + 10,
                            "xcode_handoff_mtime_unix_ms": requested + 20,
                            "xcode_handoff_accepted_at": (
                                "2027-01-15T08:00:01.000Z"
                            ),
                            "xcode_handoff_process_id": process_id,
                            "xcode_activation_process_id": process_id,
                            "xcode_activation_launch_path": str(
                                activation_launch.relative_to(root)
                            ),
                            "xcode_activation_launch_sha256": (
                                activation_launch_hash
                            ),
                            "xcode_activation_processes_path": str(
                                activation_processes.relative_to(root)
                            ),
                            "xcode_activation_processes_sha256": (
                                activation_processes_hash
                            ),
                            "xcode_handoff_stable_observations": 2,
                            "xcode_handoff_complete_png_decoded": True,
                            "xcode_handoff_device_details_before_path": str(
                                before_details.relative_to(root)
                            ),
                            "xcode_handoff_device_details_before_sha256": (
                                before_details_hash
                            ),
                            "xcode_handoff_processes_before_path": str(
                                before_processes.relative_to(root)
                            ),
                            "xcode_handoff_processes_before_sha256": (
                                before_processes_hash
                            ),
                            "xcode_handoff_device_details_after_path": str(
                                after_details.relative_to(root)
                            ),
                            "xcode_handoff_device_details_after_sha256": (
                                after_details_hash
                            ),
                            "xcode_handoff_processes_after_path": str(
                                after_processes.relative_to(root)
                            ),
                            "xcode_handoff_processes_after_sha256": (
                                after_processes_hash
                            ),
                        })
                        handoff_receipt = {
                            "schema": 1,
                            "protocol": "moonlit-xcode-screenshot-handoff-v1",
                            "nonce": handoff_nonce,
                            "expected_filename": f"moonlit-{handoff_nonce}.png",
                            "partial_filename": (
                                f".moonlit-{handoff_nonce}.png.partial-"
                                f"{handoff_nonce}"
                            ),
                            "png_sha256": digest(image),
                            "png_size": len(image),
                            "source_birthtime_ms": requested + 5,
                            "source_mtime_ms": requested + 6,
                            "final_dev": "42",
                            "final_ino": str(9000 + counter),
                            "final_birthtime_ms": requested + 10,
                            "final_mtime_ms": requested + 20,
                            "file_fsync_before_rename": True,
                            "directory_fsync_after_rename": True,
                            "published_at_ms": requested + 30,
                        }
                        handoff_receipt_bytes = (
                            json.dumps(
                                handoff_receipt,
                                ensure_ascii=False,
                                separators=(",", ":"),
                                sort_keys=True,
                            ) + "\n"
                        ).encode("utf-8")
                        capture["xcode_handoff_receipt"] = handoff_receipt
                        capture["xcode_handoff_receipt_sha256"] = digest(
                            handoff_receipt_bytes
                        )
                    else:
                        capture.update({
                            "capture_method": "pymobiledevice3-dvt-rsd",
                            "rsd_host": "fd00::1",
                            "rsd_port": 12345,
                            "xcode_handoff_nonce": None,
                            "xcode_handoff_expected_filename": None,
                            "xcode_handoff_requested_at": None,
                            "xcode_handoff_requested_at_unix_ms": None,
                            "xcode_handoff_birthtime_unix_ms": None,
                            "xcode_handoff_mtime_unix_ms": None,
                            "xcode_handoff_accepted_at": None,
                            "xcode_handoff_stable_observations": None,
                            "xcode_handoff_complete_png_decoded": None,
                            "xcode_handoff_receipt": None,
                            "xcode_handoff_receipt_sha256": None,
                            "xcode_activation_process_id": None,
                            "xcode_activation_launch_path": None,
                            "xcode_activation_launch_sha256": None,
                            "xcode_activation_processes_path": None,
                            "xcode_activation_processes_sha256": None,
                        })
                if kind == "missile_core_recovery":
                    capture["missile_before"] = missile_before
                    capture["missile_after"] = missile_after
                captures.append(capture)
        canonical_root = f"builds/shots/store-platform/{platform}/{target}"
        report = {
            "schema": 2,
            "platform": platform,
            "target": target,
            "canonical_publish_eligible": True,
            "canonical_root": canonical_root,
            "publication": "timestamp-staging-then-atomic-directory-rename",
            "asset_locales": list(locales),
            "game_locales": [module.GAME_LOCALES[locale] for locale in locales],
            "foreground_verified_at_capture_end": True,
            "source_before_build": snapshot,
            "source_after_build": snapshot,
            "source_before": snapshot,
            "source_after": snapshot,
            "source_byte_equivalent": True,
            "build_attestation": attestation,
            "build_attestation_path": attestation_relative,
            "build_attestation_sha256": attestation_hash,
            "screenshot_size": f"{source_width}x{source_height}",
            "captures": captures,
        }
        if platform == "android":
            gesture_lines = [
                (
                    "InsetsSource id=1 type=systemGestures "
                    f"frame=[0,0][30,{source_height}] visible=true "
                    "flags= sideHint=LEFT"
                ),
                (
                    "InsetsSource id=2 type=mandatorySystemGestures "
                    f"frame=[0,0][{source_width},24] visible=true "
                    "flags= sideHint=TOP"
                ),
                (
                    "InsetsSource id=3 type=systemGestures "
                    f"frame=[{source_width - 30},0]"
                    f"[{source_width},{source_height}] visible=true "
                    "flags= sideHint=RIGHT"
                ),
                (
                    "InsetsSource id=4 type=mandatorySystemGestures "
                    f"frame=[0,{source_height - 32}]"
                    f"[{source_width},{source_height}] visible=true "
                    "flags= sideHint=BOTTOM"
                ),
            ]
            window_dump_relative = (
                f"builds/tablet-evidence/{target}/fixture/"
                "window-displays.txt"
            )
            window_dump = ("\n".join(gesture_lines) + "\n").encode("utf-8")
            write_bytes(window_dump_relative, window_dump)
            config_relative = (
                f"builds/tablet-evidence/{target}/fixture/avd-config.ini"
            )
            config_bytes = avd_config_bytes(target_contract)
            write_bytes(config_relative, config_bytes)
            normalized = module._parse_android_avd_config(
                config_bytes, target)
            normalized_bytes = (
                json.dumps(
                    normalized,
                    ensure_ascii=False,
                    separators=(",", ":"),
                ) + "\n"
            ).encode("utf-8")
            report.update({
                "package": "com.crossplatformkorea.moonlitbeacon",
                "api_level": target_contract["api_level"],
                "avd_name": target_contract["avd_name"],
                "serial": "emulator-5554",
                "avd_config": {
                    "schema": 1,
                    "target": target,
                    "avd_name": target_contract["avd_name"],
                    "normalized": normalized,
                    "source_sha256": digest(config_bytes),
                    "normalized_sha256": digest(normalized_bytes),
                    "evidence_path": config_relative,
                },
                "physical_size": {
                    "width": source_width,
                    "height": source_height,
                    "raw": f"Physical size: {source_width}x{source_height}",
                },
                "density": {
                    "dpi": target_contract["density_dpi"],
                    "raw": (
                        f"Physical density: {target_contract['density_dpi']}"
                    ),
                },
                "window_dump_path": window_dump_relative,
                "window_dump_sha256": digest(window_dump),
                "window_gesture_insets": gesture_lines,
                "model": f"fixture {target}",
                "device": target,
                "build_fingerprint": f"fixture/{target}/36",
                "apk_path": artifact_relative,
                "apk_sha256": artifact_hash,
                "installed_apk_sha256": artifact_hash,
            })
            report.update(persistence_evidence(target))
            attach_persistence_signature(target, report)
        else:
            rsd_identity = {
                "physical_device": True,
                "simulator": False,
                "model_identifier": f"{target_contract['model_prefix']}Fixture1,1",
                "os_version": "26.5",
                "os_build": "23F84",
            }
            rsd_hash = "4" * 64
            rsd_proof_relative = None if target == "ipad-13" else (
                f"builds/ios-device-evidence/{target}/fixture/"
                "rsd-identity-proof.json"
            )
            if rsd_proof_relative is not None:
                write_json(rsd_proof_relative, {
                    "schema": 1,
                    "coredevice_identity_matched": True,
                    "identity": rsd_identity,
                    "raw_json_sha256": rsd_hash,
                })
            details_relative = (
                f"builds/ios-device-evidence/{target}/fixture/device-details.json"
            )
            _, details_hash = write_json(
                details_relative,
                ios_device_details(target, target_contract),
            )
            xcode_method = target == "ipad-13"
            production_listing = {
                "info": {
                    "outcome": "success",
                    "commandType": "devicectl.device.info.apps",
                },
                "result": {
                    "deviceIdentifier": f"coredevice-{target}",
                    "matchingBundleIdentifier": (
                        "com.crossplatformkorea.moonlitbeacon"
                    ),
                    "apps": [],
                },
            }
            production_before_relative = (
                f"builds/ios-device-evidence/{target}/fixture/"
                "production-app-before.json"
            )
            production_after_relative = (
                f"builds/ios-device-evidence/{target}/fixture/"
                "production-app-after.json"
            )
            _, production_before_hash = write_json(
                production_before_relative, production_listing)
            _, production_after_hash = write_json(
                production_after_relative, production_listing)
            final_process_id = (
                captures[-1]["xcode_handoff_process_id"]
                if xcode_method else 6000 + counter
            )
            final_process_relative = (
                f"builds/ios-device-evidence/{target}/fixture/"
                "processes-at-capture-end.json"
            )
            _, final_process_hash = write_json(
                final_process_relative,
                ios_processes(target, final_process_id),
            )
            report.update({
                "bundle_id": "com.crossplatformkorea.moonlitbeacon",
                "installed_capture_bundle_id": (
                    "com.crossplatformkorea.moonlitbeacon.storecapture"
                ),
                "physical_device": True,
                "simulator": False,
                "model_identifier": f"{target_contract['model_prefix']}Fixture1,1",
                "device_udid": f"fixture-{target}",
                "coredevice_identifier": f"coredevice-{target}",
                "device_name": f"Fixture {target}",
                "os_version": "26.5",
                "os_build": "23F84",
                "transport": "localNetwork" if xcode_method else "wired",
                "capture_method": (
                    "xcode-devices-take-screenshot-handoff"
                    if xcode_method else "pymobiledevice3-dvt-rsd"
                ),
                "pymobiledevice3_version": None if xcode_method else "4.1.0",
                "coredevice_device_details_path": details_relative,
                "coredevice_device_details_sha256": details_hash,
                "rsd_host": None if xcode_method else "fd00::1",
                "rsd_port": None if xcode_method else 12345,
                "rsd_endpoint_ephemeral": not xcode_method,
                "rsd_preflight_path": None,
                "rsd_preflight_image_retained": False,
                "rsd_preflight_sha256": None if xcode_method else "5" * 64,
                "rsd_preflight_size": None if xcode_method else {
                    "width": 1616,
                    "height": 720,
                },
                "rsd_identity": None if xcode_method else rsd_identity,
                "rsd_info_raw_sha256": None if xcode_method else rsd_hash,
                "rsd_identity_proof_path": rsd_proof_relative,
                "xcode_screenshot_handoff": {
                    "schema": 2,
                    "first_party_tool": "Xcode Devices and Simulators",
                    "capture_method": (
                        "xcode-devices-take-screenshot-handoff"
                    ),
                    "operator_mediated": True,
                    "inbox_path_persisted": False,
                    "atomic_rename_required": True,
                    "publisher_script": (
                        "scripts/publish-xcode-screenshot-handoff.mjs"
                    ),
                    "complete_png_decode_required": True,
                    "stable_observations_required": 2,
                    "fsync_receipt_required": True,
                    "request_timeout_seconds": 300,
                    "expected_framebuffer": {"width": 2266, "height": 1488},
                } if xcode_method else None,
                "build_artifact_path": artifact_relative,
                "build_artifact_sha256": artifact_hash,
                "installed_artifact_sha256": artifact_hash,
                "install_result_path": install_relative,
                "install_result_sha256": install_hash,
                "installed_app_path": installed_relative,
                "installed_app_sha256": installed_hash,
                "installed_identity_sha256": installed_identity_hash,
                "app_tree_sha256": app_tree_hash,
                "executable_sha256": executable_hash,
                "pck_sha256": pck_hash,
                "exported_pck_sha256": pck_hash,
                "short_version": "1.0.1",
                "build_version": "2",
                "isolated_capture_bundle": True,
                "production_container_accessed": False,
                "isolated_capture_bundle_removed": True,
                "production_app_identity_before": None,
                "production_app_identity_after": None,
                "production_app_identity_unchanged": True,
                "production_app_before_path": production_before_relative,
                "production_app_before_sha256": production_before_hash,
                "production_app_after_path": production_after_relative,
                "production_app_after_sha256": production_after_hash,
                "final_processes_path": final_process_relative,
                "final_processes_sha256": final_process_hash,
                "final_process_id": final_process_id,
                "final_process_executable": (
                    f"file:///private/fixture/{target}/"
                    "MoonlitBeacon.app/MoonlitBeacon"
                ),
            })
            report.update(ios_persistence_evidence())
        save_report(platform, target, report)

def expect_rejected(label, mutation):
    reset_fixture()
    mutation()
    try:
        module._validate_device_capture_reports(entries)
    except RuntimeError:
        return
    raise RuntimeError(f"invalid device capture evidence was accepted: {label}")

def replace_ios_artifact(target, artifact_bytes, content_updates=None):
    report = load_report("ios", target)
    artifact_path = root / report["build_artifact_path"]
    artifact_path.write_bytes(artifact_bytes)
    artifact_hash = digest(artifact_bytes)
    report["build_artifact_sha256"] = artifact_hash
    report["installed_artifact_sha256"] = artifact_hash
    report["build_attestation"]["artifact_sha256"] = artifact_hash
    for capture in report["captures"]:
        capture["installed_artifact_sha256"] = artifact_hash
    for field, value in (content_updates or {}).items():
        report[field] = value
        report["build_attestation"][field] = value
        if field == "pck_sha256":
            report["exported_pck_sha256"] = value
            report["build_attestation"]["exported_pck_sha256"] = value
    _, attestation_hash = write_json(
        report["build_attestation_path"], report["build_attestation"])
    report["build_attestation_sha256"] = attestation_hash
    save_report("ios", target, report)

def rewrite_report_json_evidence(
        report, owner, path_field, hash_field, mutation):
    path = root / owner[path_field]
    payload = json.loads(path.read_text())
    mutation(payload)
    data = (
        json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n"
    ).encode()
    path.write_bytes(data)
    owner[hash_field] = digest(data)
    return payload

reset_fixture()
module._validate_device_capture_reports(entries)

def retime_xcode_handoff(capture, requested):
    capture["xcode_handoff_requested_at_unix_ms"] = requested
    capture["xcode_handoff_birthtime_unix_ms"] = requested + 10
    capture["xcode_handoff_mtime_unix_ms"] = requested + 20
    receipt = capture["xcode_handoff_receipt"]
    receipt["source_birthtime_ms"] = requested + 5
    receipt["source_mtime_ms"] = requested + 6
    receipt["final_birthtime_ms"] = requested + 10
    receipt["final_mtime_ms"] = requested + 20
    receipt["published_at_ms"] = requested + 30
    receipt_bytes = (
        json.dumps(
            receipt,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ) + "\n"
    ).encode("utf-8")
    capture["xcode_handoff_receipt_sha256"] = digest(receipt_bytes)

def accept_xcode_capture_order_independent_of_manifest_order():
    report = load_report("ios", "ipad-13")
    latest = report["captures"][0]
    requested = max(
        capture["xcode_handoff_requested_at_unix_ms"]
        for capture in report["captures"]
    ) + 1000
    retime_xcode_handoff(latest, requested)
    final_process_id = latest["xcode_handoff_process_id"]
    _, final_process_hash = write_json(
        report["final_processes_path"],
        ios_processes("ipad-13", final_process_id),
    )
    report["final_process_id"] = final_process_id
    report["final_processes_sha256"] = final_process_hash
    save_report("ios", "ipad-13", report)

accept_xcode_capture_order_independent_of_manifest_order()
module._validate_device_capture_reports(entries)

def duplicate_xcode_requested_at():
    report = load_report("ios", "ipad-13")
    retime_xcode_handoff(
        report["captures"][0],
        report["captures"][1]["xcode_handoff_requested_at_unix_ms"],
    )
    save_report("ios", "ipad-13", report)
expect_rejected("duplicate Xcode requested_at", duplicate_xcode_requested_at)

expect_rejected("missing report", lambda: report_path("ios", "ipad-13").unlink())

def stale_source():
    report = load_report("ios", "ipad-13")
    report["source_after"] = dict(report["source_after"])
    report["source_after"]["runtime_sha256"] = "f" * 64
    save_report("ios", "ipad-13", report)
expect_rejected("stale source", stale_source)

def tampered_png():
    path = root / canonical_source(
        "android", "seven-inch-tablet", "en-US", filenames[0])
    path.write_bytes(path.read_bytes() + b"tampered")
expect_rejected("tampered canonical PNG", tampered_png)

def wrong_device_report():
    report = load_report("android", "ten-inch-tablet")
    report["target"] = "seven-inch-tablet"
    save_report("android", "ten-inch-tablet", report)
expect_rejected("wrong target", wrong_device_report)

def wrong_locale_kind_path():
    report = load_report("ios", "iphone-6.5")
    report["captures"][0]["asset_locale"] = "ko-KR"
    report["captures"][0]["kind"] = "title"
    report["captures"][0]["source"] = report["captures"][1]["source"]
    save_report("ios", "iphone-6.5", report)
expect_rejected("wrong locale kind path", wrong_locale_kind_path)

def forged_rsd_identity():
    report = load_report("ios", "iphone-6.5")
    report["rsd_identity"]["model_identifier"] = "iPadFixture1,1"
    save_report("ios", "iphone-6.5", report)
expect_rejected("forged RSD identity", forged_rsd_identity)

def forged_xcode_rsd_identity():
    report = load_report("ios", "ipad-13")
    report["rsd_identity"] = {
        "physical_device": True,
        "simulator": False,
        "model_identifier": report["model_identifier"],
        "os_version": report["os_version"],
        "os_build": report["os_build"],
    }
    save_report("ios", "ipad-13", report)
expect_rejected("forged Xcode RSD identity", forged_xcode_rsd_identity)

def mismatched_ios_after_hash():
    report = load_report("ios", "ipad-13")
    report["persistent_data_sha256_after"]["settings.cfg"] = "a" * 64
    save_report("ios", "ipad-13", report)
expect_rejected("mismatched iOS after hash", mismatched_ios_after_hash)

def nonempty_ios_mutations():
    report = load_report("ios", "ipad-13")
    report["persistent_data_mutated_during_capture"] = ["settings.cfg"]
    save_report("ios", "ipad-13", report)
expect_rejected("nonempty iOS mutations", nonempty_ios_mutations)

def mismatched_ios_settings():
    report = load_report("ios", "ipad-13")
    report["settings_restore"]["observed_sha256"] = "b" * 64
    save_report("ios", "ipad-13", report)
expect_rejected("mismatched iOS settings restore", mismatched_ios_settings)

def false_ios_restore_flag():
    report = load_report("ios", "ipad-13")
    report["persistent_data_restored_byte_exact"] = False
    save_report("ios", "ipad-13", report)
expect_rejected("false iOS restore flag", false_ios_restore_flag)

def false_ios_isolated_cleanup():
    report = load_report("ios", "ipad-13")
    report["isolated_capture_bundle_removed"] = False
    save_report("ios", "ipad-13", report)
expect_rejected("false iOS isolated cleanup", false_ios_isolated_cleanup)

def nonisolated_rsd_capture():
    report = load_report("ios", "iphone-6.5")
    report["isolated_capture_bundle"] = False
    report["production_container_accessed"] = True
    save_report("ios", "iphone-6.5", report)
expect_rejected("non-isolated RSD capture", nonisolated_rsd_capture)

def nonnull_xcode_persistence():
    report = load_report("ios", "ipad-13")
    value = "9" * 64
    for field in (
        "persistent_data_sha256_before",
        "persistent_data_sha256_after",
        "persistent_data_sha256_restored",
    ):
        report[field]["settings.cfg"] = value
    report["settings_restore"] = {
        "original_present": True,
        "original_sha256": value,
        "observed_sha256": value,
        "restored_sha256": value,
        "byte_exact": True,
    }
    save_report("ios", "ipad-13", report)
expect_rejected("nonnull Xcode isolated persistence", nonnull_xcode_persistence)

def extra_xcode_persistence_file():
    report = load_report("ios", "ipad-13")
    report["persistent_data_files"].append("zz-future.cfg")
    for field in (
        "persistent_data_sha256_before",
        "persistent_data_sha256_after",
        "persistent_data_sha256_restored",
    ):
        report[field]["zz-future.cfg"] = None
    save_report("ios", "ipad-13", report)
expect_rejected("extra Xcode isolated persistence", extra_xcode_persistence_file)

def traversal_ios_zip():
    artifact, _ = ios_app_zip(
        "ipad-13",
        "com.crossplatformkorea.moonlitbeacon.storecapture",
        extra_entry="../escape",
    )
    replace_ios_artifact("ipad-13", artifact)
expect_rejected("iOS ZIP traversal", traversal_ios_zip)

def wrong_bundle_inside_ios_zip():
    artifact, hashes = ios_app_zip(
        "ipad-13", "com.crossplatformkorea.moonlitbeacon")
    replace_ios_artifact("ipad-13", artifact, {
        "app_tree_sha256": hashes["app_tree_sha256"],
    })
expect_rejected("iOS ZIP inner bundle", wrong_bundle_inside_ios_zip)

def changed_ios_executable():
    artifact, hashes = ios_app_zip(
        "ipad-13",
        "com.crossplatformkorea.moonlitbeacon.storecapture",
        executable_suffix=b":changed",
    )
    replace_ios_artifact("ipad-13", artifact, {
        "app_tree_sha256": hashes["app_tree_sha256"],
    })
expect_rejected("iOS ZIP executable bytes", changed_ios_executable)

def changed_ios_pck():
    artifact, hashes = ios_app_zip(
        "ipad-13",
        "com.crossplatformkorea.moonlitbeacon.storecapture",
        pck_suffix=b":changed",
    )
    replace_ios_artifact("ipad-13", artifact, {
        "app_tree_sha256": hashes["app_tree_sha256"],
    })
expect_rejected("iOS ZIP PCK bytes", changed_ios_pck)

def changed_ios_resource_mode():
    artifact, _ = ios_app_zip(
        "ipad-13",
        "com.crossplatformkorea.moonlitbeacon.storecapture",
        resource_mode=0o600,
    )
    replace_ios_artifact("ipad-13", artifact)
expect_rejected("iOS ZIP app-tree mode", changed_ios_resource_mode)

def missing_ios_install_receipt():
    report = load_report("ios", "ipad-13")
    (root / report["install_result_path"]).unlink()
expect_rejected("missing iOS install receipt", missing_ios_install_receipt)

def wrong_ios_installed_version():
    report = load_report("ios", "ipad-13")
    path = root / report["installed_app_path"]
    receipt = json.loads(path.read_text())
    receipt["result"]["apps"][0]["version"] = "9.9.9"
    receipt_bytes = (
        json.dumps(receipt, ensure_ascii=False, sort_keys=True) + "\n"
    ).encode()
    path.write_bytes(receipt_bytes)
    report["installed_app_sha256"] = digest(receipt_bytes)
    save_report("ios", "ipad-13", report)
expect_rejected("wrong iOS installed version", wrong_ios_installed_version)

def reused_xcode_handoff_nonce():
    report = load_report("ios", "ipad-13")
    first = report["captures"][0]
    second = report["captures"][1]
    second["xcode_handoff_nonce"] = first["xcode_handoff_nonce"]
    second["xcode_handoff_expected_filename"] = (
        first["xcode_handoff_expected_filename"]
    )
    save_report("ios", "ipad-13", report)
expect_rejected("reused Xcode handoff nonce", reused_xcode_handoff_nonce)

def mismatched_xcode_activation_pid():
    report = load_report("ios", "ipad-13")
    report["captures"][0]["xcode_activation_process_id"] += 1
    save_report("ios", "ipad-13", report)
expect_rejected(
    "mismatched Xcode activation PID", mismatched_xcode_activation_pid)

def traversal_xcode_activation_launch():
    report = load_report("ios", "ipad-13")
    report["captures"][0]["xcode_activation_launch_path"] = "../launch.json"
    save_report("ios", "ipad-13", report)
expect_rejected(
    "traversal Xcode activation launch path", traversal_xcode_activation_launch)

def mismatched_xcode_activation_launch_hash():
    report = load_report("ios", "ipad-13")
    report["captures"][0]["xcode_activation_launch_sha256"] = "0" * 64
    save_report("ios", "ipad-13", report)
expect_rejected(
    "mismatched Xcode activation launch hash",
    mismatched_xcode_activation_launch_hash,
)

def reject_activation_launch_mutation(label, mutation):
    def apply_mutation():
        report = load_report("ios", "ipad-13")
        capture = report["captures"][0]
        rewrite_report_json_evidence(
            report,
            capture,
            "xcode_activation_launch_path",
            "xcode_activation_launch_sha256",
            mutation,
        )
        save_report("ios", "ipad-13", report)
    expect_rejected(label, apply_mutation)

activation_launch_mutations = (
    (
        "wrong Xcode activation device",
        lambda value: value["result"].__setitem__(
            "deviceIdentifier", "other-device"),
    ),
    (
        "wrong Xcode activation command",
        lambda value: value["info"].__setitem__(
            "commandType", "devicectl.device.process.terminate"),
    ),
    (
        "wrong Xcode activation receipt PID",
        lambda value: value["result"]["process"].__setitem__(
            "processIdentifier", 9999),
    ),
    (
        "wrong Xcode activation executable",
        lambda value: value["result"]["process"].__setitem__(
            "executable",
            "file:///private/fixture/production/"
            "MoonlitBeacon.app/MoonlitBeacon",
        ),
    ),
    (
        "non-activated Xcode launch",
        lambda value: value["result"]["launchOptions"].__setitem__(
            "activatedWhenStarted", False),
    ),
    (
        "terminating Xcode activation launch",
        lambda value: value["result"]["launchOptions"].__setitem__(
            "terminateExistingInstances", True),
    ),
    (
        "stopped Xcode activation launch",
        lambda value: value["result"]["launchOptions"].__setitem__(
            "startStopped", True),
    ),
    (
        "argument-bearing Xcode activation launch",
        lambda value: value["result"]["launchOptions"].__setitem__(
            "arguments", ["--time-scale", "0.2"]),
    ),
)
for activation_label, activation_mutation in activation_launch_mutations:
    reject_activation_launch_mutation(activation_label, activation_mutation)

def competing_xcode_activation_process():
    report = load_report("ios", "ipad-13")
    capture = report["captures"][0]
    def add_competitor(value):
        value["result"]["runningProcesses"].append({
            "executable": (
                "file:///private/fixture/production/"
                "MoonlitBeacon.app/MoonlitBeacon"
            ),
            "processIdentifier": 9999,
        })
    rewrite_report_json_evidence(
        report,
        capture,
        "xcode_activation_processes_path",
        "xcode_activation_processes_sha256",
        add_competitor,
    )
    save_report("ios", "ipad-13", report)
expect_rejected(
    "competing Xcode activation process", competing_xcode_activation_process)

def mismatched_final_process_hash():
    report = load_report("ios", "ipad-13")
    report["final_processes_sha256"] = "0" * 64
    save_report("ios", "ipad-13", report)
expect_rejected("mismatched final process hash", mismatched_final_process_hash)

def competing_final_process():
    report = load_report("ios", "ipad-13")
    def add_competitor(value):
        value["result"]["runningProcesses"].append({
            "executable": (
                "file:///private/fixture/production/"
                "MoonlitBeacon.app/MoonlitBeacon"
            ),
            "processIdentifier": 9999,
        })
    rewrite_report_json_evidence(
        report,
        report,
        "final_processes_path",
        "final_processes_sha256",
        add_competitor,
    )
    save_report("ios", "ipad-13", report)
expect_rejected("competing final process", competing_final_process)

def wrong_final_process_executable():
    report = load_report("ios", "ipad-13")
    rewrite_report_json_evidence(
        report,
        report,
        "final_processes_path",
        "final_processes_sha256",
        lambda value: value["result"]["runningProcesses"][0].__setitem__(
            "executable",
            "file:///private/fixture/production/"
            "MoonlitBeacon.app/MoonlitBeacon",
        ),
    )
    save_report("ios", "ipad-13", report)
expect_rejected("wrong final process executable", wrong_final_process_executable)

def wrong_final_process_executable_field():
    report = load_report("ios", "ipad-13")
    report["final_process_executable"] = (
        "file:///private/fixture/production/"
        "MoonlitBeacon.app/MoonlitBeacon"
    )
    save_report("ios", "ipad-13", report)
expect_rejected(
    "wrong final process executable field",
    wrong_final_process_executable_field,
)

def final_process_not_last_capture():
    report = load_report("ios", "ipad-13")
    new_pid = report["final_process_id"] + 1
    report["final_process_id"] = new_pid
    rewrite_report_json_evidence(
        report,
        report,
        "final_processes_path",
        "final_processes_sha256",
        lambda value: value["result"]["runningProcesses"][0].__setitem__(
            "processIdentifier", new_pid),
    )
    save_report("ios", "ipad-13", report)
expect_rejected("final process is not last capture", final_process_not_last_capture)

def tampered_attestation():
    report = load_report("android", "seven-inch-tablet")
    path = root / report["build_attestation_path"]
    path.write_bytes(path.read_bytes() + b"tampered")
expect_rejected("tampered build attestation", tampered_attestation)

def cross_device_reuse():
    source_bytes = (root / canonical_source(
        "ios", "iphone-6.5", "en-US", filenames[0])).read_bytes()
    report = load_report("ios", "ipad-13")
    capture = report["captures"][0]
    (root / capture["source"]).write_bytes(source_bytes)
    (root / capture["evidence_path"]).write_bytes(source_bytes)
    capture["sha256"] = digest(source_bytes)
    save_report("ios", "ipad-13", report)
expect_rejected("cross-device PNG reuse", cross_device_reuse)

def phone_reuse():
    phone = root / entries[0]["localized_sources"]["en-US"]
    report = load_report("android", "seven-inch-tablet")
    capture = report["captures"][0]
    image = phone.read_bytes()
    (root / capture["source"]).write_bytes(image)
    (root / capture["evidence_path"]).write_bytes(image)
    capture["sha256"] = digest(image)
    save_report("android", "seven-inch-tablet", report)
expect_rejected("Pixel phone PNG reuse", phone_reuse)

def missing_physical_proof():
    report = load_report("android", "seven-inch-tablet")
    report["captures"][0].pop("physical_safe_layout")
    save_report("android", "seven-inch-tablet", report)
expect_rejected("missing physical safe proof", missing_physical_proof)

def forged_physical_proof():
    report = load_report("android", "seven-inch-tablet")
    report["captures"][0]["physical_safe_layout"]["physical_insets"]["left"] = 999
    save_report("android", "seven-inch-tablet", report)
expect_rejected("forged physical safe proof", forged_physical_proof)

def wrong_tablet_physical_size():
    report = load_report("android", "seven-inch-tablet")
    report["physical_size"] = {
        "width": 1280,
        "height": 800,
        "raw": "Physical size: 1280x800",
    }
    save_report("android", "seven-inch-tablet", report)
expect_rejected("wrong tablet physical size", wrong_tablet_physical_size)

def wrong_tablet_density():
    report = load_report("android", "ten-inch-tablet")
    report["density"] = {"dpi": 240, "raw": "Physical density: 240"}
    save_report("android", "ten-inch-tablet", report)
expect_rejected("wrong tablet density", wrong_tablet_density)

def missing_persistence_field():
    report = load_report("android", "seven-inch-tablet")
    report.pop("persistent_data_files")
    save_report("android", "seven-inch-tablet", report)
expect_rejected("missing persistence list", missing_persistence_field)

def extra_persistence_file():
    report = load_report("android", "seven-inch-tablet")
    report["persistent_data_files"].append("unexpected.cfg")
    save_report("android", "seven-inch-tablet", report)
expect_rejected("extra persistence file", extra_persistence_file)

def mismatched_restored_hash():
    report = load_report("android", "seven-inch-tablet")
    report["persistent_data_sha256_restored"]["settings.cfg"] = "8" * 64
    save_report("android", "seven-inch-tablet", report)
expect_rejected("mismatched restored hash", mismatched_restored_hash)

def false_restore_flag():
    report = load_report("android", "seven-inch-tablet")
    report["persistent_data_restored_byte_exact"] = False
    save_report("android", "seven-inch-tablet", report)
expect_rejected("false persistence restore flag", false_restore_flag)

def false_mutation_flag():
    report = load_report("android", "seven-inch-tablet")
    report["persistent_data_mutated_during_capture"] = False
    save_report("android", "seven-inch-tablet", report)
expect_rejected("false persistence mutation flag", false_mutation_flag)

def mismatched_settings_restore():
    report = load_report("android", "seven-inch-tablet")
    report["settings_restore"]["restored_sha256"] = "9" * 64
    save_report("android", "seven-inch-tablet", report)
expect_rejected("mismatched settings restore", mismatched_settings_restore)

def tampered_avd_config_bytes():
    report = load_report("android", "seven-inch-tablet")
    path = root / report["avd_config"]["evidence_path"]
    path.write_bytes(path.read_bytes() + b"tampered=true\n")
expect_rejected("tampered AVD config bytes", tampered_avd_config_bytes)

def forged_avd_semantics(field, old, new):
    def mutate():
        report = load_report("android", "seven-inch-tablet")
        proof = report["avd_config"]
        path = root / proof["evidence_path"]
        changed = path.read_bytes().decode("utf-8").replace(old, new).encode()
        path.write_bytes(changed)
        normalized = module._parse_android_avd_config(changed, field)
        normalized_bytes = (
            json.dumps(
                normalized,
                ensure_ascii=False,
                separators=(",", ":"),
            ) + "\n"
        ).encode()
        proof["normalized"] = normalized
        proof["source_sha256"] = digest(changed)
        proof["normalized_sha256"] = digest(normalized_bytes)
        save_report("android", "seven-inch-tablet", report)
    return mutate

for field, old, new in (
    ("abi", "arm64-v8a", "x86_64"),
    ("image", "google_apis_playstore", "google_apis"),
    ("device", "7in WSVGA (Tablet)", "pixel_9"),
):
    expect_rejected(
        f"forged AVD {field}",
        forged_avd_semantics(field, old, new),
    )

def tampered_window_dump():
    report = load_report("android", "seven-inch-tablet")
    path = root / report["window_dump_path"]
    path.write_bytes(path.read_bytes() + b"tampered\n")
expect_rejected("tampered window dump", tampered_window_dump)

def wrong_window_gesture_frame():
    report = load_report("android", "seven-inch-tablet")
    lines = [
        line.replace("frame=[0,0][30,600]", "frame=[0,0][31,600]")
        for line in report["window_gesture_insets"]
    ]
    window_dump = ("\n".join(lines) + "\n").encode("utf-8")
    write_bytes(report["window_dump_path"], window_dump)
    report["window_dump_sha256"] = digest(window_dump)
    report["window_gesture_insets"] = lines
    save_report("android", "seven-inch-tablet", report)
expect_rejected("wrong window gesture frame", wrong_window_gesture_frame)

def symlinked_window_dump():
    report = load_report("android", "seven-inch-tablet")
    path = root / report["window_dump_path"]
    target = root / report["apk_path"]
    path.unlink()
    path.symlink_to(target)
expect_rejected("symlinked window dump", symlinked_window_dump)

def thirty_three_pixel_inset():
    report = load_report("android", "seven-inch-tablet")
    capture = report["captures"][0]
    width = capture["width"]
    height = capture["height"]
    viewport = capture["runtime_before"]["viewport_rect"]
    logical_x = 33.0 / (width / viewport[2])
    logical_y = 33.0 / (height / viewport[3])
    safe = [
        logical_x,
        logical_y,
        viewport[2] - 2.0 * logical_x,
        viewport[3] - 2.0 * logical_y,
    ]
    for state_field in ("runtime_before", "runtime_after"):
        capture[state_field]["safe_rect"] = safe
    capture["safe_layout"]["safe_rect"] = safe
    capture["safe_layout"]["logical_insets"] = {
        "left": logical_x,
        "top": logical_y,
        "right": logical_x,
        "bottom": logical_y,
    }
    capture["physical_safe_layout"] = physical_layout(
        width, height, capture["runtime_before"])
    proof = {
        "before": capture["runtime_before"],
        "after": capture["runtime_after"],
        "normalized": capture["runtime_before"],
    }
    write_json(capture["proof_path"], proof)
    save_report("android", "seven-inch-tablet", report)
expect_rejected("33px physical inset", thirty_three_pixel_inset)
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        root,
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Play tablets render each Android tablet device source with aspect ratio preserved', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-store-tablet-contract-'));
  try {
    const source = join(root, 'android-source.png');
    writeFileSync(source, 'source placeholder');
    const probe = `
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("store_graphics_tablet", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = Path(sys.argv[2])
module.PLAY_SCREENSHOT_OUTPUT = Path(sys.argv[3])
module._entry_source = lambda entry, locale, device=None: source
module._png_size = lambda path: (2424, 1080)
calls = []
module._run_screenshot_render = lambda ffmpeg, input_path, output, graph: calls.append({
    "input": str(input_path), "output": str(output), "graph": graph})
module._validate_screenshot_file = lambda *args: None
for device, target in module.PLAY_TABLET_FORMATS.items():
    module._render_play_tablet_screenshot(
        "ffmpeg", "", Path("."), {"output": "01.png"}, 1,
        "ko-KR", device, target, Path(sys.argv[3]))
print(json.dumps({
    "formats": module.PLAY_TABLET_FORMATS,
    "calls": calls,
}, sort_keys=True))
`;
    const result = spawnSync(
      process.execPath,
      [
        'scripts/python.mjs',
        '-B',
        '-c',
        probe,
        resolve('apps/game/tools/build_store_graphics.py'),
        source,
        join(root, 'release-play'),
      ],
      { cwd: resolve('.'), encoding: 'utf8' },
    );
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const payload = JSON.parse(result.stdout.trim().split('\n').at(-1));
    assert.deepEqual(payload.formats, {
      'seven-inch-tablet': { size: [1920, 1080] },
      'ten-inch-tablet': { size: [2560, 1440] },
    });
    assert.equal(payload.calls.length, 2);
    for (const call of payload.calls) {
      assert.equal(call.input, source);
      assert.match(call.output, /\/(?:seven|ten)-inch-tablet\/01\.png$/u);
      assert.match(call.graph, /^split=2\[background\]\[foreground\];/u);
      assert.match(call.graph, /\[foreground\]scale=\d+:\d+:flags=lanczos\[game\]/u);
      assert.doesNotMatch(call.graph, /drawbox|pad=|label|brand/u);
      assert.equal((call.graph.match(/crop=/gu) ?? []).length, 1);
      assert.match(call.graph, /\[backdrop\]\[game\]overlay=/u);
    }
    assert.match(payload.calls[0].graph, /\[foreground\]scale=1920:854:/u);
    assert.match(payload.calls[1].graph, /\[foreground\]scale=2560:1140:/u);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
