extends Node

## Narrow boundary between the store SDK and the game purchase ledger.
##
## On device this is `GodotIapBackend`; regression tests inject a fake backend.
## The game never sees Apple/Google format differences, only a plain Dictionary.

signal purchase_updated(purchase: Dictionary)
signal purchase_failed(error: Dictionary)
signal connected
signal disconnected


func initialize() -> bool:
	return false


func fetch_products(_product_ids: Array[String]) -> Array[Dictionary]:
	return []


func request_purchase(_product_id: String) -> bool:
	return false


func restore() -> bool:
	return false


func available_purchases() -> Dictionary:
	return {
		"success": false,
		"purchases": [],
	}


func verification_ready() -> bool:
	return false


func verify_purchase(
		_purchase: Dictionary, _expected_product_id: String) -> Dictionary:
	return {
		"success": false,
		"error_code": "verification-unavailable",
	}


func finish(_purchase: Dictionary, _consumable: bool = false) -> bool:
	return false


func shutdown() -> void:
	pass
