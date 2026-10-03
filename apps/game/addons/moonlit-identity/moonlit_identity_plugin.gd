@tool
extends EditorPlugin

## Editor side of the MoonlitIdentity native bridge.
##
## Registers the `MoonlitIdentity` autoload (the GDScript wrapper in
## `moonlit_identity.gd`) when the project did not register it explicitly,
## and validates the native export pieces: the Android
## AARs plus Maven dependencies from the `.gdap` manifest, and the iOS
## GDExtension descriptor plus its compiled library. Public client identifiers
## come from `res://moonlit_identity.cfg`, which the
## `scripts/build-player-identity.mjs` tool writes at build time from ignored
## configuration; this plugin stages that file into the export when it is
## present and only reports its presence, never its values.

const AUTOLOAD_NAME: String = "MoonlitIdentity"
const AUTOLOAD_PATH: String = "res://addons/moonlit-identity/moonlit_identity.gd"

var _export_plugin: MoonlitIdentityExportPlugin
var _added_autoload: bool = false


func _enter_tree() -> void:
	# The game registers the bridge autoload explicitly in project.godot, so
	# the runtime never depends on editor state. Only add it when a project
	# enabled this addon without that registration; adding unconditionally
	# would mark explicit settings dirty on every editor start.
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		_added_autoload = true
	if _export_plugin == null:
		_export_plugin = MoonlitIdentityExportPlugin.new()
		add_export_plugin(_export_plugin)
	print("[MoonlitIdentity] Plugin enabled")


func _exit_tree() -> void:
	# Only retire the autoload this enable added. An explicit project
	# registration (or one added by an earlier enable) stays untouched, so
	# disabling the addon or closing the editor can never strip the runtime
	# bridge the game boots from.
	if _added_autoload:
		remove_autoload_singleton(AUTOLOAD_NAME)
		_added_autoload = false
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	print("[MoonlitIdentity] Plugin disabled")


class MoonlitIdentityExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME: String = "MoonlitIdentity"
	const ExtensionListComposer = preload(
		"res://addons/moonlit-identity/extension_list_composer.gd")
	const AndroidManifestHook = preload(
		"res://addons/moonlit-identity/android_manifest_hook.gd")
	const IosExportManifest = preload(
		"res://addons/moonlit-identity/ios_export_manifest.gd")
	const ANDROID_GDAP_PATH: String = \
		"res://addons/moonlit-identity/android/MoonlitIdentity.gdap"
	const ANDROID_DEBUG_AAR: String = \
		"res://addons/moonlit-identity/android/MoonlitIdentity.debug.aar"
	const ANDROID_RELEASE_AAR: String = \
		"res://addons/moonlit-identity/android/MoonlitIdentity.release.aar"
	const IOS_GDEXTENSION_SOURCE: String = \
		"res://addons/moonlit-identity/ios/moonlit_identity.gdextension.ios"
	const IOS_GDEXTENSION_EXPORT: String = \
		"res://addons/moonlit-identity/bin/moonlit_identity.gdextension"
	const IOS_DEBUG_LIB: String = \
		"res://addons/moonlit-identity/bin/ios/libmoonlit_identity.debug.a"
	const IOS_RELEASE_LIB: String = \
		"res://addons/moonlit-identity/bin/ios/libmoonlit_identity.release.a"
	const IOS_FRAMEWORKS_ROOT: String = \
		"res://addons/moonlit-identity/bin/ios/frameworks"
	const IOS_RESOURCES_ROOT: String = \
		"res://addons/moonlit-identity/bin/ios/resources"
	const IDENTITY_CONFIG_PATH: String = "res://moonlit_identity.cfg"

	func _get_name() -> String:
		return PLUGIN_NAME

	func _supports_platform(
			platform: EditorExportPlatform) -> bool:
		if platform is EditorExportPlatformAndroid:
			return true
		if platform is EditorExportPlatformIOS:
			return true
		return false

	func _export_begin(features: PackedStringArray, is_debug: bool,
			_path: String, _flags: int) -> void:
		if _is_ios_export(features):
			_export_begin_ios(is_debug)
		_export_identity_config()
		_report_identity_config()

	func _export_begin_ios(is_debug: bool) -> void:
		if FileAccess.file_exists(IOS_GDEXTENSION_SOURCE):
			add_file(
				IOS_GDEXTENSION_EXPORT,
				FileAccess.get_file_as_bytes(IOS_GDEXTENSION_SOURCE),
				false)
			# One composed list shared with the godot-iap export plugin:
			# writing only this entry here would drop the purchase
			# extension whenever this writer runs last.
			add_file(
				ExtensionListComposer.extension_list_path(),
				ExtensionListComposer.compose().to_utf8_buffer(),
				false)
		else:
			push_warning(
				"[MoonlitIdentity] Missing iOS GDExtension descriptor: %s. "
				% IOS_GDEXTENSION_SOURCE
				+ "The export will run without native sign-in.")
		var static_lib: String = IOS_DEBUG_LIB if is_debug \
			else IOS_RELEASE_LIB
		if FileAccess.file_exists(static_lib):
			_add_ios_project_static_lib(static_lib)
			_add_ios_cpp_code(
				IosExportManifest.registration_cpp_code(static_lib))
		else:
			push_warning(
				"[MoonlitIdentity] Missing iOS static library: %s. " % static_lib
				+ "The export will run without native sign-in.")
		_add_ios_plist_content(
			IosExportManifest.plist_url_types_content(IDENTITY_CONFIG_PATH))
		_export_ios_frameworks(is_debug)

	func _export_ios_frameworks(is_debug: bool) -> void:
		# Static Firebase frameworks, staged per variant by --build-ios
		# from the discovered Pods build output. Linked, not embedded:
		# each bundle holds a static archive, and the export's Xcode
		# project re-signs whatever it embeds itself.
		var variant: String = "debug" if is_debug else "release"
		var frameworks_dir: String = IOS_FRAMEWORKS_ROOT + "/" + variant
		var frameworks: PackedStringArray = \
			IosExportManifest.framework_paths(frameworks_dir)
		if frameworks.is_empty():
			push_warning(
				"[MoonlitIdentity] No Firebase frameworks staged under %s. "
				% frameworks_dir + "The export will run without native "
				+ "sign-in. Run scripts/build-player-identity.mjs "
				+ "--fetch-deps --platform ios, then --build-ios.")
		for framework in frameworks:
			_add_ios_framework(framework)
		_export_ios_resources(variant)
		# System frameworks the static link was measured to need (nm over
		# the real archives plus a real arm64 link probe); bare names are
		# linked by the exporter without copying.
		for system in IosExportManifest.system_frameworks():
			_add_ios_framework(system)
		# -ObjC keeps Firebase's categories (dropped otherwise, crashing
		# every call); -lz serves GoogleUtilities compression.
		_add_ios_linker_flags(IosExportManifest.linker_flags())

	func _export_ios_resources(variant: String) -> void:
		# Privacy manifests travel as whole SDK bundles so the six
		# same-named PrivacyInfo files never collide; the exporter copies
		# each bundle into the app resources untouched.
		var resources_dir: String = IOS_RESOURCES_ROOT + "/" + variant
		var missing: PackedStringArray = \
			IosExportManifest.missing_required_bundles(resources_dir)
		if not missing.is_empty():
			push_warning(
				"[MoonlitIdentity] Privacy bundles missing under %s: %s. "
				% [resources_dir, ", ".join(missing)]
				+ "Run scripts/build-player-identity.mjs --build-ios "
				+ "--%s." % variant)
		for bundle in IosExportManifest.resource_bundle_paths(resources_dir):
			if IosExportManifest.bundle_has_manifest(bundle):
				_add_ios_bundle_file(bundle)
			else:
				push_warning(
					"[MoonlitIdentity] Staged bundle lacks its manifest, "
					+ "skipping: %s." % bundle)

	func _add_ios_project_static_lib(path: String) -> void:
		if has_method("add_apple_embedded_platform_project_static_lib"):
			call("add_apple_embedded_platform_project_static_lib", path)
			return
		if has_method("add_ios_project_static_lib"):
			call("add_ios_project_static_lib", path)
			return
		push_warning(
			"[MoonlitIdentity] Exporter has no static-library hook; "
			+ "link %s by hand." % path)

	func _add_ios_framework(path: String) -> void:
		if has_method("add_apple_embedded_platform_framework"):
			call("add_apple_embedded_platform_framework", path)
			return
		if has_method("add_ios_framework"):
			call("add_ios_framework", path)
			return
		push_warning(
			"[MoonlitIdentity] Exporter has no framework hook; "
			+ "link %s by hand." % path)

	func _add_ios_linker_flags(flags: String) -> void:
		if has_method("add_apple_embedded_platform_linker_flags"):
			call("add_apple_embedded_platform_linker_flags", flags)
			return
		if has_method("add_ios_linker_flags"):
			call("add_ios_linker_flags", flags)
			return
		push_warning(
			"[MoonlitIdentity] Exporter has no linker-flags hook; "
			+ "add -ObjC to the Xcode target by hand.")

	func _add_ios_bundle_file(path: String) -> void:
		if has_method("add_apple_embedded_platform_bundle_file"):
			call("add_apple_embedded_platform_bundle_file", path)
			return
		if has_method("add_ios_bundle_file"):
			call("add_ios_bundle_file", path)
			return
		push_warning(
			"[MoonlitIdentity] Exporter has no bundle-file hook; "
			+ "embed %s by hand." % path)

	func _add_ios_cpp_code(code: String) -> void:
		# Empty code means the static library is absent; emitting
		# nothing keeps that export a clean graceful degradation.
		if code.is_empty():
			return
		var hook: String = _select_cpp_code_hook()
		if hook.is_empty():
			push_warning(
				"[MoonlitIdentity] Exporter has no C++ code hook; "
				+ "register moonlit_identity_ios_entry by hand.")
			return
		call(hook, code)

	func _select_cpp_code_hook() -> String:
		var available: Array[String] = []
		for hook in IosExportManifest.CPP_CODE_HOOKS:
			if _has_export_hook(hook):
				available.append(hook)
		return IosExportManifest.select_cpp_code_hook(available)

	func _add_ios_plist_content(content: String) -> void:
		# Empty content means no staged Google client id; emitting nothing
		# keeps that export a clean graceful degradation.
		if content.is_empty():
			return
		var available: Array[String] = []
		for hook in IosExportManifest.PLIST_CONTENT_HOOKS:
			if _has_export_hook(hook):
				available.append(hook)
		var hook: String = \
			IosExportManifest.select_plist_content_hook(available)
		if hook.is_empty():
			push_warning(
				"[MoonlitIdentity] Exporter has no plist-content hook; "
				+ "register the GoogleSignIn callback URL scheme by hand.")
			return
		call(hook, content)

	func _has_export_hook(hook_name: String) -> bool:
		return has_method(hook_name)

	func _get_android_libraries(
			_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		var aar: String = ANDROID_DEBUG_AAR if debug \
			else ANDROID_RELEASE_AAR
		if not FileAccess.file_exists(aar):
			push_warning(
				"[MoonlitIdentity] Missing Android AAR: %s. " % aar
				+ "The export will run without native sign-in.")
			return PackedStringArray()
		return PackedStringArray([aar])

	func _get_android_dependencies(
			_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return _read_android_remote_dependencies()

	func _get_android_manifest_application_element_contents(
			_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return AndroidManifestHook.application_element_contents(
			IDENTITY_CONFIG_PATH)

	func _export_identity_config() -> void:
		# A config-only file has no resource referrer, so the exporter
		# would leave it behind: stage it explicitly when the wrapper
		# installed it for this export, and skip silently otherwise.
		# Values never print; presence is reported separately below.
		if not FileAccess.file_exists(IDENTITY_CONFIG_PATH):
			return
		add_file(
			IDENTITY_CONFIG_PATH,
			FileAccess.get_file_as_bytes(IDENTITY_CONFIG_PATH),
			false)


	func _report_identity_config() -> void:
		# Presence only. Values stay out of the editor log the same way they
		# stay out of the repo.
		if FileAccess.file_exists(IDENTITY_CONFIG_PATH):
			print("[MoonlitIdentity] Public identity config found.")
		else:
			push_warning(
				"[MoonlitIdentity] No res://moonlit_identity.cfg. Provider "
				+ "sign-in will report not_configured; guest play is "
				+ "unaffected. Run scripts/build-player-identity.mjs "
				+ "--install after configuring public client identifiers.")

	func _is_ios_export(features: PackedStringArray) -> bool:
		var platform: EditorExportPlatform = get_export_platform()
		return (
			platform is EditorExportPlatformIOS
			or features.has("ios")
			or features.has("iOS")
		)

	func _read_android_remote_dependencies() -> PackedStringArray:
		if not FileAccess.file_exists(ANDROID_GDAP_PATH):
			push_warning(
				"[MoonlitIdentity] Missing Android dependency manifest: %s"
				% ANDROID_GDAP_PATH)
			return PackedStringArray()
		var gdap_content: String = \
			FileAccess.get_file_as_string(ANDROID_GDAP_PATH)
		var dependency_regex: RegEx = RegEx.new()
		var compile_error: Error = dependency_regex.compile(
			"\"([A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[^\"]+)\"")
		if compile_error != OK:
			push_warning(
				"[MoonlitIdentity] Failed to compile Android dependency parser")
			return PackedStringArray()
		var dependencies: PackedStringArray = PackedStringArray()
		for match_result in dependency_regex.search_all(gdap_content):
			dependencies.append(match_result.get_string(1))
		return dependencies
