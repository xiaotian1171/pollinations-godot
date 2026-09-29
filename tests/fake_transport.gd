class_name FakeTransport
extends RefCounted

## A scripted transport for the offline tests: it replays a queue of responses
## and records everything it was asked to do.

var responses: Array = []
var requests: Array = []

## Queues one response. `bytes` defaults to the UTF-8 encoding of `body`.
static func response(status: int, body: String, transport_result: int = HTTPRequest.RESULT_SUCCESS) -> Dictionary:
	return {
		"status": status,
		"body": body,
		"bytes": body.to_utf8_buffer(),
		"transport_result": transport_result,
		"headers": PackedStringArray(["Content-Type: application/json"]),
	}

## A transport that always answers the same way.
static func always(response_dict: Dictionary) -> Callable:
	return func(_method: String, _url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
		return response_dict.duplicate(true)

## Builds the Callable to hand to PollinationsClient.transport. The last queued
## response is repeated once the queue runs dry.
func callable() -> Callable:
	return func(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		requests.append({"method": method, "url": url, "headers": headers, "body": body})
		if responses.is_empty():
			return response(500, '{"error":"no scripted response"}')
		if responses.size() == 1:
			return responses[0]
		return responses.pop_front()

## The JSON body of request `index`, or {} when it is not JSON.
func body_json(index: int) -> Dictionary:
	if index >= requests.size():
		return {}
	var parsed: Variant = JSON.parse_string(str(requests[index].get("body", "")))
	if parsed is Dictionary:
		return parsed
	return {}

func header_of(index: int, name: String) -> String:
	if index >= requests.size():
		return ""
	for header: String in requests[index].get("headers", PackedStringArray()):
		if header.to_lower().begins_with(name.to_lower() + ":"):
			return header.split(":", true, 1)[1].strip_edges()
	return ""
