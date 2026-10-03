extends Node

## Real HTTPRequest sender for the cloud transport. Kept separate so the
## transport stays a pure RefCounted and tests inject fakes with no network.
##
## Never logs URLs with keys, auth headers, or bodies. Timeouts and response
## bounds match the transport so a slow or huge reply fails closed. The body
## bound is enforced by the engine before receipt (`body_size_limit`), not
## by measuring after: an oversized reply never allocates. Closing the node
## cancels every in-flight request so teardown leaves no hanging request
## whose late reply could apply to a new account.

const TIMEOUT_SECONDS: float = 10.0
const MAX_RESPONSE_BYTES: int = 262144

var _active: Array[HTTPRequest] = []
var _generation: int = 0
var _closed: bool = false


func _exit_tree() -> void:
	close()


## Retire every in-flight request and refuse new ones. Late completions
## report cancelled and apply nothing.
func close() -> void:
	_closed = true
	_generation += 1
	for request in _active.duplicate():
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_active.clear()


## Sends one Firestore REST call. Returns the sender envelope the transport
## interprets. `headers` values are sent as-is; callers supply auth.
func send(method: String, url: String, headers: Dictionary,
		body: String) -> Dictionary:
	if _closed:
		return {"transport": "cancelled", "code": 0, "body": PackedByteArray()}
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.body_size_limit = MAX_RESPONSE_BYTES
	add_child(request)
	_active.append(request)
	var captured_generation: int = _generation
	var header_lines: PackedStringArray = PackedStringArray()
	for key in headers.keys():
		header_lines.append("%s: %s" % [str(key), str(headers[key])])
	var http_method: int = _http_method(method)
	var start_error: Error = request.request(url, header_lines, http_method, body)
	if start_error != OK:
		_forget(request)
		request.queue_free()
		return {"transport": "unreachable", "code": 0, "body": PackedByteArray()}
	var completed: Array = await request.request_completed
	_forget(request)
	if _closed or captured_generation != _generation \
			or not is_instance_valid(request):
		if is_instance_valid(request):
			request.queue_free()
		return {"transport": "cancelled", "code": 0, "body": PackedByteArray()}
	request.queue_free()
	if completed.size() != 4:
		return {"transport": "cancelled", "code": 0, "body": PackedByteArray()}
	var transport_result: int = int(completed[0])
	var response_code: int = int(completed[1])
	var response_body: PackedByteArray = completed[3]
	if transport_result == HTTPRequest.RESULT_TIMEOUT:
		return {"transport": "timeout", "code": 0, "body": PackedByteArray()}
	if transport_result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return {"transport": "response-too-large", "code": response_code,
			"body": PackedByteArray()}
	if transport_result == HTTPRequest.RESULT_CANT_RESOLVE \
			or transport_result == HTTPRequest.RESULT_CANT_CONNECT \
			or transport_result == HTTPRequest.RESULT_CONNECTION_ERROR \
			or transport_result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR \
			or transport_result == HTTPRequest.RESULT_NO_RESPONSE:
		return {"transport": "offline", "code": 0, "body": PackedByteArray()}
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return {"transport": "unreachable", "code": 0, "body": PackedByteArray()}
	return {"transport": "ok", "code": response_code, "body": response_body}


func _forget(request: HTTPRequest) -> void:
	_active.erase(request)


func _http_method(method: String) -> int:
	match method.to_upper():
		"GET":
			return HTTPClient.METHOD_GET
		"POST":
			return HTTPClient.METHOD_POST
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"DELETE":
			return HTTPClient.METHOD_DELETE
	return HTTPClient.METHOD_GET
