extends SceneTree

## Talks to the real Pollinations API and prints what came back. This is the
## evidence script: it is not part of the offline suite, and it needs network
## access. Signed calls use POLLINATIONS_API_KEY when it is set; the anonymous
## calls run either way.
##
##   POLLINATIONS_API_KEY=sk_... godot --headless --path . --script tests/live_check.gd

var _finished := false
var _failures: PackedStringArray = PackedStringArray()

## Started in `_initialize`, never awaited from `_process`: the real HTTP calls
## suspend, and an unresolved coroutine would be read as "quit now".
func _initialize() -> void:
	_run()

func _process(_delta: float) -> bool:
	return _finished

func _run() -> void:
	# one frame first: a node added during _initialize is not in the tree yet,
	# and HTTPRequest refuses to start outside the tree
	await process_frame
	await _run_all()
	_finished = true
	quit(1 if _failures.size() > 0 else 0)

func _run_all() -> void:
	var client := PollinationsClient.new()
	client.timeout_seconds = 180.0
	client.debug = true
	get_root().add_child(client)

	print("=== Pollinations live check")
	print("Godot %s | signed: %s" % [
		Engine.get_version_info()["string"],
		"yes" if PollinationsConfig.has_api_key() else "no key set",
	])

	await _check_anonymous(client)
	await _check_quick_route(client)
	await _check_signed_chat(client)
	await _check_catalog(client, "text")
	await _check_catalog(client, "image")
	await _check_catalog(client, "audio")
	await _check_image(client)
	await _check_speech(client)
	await _check_device_flow(client)

	print("=== live check finished: %d failing step(s)" % _failures.size())
	for failure: String in _failures:
		print("  ! %s" % failure)

func _timer() -> int:
	return Time.get_ticks_msec()

func _elapsed(started: int) -> String:
	return "%.2fs" % ((Time.get_ticks_msec() - started) / 1000.0)

func _fail(message: String) -> void:
	_failures.append(message)

## A request with no Authorization header at all, to document what the API
## answers without a key.
func _check_anonymous(client: PollinationsClient) -> void:
	var started := _timer()
	var result: Dictionary = await client.send("GET", PollinationsUrls.text_prompt("Reply with the word pollen.", "nova-fast", 1), PackedStringArray(), "")
	print("[anonymous] ok=%s status=%d kind=%s attempts=%d %s" % [
		result.get("ok"), result.get("status"), result.get("kind_name"), result.get("attempts"), _elapsed(started)
	])
	if not result.get("ok", false):
		print("            body=%s" % str(result.get("error", "")).left(160))

## The cheap single-prompt route, through the node that games use.
func _check_quick_route(client: PollinationsClient) -> void:
	if not PollinationsConfig.has_api_key():
		print("[prompt route] skipped, no key")
		return
	var node := PollinationsText.new()
	node.client = client
	get_root().add_child(node)
	var started := _timer()
	var result: Dictionary = await node.quick("Reply with the word pollen.", 1)
	print("[prompt route] ok=%s status=%d attempts=%d %s" % [
		result.get("ok"), result.get("status"), result.get("attempts"), _elapsed(started)
	])
	if result.get("ok", false):
		print("            content=%s" % str(result.get("content", "")).left(120))
	else:
		print("            kind=%s error=%s" % [result.get("kind_name"), result.get("error")])
		_fail("the prompt route failed: %s" % str(result.get("error")))
	node.free()

func _check_signed_chat(client: PollinationsClient) -> void:
	if not PollinationsConfig.has_api_key():
		print("[chat] skipped, no key")
		return
	var node := PollinationsText.new()
	node.client = client
	node.system_prompt = "Answer in one short sentence."
	node.model = PollinationsConfig.DEFAULT_TEXT_MODEL
	get_root().add_child(node)
	var started := _timer()
	var result: Dictionary = await node.generate("Describe a watermill in one sentence.")
	print("[chat] ok=%s status=%d attempts=%d %s" % [
		result.get("ok"), result.get("status"), result.get("attempts"), _elapsed(started)
	])
	if result.get("ok", false):
		print("            model=%s content=%s" % [result.get("model"), result.get("content")])
		print("            usage=%s" % JSON.stringify(result.get("usage")))
	else:
		print("            kind=%s error=%s" % [result.get("kind_name"), result.get("error")])
		_fail("signed chat failed: %s" % str(result.get("error")))
	node.free()

