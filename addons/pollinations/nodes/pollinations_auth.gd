class_name PollinationsAuth
extends PollinationsNode

## Sign-in for players, using the Pollinations device flow (BYOP: bring your
## own pollen). The game shows a short code, the player approves it on the
## Pollinations site with their own account, and the game receives a key that
## belongs to that player -- so the player pays for their own generations and
## the game never ships a secret.
##
##	var auth := PollinationsAuth.new()
##	add_child(auth)
##	auth.code_ready.connect(func(code, url, _s): print("Open %s and enter %s" % [url, code]))
##	auth.sign_in()

## Emitted as soon as there is a code to show the player.
signal code_ready(user_code: String, verification_url: String, expires_in_seconds: int)
## Emitted once the player approved and a key is stored.
signal signed_in(user: Dictionary)
## Emitted when the flow cannot continue.
signal failed(kind: PollinationsErrors.Kind, message: String)

## `pk_...` app key of your game. Falls back to the project setting.
@export var app_key: String = ""
## How often to ask whether the player approved yet.
@export var poll_interval_seconds: float = 5.0
## How long a code stays valid.
@export var expires_in_seconds: int = 600
## Keep the key on this device so the player stays signed in after a restart.
@export var remember: bool = true
## Fetch the player's profile after signing in.
@export var fetch_profile: bool = true

## Optional `func(seconds: float)` replacement for waiting, used by the tests.
var sleep: Callable = Callable()

## Runs the whole device flow and waits for the outcome.
func sign_in() -> Dictionary:
	var client := ensure_client()
	var client_id := app_key.strip_edges()
	if client_id.is_empty():
		client_id = PollinationsConfig.app_key()
	if client_id.is_empty():
		return _fail(PollinationsErrors.Kind.BAD_REQUEST, "set your game's publishable app key (pk_...) before signing in", 0)
	var start: Dictionary = await client.post_json(PollinationsUrls.device_code(), {"client_id": client_id})
	var code := parse_device_code(start.get("json"))
	if not code.get("ok", false):
		return _fail(
			PollinationsErrors.Kind.BAD_REQUEST if start.get("ok", false) else int(start.get("kind", PollinationsErrors.Kind.UNKNOWN)),
			"the device code request failed: %s" % str(start.get("error", "")),
			int(start.get("status", 0))
		)
	code_ready.emit(code["user_code"], code["verification_url"], int(code["expires_in"]))
	var deadline := Time.get_ticks_msec() + int(code["expires_in"]) * 1000
	var interval: float = maxf(1.0, code["interval"])
	while true:
		await _wait(interval)
		if Time.get_ticks_msec() > deadline:
			return _fail(
				PollinationsErrors.Kind.BAD_REQUEST,
				"the sign-in code expired before it was approved",
				0
			)
		var poll: Dictionary = await client.post_json(PollinationsUrls.device_token(), {"device_code": code["device_code"]})
		var state := parse_token(poll.get("json"), int(poll.get("status", 0)))
		match state["state"]:
			"granted":
				var key: String = state["key"]
				PollinationsConfig.set_api_key(key, remember)
				var user: Dictionary = {}
				if fetch_profile:
					var profile := await fetch_userinfo()
					if profile.get("ok", false) and profile.get("json") is Dictionary:
						user = profile["json"]
				signed_in.emit(user)
				return {
					"ok": true,
					"kind": PollinationsErrors.Kind.NONE,
					"key": key,
					"user": user,
					"error": "",
				}
			"error":
				return _fail(PollinationsErrors.Kind.AUTH, str(state["error"]), int(poll.get("status", 0)))
			_:
				interval = maxf(interval, float(state.get("interval", interval)))
				continue
	return _fail(PollinationsErrors.Kind.UNKNOWN, "the sign-in flow stopped unexpectedly", 0)

## Forgets the key on this device.
func sign_out() -> void:
	PollinationsConfig.clear_api_key()

## The signed-in player's profile, when the key has the profile scope.
func fetch_userinfo() -> Dictionary:
	var client := ensure_client()
	return await client.get_json(PollinationsUrls.device_userinfo(), PollinationsConfig.authorization_headers())

## Reads the device-code response. Accepts the documented shape and the OAuth
## spelling of it (`verification_uri`).
static func parse_device_code(json: Variant) -> Dictionary:
	var out := {
		"ok": false,
		"device_code": "",
		"user_code": "",
		"verification_url": "",
		"interval": 5.0,
		"expires_in": 600,
	}
	if not json is Dictionary:
		return out
	var dict: Dictionary = json
	var device_code := str(dict.get("device_code", "")).strip_edges()
	if device_code.is_empty():
		return out
	out["ok"] = true
	out["device_code"] = device_code
	out["user_code"] = str(dict.get("user_code", "")).strip_edges()
	out["interval"] = maxf(1.0, float(dict.get("interval", 5.0)))
	out["expires_in"] = int(dict.get("expires_in", 600))
	var uri := str(dict.get("verification_uri", dict.get("verification_url", "/device")))
	out["verification_url"] = url_for_verification(uri)
	return out

## Reads a token-poll response into one of three states: "pending", "granted"
## or "error".
static func parse_token(json: Variant, http_status: int = 0) -> Dictionary:
	var out := {"state": "pending", "key": "", "error": "", "interval": 0.0}
	if json is Dictionary:
		var dict: Dictionary = json
		var token := str(dict.get("access_token", "")).strip_edges()
		if not token.is_empty():
			out["state"] = "granted"
			out["key"] = token
			return out
		var error := str(dict.get("error", "")).strip_edges()
		match error:
			"authorization_pending":
				return out
			"slow_down":
				out["interval"] = 5.0
				return out
			"expired_token":
				out["state"] = "error"
				out["error"] = "the sign-in code expired"
				return out
			"access_denied":
				out["state"] = "error"
				out["error"] = "the player denied the sign-in request"
				return out
			"":
				pass
			_:
				out["state"] = "error"
				out["error"] = error
				return out
	if http_status >= 400:
		out["state"] = "error"
		out["error"] = "the token request was rejected (status %d)" % http_status
	return out

## Turns the `verification_uri` from the API into something a player can open.
static func url_for_verification(uri: String) -> String:
	var trimmed := uri.strip_edges()
	if trimmed.is_empty():
		return PollinationsUrls.device_verification_page()
	if trimmed.begins_with("http://") or trimmed.begins_with("https://"):
		return trimmed
	if not trimmed.begins_with("/"):
		trimmed = "/" + trimmed
	return PollinationsUrls.ENTER_BASE + trimmed

func _wait(seconds: float) -> void:
	if sleep.is_valid():
		await sleep.call(seconds)
		return
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout
	else:
		await Engine.get_main_loop().create_timer(seconds).timeout

func _fail(kind: PollinationsErrors.Kind, message: String, status: int) -> Dictionary:
	var text := PollinationsErrors.describe(kind, status, message)
	failed.emit(kind, text)
	return {
		"ok": false,
		"kind": kind,
		"kind_name": PollinationsErrors.kind_name(kind),
		"status": status,
		"key": "",
		"user": {},
		"error": text,
	}
