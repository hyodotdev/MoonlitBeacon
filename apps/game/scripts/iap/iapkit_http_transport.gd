extends Node

## Small HTTP boundary that only calls IAPKit's public purchase-verification API.
##
## Never put the API key, JWS, or purchaseToken in error messages or logs.
## Distinguish HTTP errors from an invalid purchase so the caller can retry
## via store replay without granting or finishing.

const VERIFY_URL: String = "https://kit.openiap.dev/v1/purchase/verify"
const TIMEOUT_SECONDS: float = 15.0
const MAX_RESPONSE_BYTES: int = 64 * 1024


func post_verification(api_key: String, body: Dictionary) -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	add_child(request)
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/json",
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json",
	])
	var request_error: Error = request.request(
		VERIFY_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body))
	if request_error != OK:
		request.queue_free()
		return _failure("request-start-failed")
	var completed: Array = await request.request_completed
	request.queue_free()
	if completed.size() != 4:
		return _failure("malformed-http-result")
	var transport_result: int = int(completed[0])
	var response_code: int = int(completed[1])
	var response_body: PackedByteArray = completed[3]
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return _failure("verification-unavailable", true)
	if response_code < 200 or response_code >= 300:
		return _http_failure(response_code)
	if response_body.size() <= 0 or response_body.size() > MAX_RESPONSE_BYTES:
		return _failure("verification-unavailable", true)
	var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if parsed is not Dictionary:
		return _failure("verification-unavailable", true)
	return {
		"success": true,
		"body": parsed,
	}


func _http_failure(response_code: int) -> Dictionary:
	if response_code in [408, 425, 429] or response_code >= 500:
		return _failure("verification-unavailable", true)
	if response_code in [401, 403]:
		return _failure("verification-configuration-error", false)
	return _failure("verification-rejected", false)


func _failure(code: String, retryable: bool = true) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"retryable": retryable,
	}
