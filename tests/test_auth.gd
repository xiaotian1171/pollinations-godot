class_name TestAuth
extends RefCounted

const DEVICE_CODE_BODY := '{"device_code":"dc_123","user_code":"WXYZ-1234","verification_uri":"/device","expires_in":600,"interval":5}'
const PENDING_BODY := '{"error":"authorization_pending"}'
const GRANTED_BODY := '{"access_token":"sk_player","token_type":"bearer"}'
const USERINFO_BODY := '{"sub":"42","preferred_username":"miller"}'

static func _node(transport: FakeTransport) -> PollinationsAuth:
	var node := PollinationsAuth.new()
	node.client = PollinationsClient.new()
	node.client.sleep = func(_seconds: float) -> void: pass
	node.client.transport = transport.callable()
	node.sleep = func(_seconds: float) -> void: pass
	node.remember = false
	node.add_child(node.client)
	return node

static func run() -> void:
	PollinationsTest.suite("auth node")

	# reading the device code
	var code := PollinationsAuth.parse_device_code(JSON.parse_string(DEVICE_CODE_BODY))
	PollinationsTest.check(bool(code["ok"]), "a device code is understood")
	PollinationsTest.equal(str(code["device_code"]), "dc_123", "the device code is kept")
	PollinationsTest.equal(str(code["user_code"]), "WXYZ-1234", "the user code is kept")
	PollinationsTest.equal(str(code["verification_url"]), "https://enter.pollinations.ai/device", "a relative path becomes a link")
	PollinationsTest.equal(int(code["expires_in"]), 600, "the expiry is kept")
	PollinationsTest.equal(float(code["interval"]), 5.0, "the interval is kept")
	PollinationsTest.check(not bool(PollinationsAuth.parse_device_code(null)["ok"]), "nothing is not a device code")
	PollinationsTest.check(not bool(PollinationsAuth.parse_device_code({"error": "bad client"})["ok"]), "an error is not a device code")

	PollinationsTest.equal(
		PollinationsAuth.url_for_verification("https://enter.pollinations.ai/device"),
		"https://enter.pollinations.ai/device",
		"an absolute link is kept"
	)
	PollinationsTest.equal(
		PollinationsAuth.url_for_verification("device"),
		"https://enter.pollinations.ai/device",
		"a bare path becomes a link"
	)
	PollinationsTest.equal(
		PollinationsAuth.url_for_verification(""),
		"https://enter.pollinations.ai/device",
		"an empty path falls back to the device page"
	)

	# reading a token poll
	PollinationsTest.equal(str(PollinationsAuth.parse_token(JSON.parse_string(PENDING_BODY))["state"]), "pending", "a pending poll is pending")
	PollinationsTest.equal(str(PollinationsAuth.parse_token(JSON.parse_string(GRANTED_BODY))["state"]), "granted", "a token is granted")
	PollinationsTest.equal(str(PollinationsAuth.parse_token(JSON.parse_string(GRANTED_BODY))["key"]), "sk_player", "the key comes back")
	PollinationsTest.equal(str(PollinationsAuth.parse_token(JSON.parse_string('{"error":"slow_down"}'))["state"]), "pending", "slow_down keeps polling")
	PollinationsTest.check(float(PollinationsAuth.parse_token(JSON.parse_string('{"error":"slow_down"}'))["interval"]) > 0.0, "slow_down asks for a longer interval")
	PollinationsTest.equal(str(PollinationsAuth.parse_token(JSON.parse_string('{"error":"expired_token"}'))["state"]), "error", "an expired code is an error")
	PollinationsTest.equal(str(PollinationsAuth.parse_token(JSON.parse_string('{"error":"access_denied"}'))["state"]), "error", "a denied sign-in is an error")
	PollinationsTest.equal(str(PollinationsAuth.parse_token(JSON.parse_string('{"error":"whatever"}'))["state"]), "error", "an unknown error is an error")
	PollinationsTest.equal(str(PollinationsAuth.parse_token(null, 400)["state"]), "error", "a rejected poll with no body is an error")
	PollinationsTest.equal(str(PollinationsAuth.parse_token("junk", 200)["state"]), "pending", "an unreadable 200 keeps polling")

	# a whole sign-in, scripted: the player approves on the third poll
	var transport := FakeTransport.new()
	transport.responses = [
		FakeTransport.response(200, DEVICE_CODE_BODY),
		FakeTransport.response(400, PENDING_BODY),
		FakeTransport.response(400, PENDING_BODY),
		FakeTransport.response(200, GRANTED_BODY),
		FakeTransport.response(200, USERINFO_BODY),
	]
	var node := _node(transport)
	var codes: Array = []
	var users: Array = []
	var problems: Array = []
	node.code_ready.connect(func(user_code: String, url: String, expires: int) -> void:
		codes.append({"user_code": user_code, "url": url, "expires": expires})
	)
	node.signed_in.connect(func(user: Dictionary) -> void: users.append(user))
	node.failed.connect(func(kind: int, message: String) -> void: problems.append(message))
	PollinationsConfig.clear_api_key(true)
	var result: Dictionary = await node.sign_in()
	PollinationsTest.check(bool(result.get("ok", false)), "the sign-in succeeds")
	PollinationsTest.equal(problems.size(), 0, "no failure was reported")
	PollinationsTest.equal(codes.size(), 1, "the player is told the code once")
	PollinationsTest.equal(str(codes[0]["user_code"]), "WXYZ-1234", "the code shown is the user code")
	PollinationsTest.equal(str(codes[0]["url"]), "https://enter.pollinations.ai/device", "the link shown is the device page")
	PollinationsTest.equal(users.size(), 1, "the signed-in signal fires")
	PollinationsTest.equal(str(users[0].get("preferred_username", "")), "miller", "the profile comes with it")
	PollinationsTest.equal(str(result.get("key", "")), "sk_player", "the key is returned")
	PollinationsTest.equal(PollinationsConfig.api_key(), "sk_player", "the key is ready for the next request")
	PollinationsTest.equal(transport.requests.size(), 5, "the poll ran until it was approved")
	PollinationsTest.equal(str(transport.requests[0].get("url", "")), "https://enter.pollinations.ai/api/device/code", "the flow starts at the device code route")
	PollinationsTest.equal(str(transport.body_json(0).get("client_id", "")), PollinationsConfig.DEFAULT_APP_KEY, "the app key identifies the game")
	PollinationsTest.equal(str(transport.requests[1].get("url", "")), "https://enter.pollinations.ai/api/device/token", "the flow polls the token route")
	PollinationsTest.equal(str(transport.body_json(1).get("device_code", "")), "dc_123", "the poll sends the device code")
	PollinationsTest.equal(transport.header_of(4, "Authorization"), "Bearer sk_player", "the profile request is signed")
	node.free()
	PollinationsConfig.clear_api_key(true)

	# a denied sign-in reports the failure
	transport = FakeTransport.new()
	transport.responses = [
		FakeTransport.response(200, DEVICE_CODE_BODY),
		FakeTransport.response(400, '{"error":"access_denied"}'),
	]
	node = _node(transport)
	result = await node.sign_in()
	PollinationsTest.check(not bool(result.get("ok", true)), "a denied sign-in fails")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.AUTH, "a denied sign-in is an auth failure")
	PollinationsTest.equal(transport.requests.size(), 2, "polling stops at once")
	node.free()

	# a broken device-code request reports the transport failure
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(500, '{"error":"boom"}')]
	node = _node(transport)
	result = await node.sign_in()
	PollinationsTest.check(not bool(result.get("ok", true)), "a failed start fails the flow")
	node.free()

	# signing out forgets the key
	PollinationsConfig.set_api_key("sk_player", false)
	var other := PollinationsAuth.new()
	other.sign_out()
	PollinationsTest.equal(PollinationsConfig.api_key(), "", "signing out forgets the key")
	other.free()
