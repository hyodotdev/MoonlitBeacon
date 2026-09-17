extends Node

## Inspects IAPKit HTTP request shape and failure/response handling with no network.

var results: Array[Dictionary] = []
var calls: Array[Dictionary] = []


func post_verification(api_key: String, body: Dictionary) -> Dictionary:
	calls.append({
		"api_key": api_key,
		"body": body.duplicate(true),
	})
	if not results.is_empty():
		return results.pop_front().duplicate(true)
	return {
		"success": true,
		"body": {
			"store": body.get("store", ""),
			"isValid": true,
			"state": "ENTITLED",
			"productId": body.get("expectedProductId", ""),
		},
	}
