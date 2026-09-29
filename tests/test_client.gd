class_name TestClient
extends RefCounted

const OPENAI_BODY := '{"choices":[{"message":{"role":"assistant","content":"hello"}}],"usage":{"total_tokens":11},"model":"nova-fast"}'

## A client wired to a scripted transport, with the waiting removed so the
## tests never depend on the frame loop.
static func _make(transport: FakeTransport) -> PollinationsClient:
	var client := PollinationsClient.new()
	client.sleep = func(_seconds: float) -> void: pass
	client.transport = transport.callable()
	return client

static func run() -> void:
	PollinationsTest.suite("client")

	# method names are translated for HTTPRequest
	PollinationsTest.equal(PollinationsClient.http_method("get"), HTTPClient.METHOD_GET, "GET is translated")
	PollinationsTest.equal(PollinationsClient.http_method("POST"), HTTPClient.METHOD_POST, "POST is translated")
	PollinationsTest.equal(PollinationsClient.http_method(" patch "), HTTPClient.METHOD_PATCH, "PATCH is translated and trimmed")

	# a normal success
	var transport := FakeTransport.new()
	transport.responses = [FakeTransport.response(200, OPENAI_BODY)]
	var client := _make(transport)
	var result: Dictionary = await client.send("POST", "https://gen.pollinations.ai/v1/chat/completions", PackedStringArray(), "{}")
	PollinationsTest.check(bool(result.get("ok", false)), "a 200 is a success")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.NONE, "a 200 has no error kind")
	PollinationsTest.equal(int(result.get("attempts", 0)), 1, "a 200 takes one attempt")
	PollinationsTest.equal(str(result.get("text", "")), OPENAI_BODY, "the raw body is kept")
	PollinationsTest.check(result.get("json") is Dictionary, "the body is decoded")
	PollinationsTest.equal(transport.requests.size(), 1, "only one request was made")
	client.free()

	# rate limits are retried with backoff, then succeed
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(429, '{"error":"slow down"}'), FakeTransport.response(200, OPENAI_BODY)]
	client = _make(transport)
	result = await client.send("POST", "https://example.invalid", PackedStringArray(), "{}")
	PollinationsTest.check(bool(result.get("ok", false)), "a retried rate limit succeeds")
	PollinationsTest.equal(int(result.get("attempts", 0)), 2, "the retry is counted")
	PollinationsTest.equal(transport.requests.size(), 2, "the request was repeated")
	client.free()

	# balance and auth failures are never retried
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(402, '{"error":"insufficient balance"}')]
	client = _make(transport)
	result = await client.send("POST", "https://example.invalid", PackedStringArray(), "{}")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.BALANCE, "402 is a balance failure")
	PollinationsTest.equal(transport.requests.size(), 1, "a balance failure is not retried")
	PollinationsTest.contains(str(result.get("message", "")), "pollen", "the balance failure explains itself")
	client.free()

	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(401, '{"error":"invalid key"}')]
	client = _make(transport)
	result = await client.send("GET", "https://example.invalid", PackedStringArray(), "")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.AUTH, "401 is an auth failure")
	PollinationsTest.equal(transport.requests.size(), 1, "an auth failure is not retried")
	PollinationsTest.equal(int(result.get("status", 0)), 401, "the status is reported")
	client.free()

	# a persistent server error gives up after max_retries
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(500, '{"error":"boom"}')]
	client = _make(transport)
	result = await client.send("GET", "https://example.invalid", PackedStringArray(), "")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.SERVER, "500 is a server failure")
	PollinationsTest.equal(int(result.get("attempts", 0)), 3, "a server failure is retried twice")
	PollinationsTest.equal(transport.requests.size(), 3, "one request per attempt")
	PollinationsTest.check(not bool(result.get("ok", true)), "a failure is not ok")
	client.free()

	# retries can be switched off
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(503, "nope")]
	client = _make(transport)
	client.max_retries = 0
	result = await client.send("GET", "https://example.invalid", PackedStringArray(), "")
	PollinationsTest.equal(transport.requests.size(), 1, "max_retries = 0 means one attempt")
	client.free()

	# a broken connection is a network failure
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(0, "", HTTPRequest.RESULT_CANT_CONNECT)]
	client = _make(transport)
	result = await client.send("GET", "https://example.invalid", PackedStringArray(), "")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.NETWORK, "a dead connection is a network failure")
	client.free()

	# an empty body is still a success
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, "")]
	client = _make(transport)
	result = await client.send("GET", "https://example.invalid", PackedStringArray(), "")
	PollinationsTest.check(bool(result.get("ok", false)), "an empty body is not a failure")
	PollinationsTest.equal(result.get("json"), null, "an empty body decodes to nothing")
	client.free()

	# non-JSON bodies stay usable as text
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, "<svg></svg>")]
	client = _make(transport)
	result = await client.send("GET", "https://example.invalid", PackedStringArray(), "")
	PollinationsTest.check(bool(result.get("ok", false)), "a non-JSON body is not a failure")
	PollinationsTest.equal(str(result.get("text", "")), "<svg></svg>", "a non-JSON body is kept as text")
	client.free()

	# a POST declares JSON, and signs itself when a key is configured
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, "{}")]
	client = _make(transport)
	PollinationsConfig.set_api_key("sk_test")
	result = await client.post_json("https://example.invalid", {"model": "nova-fast"})
	PollinationsConfig.clear_api_key(true)
	PollinationsTest.contains(
		str(transport.requests[0].get("headers", PackedStringArray())),
		"Content-Type: application/json",
		"POSTs declare JSON"
	)
	PollinationsTest.equal(transport.header_of(0, "Authorization"), "Bearer sk_test", "POSTs are signed")
	PollinationsTest.equal(str(transport.body_json(0).get("model", "")), "nova-fast", "the payload is serialised")
	PollinationsTest.equal(str(client.last_request.get("method", "")), "POST", "the last request is remembered")
	PollinationsTest.equal(int(client.last_request.get("attempts", 0)), 1, "the last attempt count is remembered")
	client.free()

	# a binary body is kept as bytes and never decoded as text
	PollinationsTest.check(not PollinationsClient.is_textual(PackedStringArray(["Content-Type: image/png"])), "an image body is not text")
	PollinationsTest.check(not PollinationsClient.is_textual(PackedStringArray(["content-type: audio/mpeg"])), "an audio body is not text")
	PollinationsTest.check(PollinationsClient.is_textual(PackedStringArray(["Content-Type: application/json"])), "JSON is text")
	PollinationsTest.check(PollinationsClient.is_textual(PackedStringArray()), "a missing content type counts as text")
	PollinationsTest.check(PollinationsClient.is_textual(PackedStringArray(["X-Thing: 1"])), "an unrelated header does not matter")

	# an anonymous POST sends no Authorization header at all
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, "{}")]
	client = _make(transport)
	result = await client.post_json("https://example.invalid", {"model": "nova-fast"})
	PollinationsTest.equal(transport.header_of(0, "Authorization"), "", "an anonymous POST is unsigned")
	client.free()
