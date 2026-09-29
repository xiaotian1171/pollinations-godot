class_name PollinationsClient
extends Node

## Thin, retrying HTTP layer. Every node in this add-on talks through it, so
## error handling and backoff live in exactly one place.
##
## The transport can be replaced, which is what the offline tests do:
##   client.transport = func(method, url, headers, body): return {...}

## Optional injected transport:
## func(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary
## It must return {"status": int, "body": String, "bytes": PackedByteArray,
## "transport_result": int, "headers": PackedStringArray}.
var transport: Callable = Callable()

## Optional injected sleep, `func(seconds: float) -> void`, used between retries.
var sleep: Callable = Callable()

var max_retries: int = 2
var retry_base_seconds: float = 0.75
var retry_cap_seconds: float = 8.0
var timeout_seconds: float = 120.0
var debug: bool = false

## Last request, handy for a debug overlay.
var last_request: Dictionary = {}

## Sends a request and waits for it, retrying the failures worth retrying.
func send(method: String, url: String, headers: PackedStringArray = PackedStringArray(), body: String = "") -> Dictionary:
	var attempts := 0
	var kind := PollinationsErrors.Kind.UNKNOWN
	var response: Dictionary = {}
	while true:
		attempts += 1
		response = await _send_once(method, url, headers, body)
		kind = PollinationsErrors.classify(
			int(response.get("status", 0)),
			str(response.get("body", "")),
			int(response.get("transport_result", -1))
		)
		if kind == PollinationsErrors.Kind.NONE or attempts > max_retries or not PollinationsErrors.retryable(kind):
			break
		var delay := PollinationsErrors.backoff_seconds(attempts - 1, retry_base_seconds, retry_cap_seconds)
		_log("%s %s failed with %s, retrying in %.2fs" % [method, url, PollinationsErrors.kind_name(kind), delay])
		await _sleep(delay)

	last_request = {"method": method, "url": url, "attempts": attempts, "status": int(response.get("status", 0))}
	if kind == PollinationsErrors.Kind.NONE:
		return _ok(response, attempts, url)
	return _failure(kind, response, attempts, url)

## GET with the configured credentials. Pass `headers` to override them.
func get_json(url: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var sent := headers
	if sent.is_empty():
		sent = PollinationsConfig.authorization_headers()
	return await send("GET", url, sent)

## POST JSON signed with the configured credentials (unless `headers` says
## otherwise), so callers cannot forget the Authorization header.
func post_json(url: String, payload: Dictionary, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var sent := headers
	if sent.is_empty():
		sent = auth_json_headers()
	return await send("POST", url, sent, JSON.stringify(payload))

## Headers for an authenticated JSON request.
func auth_json_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(PollinationsConfig.authorization_headers())
	return headers

func _send_once(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	if transport.is_valid():
		var injected: Variant = await transport.call(method, url, headers, body)
		if injected is Dictionary:
			return injected
		return _transport_failure("the injected transport returned %s" % str(injected))
	return await _send_with_http_request(method, url, headers, body)

func _send_with_http_request(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.name = "PollinationsHttpRequest"
	request.timeout = timeout_seconds
	request.accept_gzip = true
	add_child(request)
	var error := request.request(url, headers, http_method(method), body)
	if error != OK:
		request.queue_free()
		_log("could not start %s %s: %s" % [method, url, error_string(error)])
		var failed := _transport_failure(error_string(error))
		failed["transport_result"] = HTTPRequest.RESULT_CANT_CONNECT
		return failed
	var completed: Array = await request.request_completed
	request.queue_free()
	var headers_out: PackedStringArray = completed[2]
	var bytes: PackedByteArray = completed[3]
	return {
		"status": int(completed[1]),
		"headers": headers_out,
		# image and audio bodies are binary; decoding them as UTF-8 would only
		# produce noise, so they stay in `bytes` and `text` stays empty
		"body": bytes.get_string_from_utf8() if is_textual(headers_out) else "",
		"bytes": bytes,
		"transport_result": int(completed[0]),
	}

## True when a response body should be treated as text. A missing Content-Type
## counts as text, which is what the API does for JSON.
static func is_textual(headers: PackedStringArray) -> bool:
	for header: String in headers:
		var parts := header.split(":", true, 1)
		if parts.size() < 2 or parts[0].strip_edges().to_lower() != "content-type":
			continue
		var mime := parts[1].strip_edges().to_lower()
		if mime.begins_with("image/") or mime.begins_with("audio/") or mime.begins_with("video/"):
			return false
		if mime.begins_with("application/octet-stream"):
			return false
	return true

## HTTPRequest wants an HTTPClient.Method, while this add-on (and the tests)
## talk in plain method names. GET is the fallback for anything unexpected,
## which is reported rather than silently sent as a POST.
static func http_method(method: String) -> int:
	match method.strip_edges().to_upper():
		"GET":
			return HTTPClient.METHOD_GET
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"DELETE":
			return HTTPClient.METHOD_DELETE
		"HEAD":
			return HTTPClient.METHOD_HEAD
	push_error("[pollinations] unsupported HTTP method %s, sending GET" % method)
	return HTTPClient.METHOD_GET

func _sleep(seconds: float) -> void:
	if sleep.is_valid():
		await sleep.call(seconds)
		return
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout
	else:
		await Engine.get_main_loop().create_timer(seconds).timeout

func _ok(response: Dictionary, attempts: int, url: String) -> Dictionary:
	var text := str(response.get("body", ""))
	var decoded := _decode(text)
	return {
		"ok": true,
		"kind": PollinationsErrors.Kind.NONE,
		"kind_name": PollinationsErrors.kind_name(PollinationsErrors.Kind.NONE),
		"status": int(response.get("status", 0)),
		"text": text,
		"json": decoded,
		"bytes": response.get("bytes", PackedByteArray()),
		"headers": response.get("headers", PackedStringArray()),
		"error": "",
		"attempts": attempts,
		"url": url,
	}

func _failure(kind: PollinationsErrors.Kind, response: Dictionary, attempts: int, url: String) -> Dictionary:
	var status := int(response.get("status", 0))
	var text := str(response.get("body", ""))
	var detail := text.strip_edges().left(200)
	if detail.is_empty():
		detail = str(response.get("error", ""))
	var failure := PollinationsClient.failure(kind, status, url, detail)
	# Failed responses can still carry a useful body, e.g. the device flow
	# answers "authorization_pending" while the player has not approved yet.
	failure["json"] = _decode(text)
	failure["attempts"] = attempts
	return failure

## Builds a failure result without a response, for callers that reject a
## successful response because its payload is unusable.
static func failure(kind: PollinationsErrors.Kind, status: int, url: String, detail: String) -> Dictionary:
	return {
		"ok": false,
		"kind": kind,
		"kind_name": PollinationsErrors.kind_name(kind),
		"status": status,
		"text": "",
		"json": null,
		"bytes": PackedByteArray(),
		"headers": PackedStringArray(),
		"error": PollinationsErrors.describe(kind, status, detail),
		"message": PollinationsErrors.message(kind),
		"attempts": 1,
		"url": url,
	}

static func _decode(text: String) -> Variant:
	if text.strip_edges().is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data

func _transport_failure(detail: String) -> Dictionary:
	return {
		"status": 0,
		"headers": PackedStringArray(),
		"body": detail,
		"bytes": PackedByteArray(),
		"transport_result": HTTPRequest.RESULT_CANT_CONNECT,
	}

func _log(message: String) -> void:
	if debug:
		print("[pollinations] %s" % message)
