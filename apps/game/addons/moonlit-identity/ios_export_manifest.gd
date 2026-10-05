extends RefCounted

## Computes the exact iOS export registration for the MoonlitIdentity
## bridge: staged Firebase frameworks, staged privacy bundles, required
## system frameworks, and linker flags.
##
## The system set and `-lz` are measured, not guessed: `nm -u` over the
## real built static frameworks shows FirebaseAuth referencing GameKit,
## SafariServices, WebKit and Security, GoogleUtilities referencing
## CoreTelephony, SystemConfiguration, Security and zlib, GTMSessionFetcher
## referencing Security — and a real arm64 link probe only succeeds with
## exactly this set plus `-ObjC`. The bridge itself uses
## AuthenticationServices for the Apple sheet.
##
## Pure static functions over staging directories, so tests exercise the
## exact registration inputs without running an export. The export plugin
## calls these and forwards each result to the matching verified
## `add_ios_*` hook; dropping any item here fails the focused tests.

const ENTRY_SYMBOL: String = "moonlit_identity_ios_entry"

## Preferred C++ injection hooks, modern first. The export plugin probes
## these with `has_method` and forwards the registration snippet to the
## first one the running engine offers.
const CPP_CODE_HOOKS: Array[String] = [
	"add_apple_embedded_platform_cpp_code",
	"add_ios_cpp_code",
]

## Preferred Info.plist injection hooks, modern first. Same probing: the
## GoogleSignIn callback URL scheme rides the first hook the engine offers.
const PLIST_CONTENT_HOOKS: Array[String] = [
	"add_apple_embedded_platform_plist_content",
	"add_ios_plist_content",
]

const SYSTEM_FRAMEWORKS: Array[String] = [
	"AuthenticationServices",
	"CoreTelephony",
	"GameKit",
	"SafariServices",
	"Security",
	"SystemConfiguration",
	"WebKit",
]
const LINKER_FLAGS: String = "-ObjC -lz"
const PRIVACY_MANIFEST_FILE: String = "PrivacyInfo.xcprivacy"
## Mirrors IDENTITY_REQUIRED_PRIVACY_BUNDLES in
## scripts/lib/player-identity-build.mjs: the six Firebase entries plus the
## GoogleSignIn 7.1.0 closure's three measured bundles (AppAuthCore and
## GTMAppAuth manifests, GoogleSignIn's resource bundle with its manifest
## and button assets), identical in both real config roots.
const REQUIRED_BUNDLES: Array[String] = [
	"FirebaseAuth_Privacy.bundle",
	"FirebaseCore_Privacy.bundle",
	"FirebaseCoreExtension_Privacy.bundle",
	"FirebaseCoreInternal_Privacy.bundle",
	"GTMSessionFetcher_Core_Privacy.bundle",
	"GoogleUtilities_Privacy.bundle",
	"AppAuthCore_Privacy.bundle",
	"GTMAppAuth_Privacy.bundle",
	"GoogleSignIn.bundle",
]


## Bare `X.framework` names, linked by the exporter without copying.
static func system_frameworks() -> PackedStringArray:
	var frameworks: PackedStringArray = PackedStringArray()
	for name in SYSTEM_FRAMEWORKS:
		frameworks.append(name + ".framework")
	return frameworks


static func linker_flags() -> String:
	return LINKER_FLAGS


## Namespace-scope C++ retaining and registering the statically linked entry.
##
## The `.a` is linked into the app, but the linker only pulls archive
## members that something references: with no reference, the entry never
## reaches the executable and the engine cannot resolve the extension,
## no matter what the archive itself contains. The export template
## places this whole-source text at namespace scope in dummy.cpp, so it
## must be complete declarations plus a callback queue: the constructor
## below registers only an engine init callback at startup, and the
## engine runs that callback from the OS_AppleEmbedded constructor, after
## the dynamic-symbol map exists and before extension lookup, where writing
## the entry address into the symbol table is safe. The entry itself is
## never called here. Empty when the static library is absent, so an
## export without native sign-in stays a clean graceful degradation
## instead of gaining an undefined reference.
static func registration_cpp_code(static_lib_path: String) -> String:
	if static_lib_path.is_empty() or not FileAccess.file_exists(
			static_lib_path):
		return ""
	var lines: Array[String] = [
		"// MoonlitIdentity static entry: retain the archive member in",
		"// the link and register it with the engine. Namespace-scope",
		"// code for the exporter-generated dummy.cpp. The constructor",
		"// below only queues a callback; the engine runs it from",
		"// the OS_AppleEmbedded constructor, after the",
		"// dynamic-symbol map exists. The entry itself is never",
		"// called here. (void *, void *, void *) stands in for the",
		"// godot typedefs; only the address is taken.",
		"extern \"C\" unsigned char %s(void *, void *, void *);"
		% ENTRY_SYMBOL,
		"extern void register_dynamic_symbol(char *, void *);",
		"extern void add_apple_embedded_platform_init_callback(void (*)());",
		"static void moonlit_identity_register_entry() {",
		"\tregister_dynamic_symbol((char *)\"%s\", (void *)&%s);"
		% [ENTRY_SYMBOL, ENTRY_SYMBOL],
		"}",
		"namespace {",
		"struct MoonlitIdentityInitRegistrar {",
		"\tMoonlitIdentityInitRegistrar() {",
		"\t\tadd_apple_embedded_platform_init_callback(moonlit_identity_register_entry);",
		"\t}",
		"};",
		"static MoonlitIdentityInitRegistrar moonlit_identity_init_registrar;",
		"}",
	]
	return "\n".join(lines) + "\n"