func _check_catalog(client: PollinationsClient, modality: String) -> void:
	var node := PollinationsCatalog.new()
	node.client = client
	get_root().add_child(node)
	var started := _timer()
	var result: Dictionary = await node.fetch(modality)
	if result.get("ok", false):
		var supported := node.supporting(endpoint_for(modality))
		print("[catalog %s] %d entries, %d usable here, %s" % [
			modality, node.models.size(), supported.size(), _elapsed(started)
		])
		print("            first ids: %s" % str(node.ids().slice(0, 5)))
	else:
		print("[catalog %s] failed: %s" % [modality, result.get("error")])
		# the audio catalogue is the one that can be missing upstream, so it is
		# reported rather than counted as a broken add-on
		if modality != "audio":
			_fail("catalogue %s failed" % modality)
	node.free()

func endpoint_for(modality: String) -> String:
	match modality:
		"image":
			return "/image/{prompt}"
		"audio":
			return "/v1/audio/speech"
	return "/v1/chat/completions"

func _check_image(client: PollinationsClient) -> void:
	if not PollinationsConfig.has_api_key():
		print("[image] skipped, no key")
		return
	var node := PollinationsImage.new()
	node.client = client
	node.width = 256
	node.height = 256
	node.seed = 11
	get_root().add_child(node)
	var started := _timer()
	var result: Dictionary = await node.generate("a wooden watermill, flat illustration")
	if result.get("ok", false):
		print("[image] ok status=%d %s mime=%s size=%s bytes=%d" % [
			result.get("status"), _elapsed(started), result.get("mime"),
			str(result.get("size")), (result.get("bytes") as PackedByteArray).size(),
		])
		print("            texture=%s" % str(result.get("texture") != null))
	else:
		print("[image] kind=%s status=%d error=%s" % [
			result.get("kind_name"), result.get("status"), result.get("error")
		])
		_fail("image generation failed")
	node.free()

func _check_speech(client: PollinationsClient) -> void:
	if not PollinationsConfig.has_api_key():
		print("[speech] skipped, no key")
		return
	var node := PollinationsSpeech.new()
	node.client = client
	node.response_format = "mp3"
	get_root().add_child(node)
	var started := _timer()
	var result: Dictionary = await node.generate("Welcome to Pollen Village.")
	if result.get("ok", false):
		print("[speech] ok status=%d %s bytes=%d length=%.2fs" % [
			result.get("status"), _elapsed(started),
			(result.get("bytes") as PackedByteArray).size(), float(result.get("length", 0.0)),
		])
	elif int(result.get("kind", -1)) == PollinationsErrors.Kind.BALANCE:
		# Speech models are only served to accounts with paid pollen; the
		# request shape and the error classification are what this step checks.
		print("[speech] 402 balance as expected for a free account: %s" % str(result.get("message", "")))
	else:
		print("[speech] kind=%s status=%d error=%s" % [
			result.get("kind_name"), result.get("status"), result.get("error")
		])
		_fail("speech generation failed")
	node.free()

## The device flow, checked without approving anything: a code is requested,
## then polled once, which must answer "authorization_pending".
func _check_device_flow(client: PollinationsClient) -> void:
	var started := _timer()
	var start: Dictionary = await client.post_json(PollinationsUrls.device_code(), {"client_id": PollinationsConfig.app_key()})
	print("[device code] ok=%s status=%d %s" % [start.get("ok"), start.get("status"), _elapsed(started)])
	if not start.get("ok", false):
		print("            body=%s" % str(start.get("text", "")).left(200))
		print("            (set pollinations/app_key to a pk_ key of your own app)")
		return
	var code := PollinationsAuth.parse_device_code(start.get("json"))
	print("            parsed=%s user_code=%s url=%s interval=%s expires_in=%s" % [
		code.get("ok"), code.get("user_code"), code.get("verification_url"),
		code.get("interval"), code.get("expires_in"),
	])
	if not code.get("ok", false):
		_fail("the device code response was not understood")
		return
	var poll: Dictionary = await client.post_json(PollinationsUrls.device_token(), {"device_code": code["device_code"]})
	var state := PollinationsAuth.parse_token(poll.get("json"), int(poll.get("status", 0)))
	print("[device token] status=%d state=%s (pending is correct: nobody approved)" % [
		poll.get("status"), state.get("state")
	])
	if str(state.get("state", "")) != "pending":
		_fail("an unapproved device code should be pending, got %s" % str(state.get("state")))
