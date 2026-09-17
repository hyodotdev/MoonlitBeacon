extends Node

## Plugin whose `fetch_products` never answers.
##
## Play Billing actually behaved this way — while a purchase that failed
## verification and was never finished stayed on the account, the Pixel 10
## query callback never arrived even after several minutes. If that await
## never returns, the shop stays dead including the retry button.

var fetch_calls: int = 0
var should_answer: bool = false
var answer: Array = []


func get_platform() -> String:
	return "Android"


func is_store_connected() -> bool:
	return true


func fetch_products(_request: Variant) -> Array:
	fetch_calls += 1
	while not should_answer and is_inside_tree():
		await get_tree().process_frame
	return answer
