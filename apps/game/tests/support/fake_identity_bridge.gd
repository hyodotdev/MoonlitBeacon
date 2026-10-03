extends Node

## Scripted stand-in for the native MoonlitIdentity engine singleton.
##
## Speaks the same contract as the Kotlin plugin and the iOS GDExtension
## class: methods take `(request_id, args_json)`, answer with a receipt
## Dictionary, and settle `pending` receipts later on
## `moonlit_identity_event`. Tests drive outcomes by hand with `emit_outcome()`.

signal moonlit_identity_event(outcome: Dictionary)

var receipts: Dictionary = {}
var calls: Array[String] = []
var last_args: Dictionary = {}
var cancelled_ids: Array[String] = []
# Scripted `moonlitCancelRequest` answer. `{"status": "cancelled"}` means the
# native side stopped before any mutation; `{"status": "draining"}` means a
# mutation already began and the terminal outcome still follows.
var cancel_answer: Dictionary = {"status": "cancelled"}
# Faithful emulation of the native single-mutation slot: while a mutating
# call is pending, a second mutating call answers `mutation_in_progress`.
# Read-only session/token calls never take the slot.
var enforce_mutation_lock: bool = false
var mutation_owner: String = ""


func moonlitSignInGuest(request_id: String, args_json: String) -> Dictionary:
	return _answer("moonlitSignInGuest", request_id, args_json)


func moonlitSignInProvider(request_id: String, args_json: String) -> Dictionary:
	return _answer("moonlitSignInProvider", request_id, args_json)


func moonlitLinkProvider(request_id: String, args_json: String) -> Dictionary:
	return _answer("moonlitLinkProvider", request_id, args_json)


func moonlitGetSession(request_id: String, args_json: String) -> Dictionary:
	return _answer("moonlitGetSession", request_id, args_json)


func moonlitGetIdToken(request_id: String, args_json: String) -> Dictionary:
	return _answer("moonlitGetIdToken", request_id, args_json)


func moonlitSignOut(request_id: String, args_json: String) -> Dictionary:
	return _answer("moonlitSignOut", request_id, args_json)


func moonlitDeleteAccount(request_id: String, args_json: String) -> Dictionary:
	return _answer("moonlitDeleteAccount", request_id, args_json)


func moonlitCancelRequest(request_id: String) -> Dictionary:
	cancelled_ids.append(request_id)
	var answer: Dictionary = cancel_answer.duplicate()
	answer["request_id"] = request_id
	if str(answer.get("status", "")) != "draining" \
			and mutation_owner == request_id:
		mutation_owner = ""
	return answer


func emit_outcome(outcome: Dictionary) -> void:
	var folded: Dictionary = outcome.duplicate()
	# A terminal outcome settles the native slot, exactly like finish().
	if str(folded.get("request_id", "")) == mutation_owner \
			and str(folded.get("status", "")) != "pending":
		mutation_owner = ""
	moonlit_identity_event.emit(folded)


func _answer(method: String, request_id: String,
		args_json: String) -> Dictionary:
	calls.append(method)
	last_args[method] = JSON.parse_string(args_json)
	if _is_mutating_call(method) and enforce_mutation_lock \
			and not mutation_owner.is_empty():
		return {"status": "error", "code": "mutation_in_progress",
			"retryable": true, "request_id": request_id}
	var receipt: Dictionary
	if receipts.has(method):
		receipt = (receipts[method] as Dictionary).duplicate()
	else:
		receipt = {"status": "ok", "kind": "local_guest", "uid": "",
			"provider": ""}
	receipt["request_id"] = request_id
	if _is_mutating_call(method) and enforce_mutation_lock \
			and str(receipt.get("status", "")) == "pending":
		mutation_owner = request_id
	return receipt


func _is_mutating_call(method: String) -> bool:
	return method in ["moonlitSignInGuest", "moonlitSignInProvider",
		"moonlitLinkProvider", "moonlitSignOut", "moonlitDeleteAccount"]
