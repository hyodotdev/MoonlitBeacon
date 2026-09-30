extends Node

## Stand-in for the godot-iap wrapper at the backend's dispatch boundary, and
## for the native bridge when a test puts it behind the real wrapper.

signal purchase_updated(purchase: Dictionary)
signal purchase_error(error: Dictionary)
signal connected
signal disconnected

var dispatched: bool = true
var request_count: int = 0
var last_props: Variant
var last_available_options: Variant
var native_available_result_json: String = \
	'{"success":true,"purchases":[]}'
var native_restore_result_json: String = '{"success":true,"count":0}'
var native_request_result_json: String = '{"success":true}'
var native_request_count: int = 0
var ios_available_payload: Dictionary = {
	"success": true,
	"purchasesJson": "[]",
}
var _platform: String = "Android"
var _store_connected: bool = true


func get_platform() -> String:
	return _platform


func is_store_connected() -> bool:
	return _store_connected


func request_purchase(props: Variant) -> Variant:
	request_count += 1
	last_props = props
	if not dispatched:
		purchase_error.emit({
			"code": "not-prepared",
			"message": "billing unavailable",
		})
	# The canonical 3.x wrapper also returns null for a normal async pending.
	return null


func requestPurchase(_params_json: String) -> String:
	native_request_count += 1
	return native_request_result_json


func requestPurchaseWithPayload(_params_json: String) -> String:
	native_request_count += 1
	return native_request_result_json


func getAvailablePurchasesResult() -> String:
	return native_available_result_json


func getAvailablePurchasesResultWithOptions(options_json: String) -> String:
	last_available_options = JSON.parse_string(options_json)
	return native_available_result_json


## Apple bridge: answer at once (no requestId) so the wrapper skips its async wait.
func getAvailablePurchases(options_json: String) -> String:
	last_available_options = JSON.parse_string(options_json)
	return JSON.stringify(ios_available_payload)


func restorePurchases() -> String:
	return native_restore_result_json
