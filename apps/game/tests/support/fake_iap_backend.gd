extends "res://scripts/iap/iap_backend.gd"

## Deterministic store used by Moonlit shop regression tests.
##
## Injects return values and purchase lists instead of a real checkout, and
## records call order.

var initialize_result: bool = true
var restore_result: bool = true
var request_result: bool = true
var available_result: bool = true
var fetched_products: Array[Dictionary] = []
var owned_purchases: Array[Dictionary] = []
var finish_results: Array[bool] = []
var verification_results: Array[Dictionary] = []
var calls: Array[String] = []
var requested_product_ids: Array[String] = []
var finished_purchases: Array[Dictionary] = []
## Consumable flags received by `finish()`. Order matches `finished_purchases`.
var finished_consumable_flags: Array[bool] = []
var verified_purchases: Array[Dictionary] = []
var finish_observer: Callable
var verification_observer: Callable
var restore_observer: Callable
var initialize_observer: Callable
var available_observer: Callable
var connected_state: bool = false
var verification_ready_result: bool = true


func initialize() -> bool:
	calls.append("initialize")
	connected_state = initialize_result
	if connected_state:
		connected.emit()
	if initialize_observer.is_valid():
		await initialize_observer.call()
	return initialize_result


func fetch_products(product_ids: Array[String]) -> Array[Dictionary]:
	calls.append("fetch:" + ",".join(product_ids))
	return fetched_products.duplicate(true)


func request_purchase(product_id: String) -> bool:
	calls.append("request:" + product_id)
	requested_product_ids.append(product_id)
	return request_result


func restore() -> bool:
	calls.append("restore")
	if restore_observer.is_valid():
		restore_observer.call()
	return restore_result


func available_purchases() -> Dictionary:
	calls.append("available")
	if available_observer.is_valid():
		await available_observer.call()
	return {
		"success": available_result,
		"purchases": owned_purchases.duplicate(true) if available_result else [],
	}


func verification_ready() -> bool:
	return verification_ready_result


func verify_purchase(
		purchase: Dictionary, expected_product_id: String) -> Dictionary:
	calls.append("verify:" + expected_product_id)
	verified_purchases.append(purchase.duplicate(true))
	if verification_observer.is_valid():
		await verification_observer.call(purchase)
	if not verification_results.is_empty():
		return verification_results.pop_front().duplicate(true)
	var store: String = "apple" if purchase.has("appBundleIdIOS") \
		or str(purchase.get("store", "")).to_lower() in ["apple", "app-store", "ios"] \
		else "google"
	return {
		"success": true,
		"is_valid": true,
		"store": store,
		"state": "entitled",
		"product_id": expected_product_id,
	}


## For consumables the store consumes the purchase so it can be bought again.
## Tests also check that this flag is actually passed — consuming a
## non-consumable would unlock ownership.
func finish(purchase: Dictionary, consumable: bool = false) -> bool:
	finished_consumable_flags.append(consumable)
	calls.append("finish:" + str(purchase.get("productId", "")))
	finished_purchases.append(purchase.duplicate(true))
	if finish_observer.is_valid():
		finish_observer.call(purchase)
	if not finish_results.is_empty():
		return finish_results.pop_front()
	return true


func emit_purchase(purchase: Dictionary) -> void:
	purchase_updated.emit(purchase.duplicate(true))


func emit_failure(product_id: String, code: String) -> void:
	purchase_failed.emit({"productId": product_id, "code": code})


func emit_disconnect() -> void:
	connected_state = false
	disconnected.emit()
