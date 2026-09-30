extends SceneTree

## The whole BYOP sign-in with a person really approving the code: a code is
## requested, printed for the player, polled until it is approved (or expires),
## the granted key is read back, and then that key is used for a real text call
## and a real speech call before the player's profile is fetched.
##
## ```
## POLLINATIONS_APP_KEY=pk_... godot --headless --path . --script tests/device_flow_check.gd
## ```
##
## Approve the printed code at the printed URL before it expires. The run writes
## what happened, line by line, to tests/evidence/device_flow.txt.
##
## `tests/live_check.gd` covers the same flow with nobody approving: a code is
## requested and the poll must answer `authorization_pending`. This one is the
## other half, the part a stub cannot show.

var _finished := false
var _log: PackedStringArray = PackedStringArray()
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run()

func _process(_delta: float) -> bool:
	return _finished

func _run() -> void:
	await process_frame
	await _run_all()
	_flush()
	_finished = true
	quit(1 if _failures.size() > 0 else 0)

func _run_all() -> void:
	var client := PollinationsClient.new()
	client.timeout_seconds = 180.0
	get_root().add_child(client)

	_say("=== Pollinations device flow, with an approval")
	_say("godot %s | app key: %s" % [
		Engine.get_version_info()["string"], PollinationsConfig.app_key(),
	])

	var auth := PollinationsAuth.new()
	auth.client = client
	auth.app_key = PollinationsConfig.app_key()
	auth.remember = true
	auth.fetch_profile = true
	auth.code_ready.connect(_on_code)
	get_root().add_child(auth)

	var started := Time.get_ticks_msec()
	var result: Dictionary = await auth.sign_in()
	_say("sign_in ok=%s key=%s user=%s error=%s elapsed=%.1fs" % [
		result.get("ok"),
		"granted" if not str(result.get("key", "")).is_empty() else "none",
		JSON.stringify(result.get("user", {})).left(240),
		result.get("error"),
		(Time.get_ticks_msec() - started) / 1000.0,
	])
	if not result.get("ok", false):
		_fail("the device flow did not finish: %s" % str(result.get("error", "")))
		_summary()
		return

	# the granted key belongs to the player who approved: use it for real calls
	var text := PollinationsText.new()
	text.client = client
	get_root().add_child(text)
	var answer: Dictionary = await text.generate("Reply with exactly: the pipes are warm.")
	_say("text with the granted key: ok=%s status=%d model=%s answer=%s" % [
		answer.get("ok"), answer.get("status"), answer.get("model"),
		str(answer.get("text", "")).strip_edges().left(120),
	])
	if not answer.get("ok", false):
		_fail("a text call with the granted key failed")

	var speech := PollinationsSpeech.new()
	speech.client = client
	speech.response_format = "mp3"
	get_root().add_child(speech)
	var spoken: Dictionary = await speech.generate("The pipes are warm.")
	var spoken_bytes: int = (spoken.get("bytes", PackedByteArray()) as PackedByteArray).size()
	_say("speech with the granted key: ok=%s status=%d model=%s bytes=%d length=%.2fs" % [
		spoken.get("ok"), spoken.get("status"), speech.model, spoken_bytes,
		float(spoken.get("length", 0.0)),
	])
	if not spoken.get("ok", false):
		_fail("a speech call with the granted key failed: %s" % str(spoken.get("error", "")))

	_say("key stored on this device: %s" % ("yes" if PollinationsConfig.has_api_key() else "no"))
	_summary()

func _summary() -> void:
	_say("=== device flow finished: %d failing step(s)" % _failures.size())
	for failure: String in _failures:
		_say("  ! %s" % failure)

func _on_code(user_code: String, url: String, expires_in: int) -> void:
	_say("code=%s url=%s expires_in=%ds — waiting for the approval" % [user_code, url, expires_in])

func _fail(message: String) -> void:
	_failures.append(message)

func _say(line: String) -> void:
	print(line)
	_log.append(line)
	_flush()

func _flush() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/evidence")
	var file := FileAccess.open("res://tests/evidence/device_flow.txt", FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(_log) + "\n")
	file.close()
