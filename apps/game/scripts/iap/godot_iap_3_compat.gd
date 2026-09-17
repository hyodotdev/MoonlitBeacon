extends RefCounted

## Preserve native query failures that the public Array API would collapse.
##
## Upstream `get_available_purchases()` still maps a store/bridge failure to an
## empty list. Entitlement sync cannot treat those the same, so this narrow
## adapter reads the Android result envelope and the Apple async envelope.
## Every other call goes through the official 3.x wrapper.

const PLATFORM_ANDROID: String = "Android"
const PLATFORM_IOS: String = "iOS"

var _plugin: Node


func _init(plugin: Node) -> void:
	_plugin = plugin


func available_purchases(options: Variant = null) -> Dictionary:
	if _plugin == null:
		return _failure()
	var platform: String = str(_plugin.get_platform())
	if platform == PLATFORM_ANDROID:
		return _android_available_purchases(options)
	if platform == PLATFORM_IOS:
		return await _ios_available_purchases(options)
	return _failure()


func restore_purchases() -> Dictionary:
	if _plugin == null:
		return _failure()
	var platform: String = str(_plugin.get_platform())
	if platform == PLATFORM_ANDROID:
		return _android_void_result("restorePurchases")
	if platform == PLATFORM_IOS:
		var result: Variant = await _plugin.restore_purchases()
		return {
			"success": _result_success(result),
		}
	return _failure()


func _android_available_purchases(options: Variant) -> Dictionary:
	var native: Variant = _native_plugin()
	if native == null:
		return _failure()
	var response_json: Variant
	if options == null:
		response_json = native.call("getAvailablePurchasesResult")
	else:
		response_json = native.call(
			"getAvailablePurchasesResultWithOptions",
			JSON.stringify(_as_dictionary(options)))
	return _parse_available_result(response_json)


func _ios_available_purchases(options: Variant) -> Dictionary:
	var payload: Variant
	if _plugin.has_method("_call_apple_async"):
		payload = await _plugin._call_apple_async(
			"getAvailablePurchases",
			[JSON.stringify(_as_dictionary(options))])
	elif _plugin.has_method("_call_ios_async"):
		payload = await _plugin._call_ios_async(
			"getAvailablePurchases",
			[JSON.stringify(_as_dictionary(options))])
	else:
		return _failure()
	if payload is not Dictionary or not bool(payload.get("success", false)):
		return _failure()
	var purchases: Variant = _parse_json(
		str(payload.get("purchasesJson", "")))
	if purchases is not Array:
		return _failure()
	return {
		"success": true,
		"purchases": purchases,
	}


func _android_void_result(method: String) -> Dictionary:
	var native: Variant = _native_plugin()
	if native == null:
		return _failure()
	var parsed: Variant = _parse_json(native.call(method))
	if parsed is not Dictionary or typeof(parsed.get("success", null)) != TYPE_BOOL:
		return _failure()
	return {
		"success": bool(parsed.get("success", false)),
	}


func _parse_available_result(response_json: Variant) -> Dictionary:
	var parsed: Variant = _parse_json(response_json)
	if parsed is not Dictionary \
			or typeof(parsed.get("success", null)) != TYPE_BOOL \
			or parsed.get("purchases", null) is not Array:
		return _failure()
	if not bool(parsed.get("success", false)):
		return _failure()
	return {
		"success": true,
		"purchases": parsed.get("purchases", []),
	}


func _native_plugin() -> Variant:
	return _plugin.get("_native_plugin")


func _parse_json(value: Variant) -> Variant:
	var parser: JSON = JSON.new()
	if parser.parse(str(value)) != OK:
		return null
	return parser.data


func _result_success(result: Variant) -> bool:
	if result is Dictionary:
		return typeof(result.get("success", null)) == TYPE_BOOL \
			and bool(result.get("success", false))
	if typeof(result) == TYPE_OBJECT and is_instance_valid(result):
		var value: Variant = result.get("success")
		return typeof(value) == TYPE_BOOL and bool(value)
	return false


func _as_dictionary(value: Variant) -> Dictionary:
	if value == null:
		return {}
	if value is Dictionary:
		return value
	if typeof(value) == TYPE_OBJECT \
			and is_instance_valid(value) \
			and value.has_method("to_dict"):
		var converted: Variant = value.to_dict()
		if converted is Dictionary:
			return converted
	return {}


func _failure() -> Dictionary:
	return {
		"success": false,
		"purchases": [],
	}
