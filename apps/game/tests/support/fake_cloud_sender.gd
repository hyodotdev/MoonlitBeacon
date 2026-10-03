extends RefCounted

## Scripted fake for the cloud sender contract. Tests queue replies and then
## assert on the recorded calls. No network, no tokens in output.

var replies: Array[Dictionary] = []
var calls: Array[Dictionary] = []
var default_reply: Dictionary = {"transport": "ok", "code": 200, "body": "{}"}


func queue_reply(reply: Dictionary) -> void:
	replies.append(reply.duplicate(true))


func queue_ok(body: String = "{}", code: int = 200) -> void:
	replies.append({"transport": "ok", "code": code, "body": body})


func send(method: String, url: String, headers: Dictionary,
		body: String) -> Dictionary:
	var recorded_headers: Dictionary = {}
	for key in headers.keys():
		# The test double records that auth was sent without keeping the token.
		if str(key).to_lower() == "authorization":
			recorded_headers[key] = "<auth>"
		else:
			recorded_headers[key] = headers[key]
	calls.append({
		"method": method,
		"url": url,
		"headers": recorded_headers,
		"body": body,
	})
	if not replies.is_empty():
		return replies.pop_front().duplicate(true)
	return default_reply.duplicate(true)


func sender_callable() -> Callable:
	return Callable(self, "send")


func last_call() -> Dictionary:
	if calls.is_empty():
		return {}
	return calls[calls.size() - 1]


func reset() -> void:
	replies.clear()
	calls.clear()