## First preferred C++ hook present in `available_hooks`, else "".
static func select_cpp_code_hook(available_hooks: Array) -> String:
	for hook in CPP_CODE_HOOKS:
		if available_hooks.has(hook):
			return hook
	return ""


## First preferred plist hook present in `available_hooks`, else "".
static func select_plist_content_hook(available_hooks: Array) -> String:
	for hook in PLIST_CONTENT_HOOKS:
		if available_hooks.has(hook):
			return hook
	return ""


## The GoogleSignIn callback URL scheme for the staged iOS client id.
##
## Google's reversed client id is the dotted client-id parts in reverse
## (`1234-abcd.apps.googleusercontent.com` becomes
## `com.googleusercontent.apps.1234-abcd`), registered as a
## `CFBundleURLSchemes` entry so the OAuth callback returns to the app.
## Empty when the staged config names no well-formed iOS client id, in
## which case the export stamps no scheme and Google sign-in reports
## `not_configured` at runtime instead of failing in the browser.
static func google_url_scheme(config_path: String) -> String:
	var client_id: String = read_ios_client_id(config_path)
	if client_id.is_empty():
		return ""
	var parts: PackedStringArray = client_id.split(".")
	parts.reverse()
	return ".".join(parts)


## The staged `[google] ios_client_id`, or "" when absent or malformed.
## A Google OAuth client id ends in `.apps.googleusercontent.com`; anything
## else is a paste of the wrong value and stamps nothing.
static func read_ios_client_id(config_path: String) -> String:
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		return ""
	var config: ConfigFile = ConfigFile.new()
	if config.load(config_path) != OK:
		return ""
	var raw: Variant = config.get_value("google", "ios_client_id", "")
	if typeof(raw) != TYPE_STRING:
		return ""
	var client_id: String = str(raw).strip_edges()
	var pattern: RegEx = RegEx.new()
	if pattern.compile(
			"^[0-9]+-[A-Za-z0-9_-]+\\.apps\\.googleusercontent\\.com$"
			) != OK:
		return ""
	if pattern.search(client_id) == null:
		return ""
	return client_id


## Info.plist fragment registering the GoogleSignIn callback scheme.
## Empty when no scheme derives from the staged config, so a Google-less
## export gains no URL type and stays a clean graceful degradation.
static func plist_url_types_content(config_path: String) -> String:
	var scheme: String = google_url_scheme(config_path)
	if scheme.is_empty():
		return ""
	var lines: Array[String] = [
		"<key>CFBundleURLTypes</key>",
		"<array>",
		"\t<dict>",
		"\t\t<key>CFBundleURLName</key>",
		"\t\t<string>com.moonlitbeacon.google-signin</string>",
		"\t\t<key>CFBundleURLSchemes</key>",
		"\t\t<array>",
		"\t\t\t<string>%s</string>" % scheme,
		"\t\t</array>",
		"\t</dict>",
		"</array>",
	]
	return "\n".join(lines) + "\n"


## Sorted full paths of every `*.framework` staged under `frameworks_dir`.
static func framework_paths(frameworks_dir: String) -> PackedStringArray:
	return _child_paths(frameworks_dir, ".framework")


## Sorted full paths of every `*.bundle` staged under `resources_dir`.
static func resource_bundle_paths(resources_dir: String) -> PackedStringArray:
	return _child_paths(resources_dir, ".bundle")


## Required bundle names absent from `resources_dir`, sorted.
static func missing_required_bundles(resources_dir: String) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var staged: Dictionary = {}
	for path in resource_bundle_paths(resources_dir):
		staged[path.get_file()] = true
	for name in REQUIRED_BUNDLES:
		if not staged.has(name):
			missing.append(name)
	missing.sort()
	return missing


## True when the staged bundle carries its untouched SDK manifest.
static func bundle_has_manifest(bundle_dir: String) -> bool:
	return FileAccess.file_exists(
		bundle_dir + "/" + PRIVACY_MANIFEST_FILE)


static func _child_paths(parent_dir: String, suffix: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if parent_dir.is_empty() or not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(parent_dir)):
		return found
	for entry in DirAccess.get_directories_at(parent_dir):
		if entry.ends_with(suffix):
			found.append(parent_dir + "/" + entry)
	found.sort()
	return found
