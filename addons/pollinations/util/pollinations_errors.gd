class_name PollinationsErrors
extends RefCounted

## Maps HTTP and transport failures onto a small set of stable kinds, so game
## code can react to a failure instead of parsing error strings.

enum Kind {
	NONE, ## the request succeeded
	AUTH, ## missing, invalid or revoked key
	BALANCE, ## the key is valid but has no pollen left
	RATE_LIMIT, ## too many requests
	BAD_REQUEST, ## the request itself is wrong (unknown model, bad parameters)
	SERVER, ## upsteam or Pollinations hiccup
	NETWORK, ## the request never completed (DNS, TLS, timeout)
	PARSE, ## 200, but the payload could not be used
	UNKNOWN,
}

const KIND_NAMES: Dictionary = {
	Kind.NONE: "none",
	Kind.AUTH: "auth",
	Kind.BALANCE: "balance",
	Kind.RATE_LIMIT: "rate_limit",
	Kind.BAD_REQUEST: "bad_request",
	Kind.SERVER: "server",
	Kind.NETWORK: "network",
	Kind.PARSE: "parse",
	Kind.UNKNOWN: "unknown",
}

const KIND_MESSAGES: Dictionary = {
	Kind.NONE: "OK",
	Kind.AUTH: "The API key is missing or not accepted. Check pollinations/api_key, or sign a player in with PollinationsAuth.",
	Kind.BALANCE: "This key is out of pollen. Add pollen to the account, or let the player pay with their own Pollen through PollinationsAuth.",
	Kind.RATE_LIMIT: "Too many requests right now. The request was retried; lower the rate if this repeats.",
	Kind.BAD_REQUEST: "Pollinations rejected the request. Check the model id and the parameters.",
	Kind.SERVER: "Pollinations or the upstream model failed. Safe to retry.",
	Kind.NETWORK: "The request never reached Pollinations. Check the network and try again.",
	Kind.PARSE: "The response could not be parsed. Check the model id and the response format.",
	Kind.UNKNOWN: "The request failed for an unknown reason.",
}

## Classify a finished request. Pass `transport_result` from HTTPRequest
## (`HTTPRequest.RESULT_SUCCESS` when the HTTP round trip itself worked) to
## catch DNS, TLS and timeout failures. Use -1 when there was no transport.
static func classify(http_status: int, body: String = "", transport_result: int = -1) -> Kind:
	if transport_result != -1 and transport_result != HTTPRequest.RESULT_SUCCESS:
		return Kind.NETWORK
	if http_status == 0:
		return Kind.NETWORK
	if http_status == 401 or http_status == 403:
		return Kind.AUTH
	if http_status == 402:
		return Kind.BALANCE
	# A drained balance can also surface as 400 or 500 with an explanatory
	# body; treat that as a balance failure whichever status it arrives with.
	if http_status >= 400 and _mentions_balance(body):
		return Kind.BALANCE
	if http_status == 429:
		return Kind.RATE_LIMIT
	if http_status >= 400 and http_status < 500:
		return Kind.BAD_REQUEST
	if http_status >= 500:
		return Kind.SERVER
	if http_status >= 200 and http_status < 300:
		return Kind.NONE
	return Kind.UNKNOWN

## True when retrying the same request has a chance of succeeding.
static func retryable(kind: Kind) -> bool:
	return kind == Kind.RATE_LIMIT or kind == Kind.SERVER or kind == Kind.NETWORK or kind == Kind.UNKNOWN

## Exponential backoff with a cap, in seconds.
static func backoff_seconds(attempt: int, base: float = 0.75, cap: float = 8.0) -> float:
	return minf(cap, base * pow(2.0, maxf(0.0, float(attempt))))

static func describe(kind: Kind, http_status: int = 0, detail: String = "") -> String:
	var name: String = KIND_NAMES.get(kind, "unknown")
	if http_status == 0 and detail.is_empty():
		return "[pollinations] %s" % name
	return "[pollinations] %s (status=%d) %s" % [name, http_status, detail.left(200)]

## Name of a kind, for logs and UI.
static func kind_name(kind: Kind) -> String:
	return KIND_NAMES.get(kind, "unknown")

## Player-facing explanation of a kind.
static func message(kind: Kind) -> String:
	return KIND_MESSAGES.get(kind, KIND_MESSAGES[Kind.UNKNOWN])

static func _mentions_balance(body: String) -> bool:
	var lowered := body.to_lower()
	return lowered.contains("insufficient balance") or lowered.contains("insufficient_balance") or lowered.contains("no pollen")
