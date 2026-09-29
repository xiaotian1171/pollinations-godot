class_name TestNodes
extends RefCounted

const CHAT_BODY := '{"model":"nova-fast","choices":[{"message":{"role":"assistant","content":"  A quiet mill.  "}}],"usage":{"total_tokens":12}}'

static func _node(transport: FakeTransport) -> PollinationsText:
	var node := PollinationsText.new()
	node.client = PollinationsClient.new()
	node.client.sleep = func(_seconds: float) -> void: pass
	node.client.transport = transport.callable()
	node.add_child(node.client)
	return node

static func run() -> void:
	PollinationsTest.suite("text node")

	# response shapes
	PollinationsTest.equal(
		PollinationsText.extract_text(JSON.parse_string(CHAT_BODY)),
		"A quiet mill.",
		"the OpenAI shape is read and trimmed"
	)
	PollinationsTest.equal(PollinationsText.extract_text("  hi  "), "hi", "a bare string is read")
	PollinationsTest.equal(
		PollinationsText.extract_text({"content": [{"type": "text", "text": "a"}, {"type": "text", "text": "b"}]}),
		"ab",
		"typed content parts are joined"
	)
	PollinationsTest.equal(PollinationsText.extract_text({"text": "plain"}), "plain", "a flat text field is read")
	PollinationsTest.equal(PollinationsText.extract_text({"error": "nope"}), "", "an error body has no text")
	PollinationsTest.equal(PollinationsText.extract_text(null), "", "nothing has no text")
	PollinationsTest.equal(PollinationsText.extract_text([{"content": "x"}, {"content": "y"}]), "x\ny", "a list of results is joined")

	PollinationsTest.equal(str(PollinationsText.extract_model(JSON.parse_string(CHAT_BODY))), "nova-fast", "the model is read")
	PollinationsTest.equal(int(PollinationsText.extract_usage(JSON.parse_string(CHAT_BODY)).get("total_tokens", 0)), 12, "usage is read")
	PollinationsTest.equal(PollinationsText.extract_model("nope"), "", "a string has no model")

	# messages
	var node := PollinationsText.new()
	node.system_prompt = ""
	var messages := node.build_messages("hello")
	PollinationsTest.equal(messages.size(), 1, "one user message without a persona")
	PollinationsTest.equal(str(messages[0]["role"]), "user", "the message is from the user")
	node.system_prompt = "You are the miller."
	messages = node.build_messages("hello")
	PollinationsTest.equal(messages.size(), 2, "a persona adds a system message")
	PollinationsTest.equal(str(messages[0]["role"]), "system", "the persona comes first")
	node.free()

	# a chat round trip
	var transport := FakeTransport.new()
	transport.responses = [FakeTransport.response(200, CHAT_BODY)]
	node = _node(transport)
	var result: Dictionary = await node.chat(node.build_messages("hi"))
	PollinationsTest.check(bool(result.get("ok", false)), "the chat succeeds")
	PollinationsTest.equal(str(result.get("content", "")), "A quiet mill.", "the answer is extracted")
	PollinationsTest.equal(str(result.get("model", "")), "nova-fast", "the model is reported")
	PollinationsTest.equal(str(transport.requests[0].get("url", "")), "https://gen.pollinations.ai/v1/chat/completions", "the chat route is used")
	var payload := transport.body_json(0)
	PollinationsTest.equal(str(payload.get("model", "")), PollinationsConfig.DEFAULT_TEXT_MODEL, "the default model is sent")
	PollinationsTest.check(not payload.has("max_tokens"), "an unset max_tokens is not sent")
	PollinationsTest.check(payload.has("temperature"), "the temperature is sent")
	node.free()

	# optional parameters
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, CHAT_BODY)]
	node = _node(transport)
	node.max_tokens = 64
	node.temperature = 0.0
	result = await node.chat(node.build_messages("hi"))
	payload = transport.body_json(0)
	PollinationsTest.equal(int(payload.get("max_tokens", 0)), 64, "max_tokens is sent when set")
	PollinationsTest.check(not payload.has("temperature"), "a zero temperature is left out")
	node.free()

	# a 200 with no text is a parse failure, not a silent empty answer
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, '{"choices":[]}')]
	node = _node(transport)
	result = await node.chat([{"role": "user", "content": "hi"}])
	PollinationsTest.check(not bool(result.get("ok", true)), "a textless 200 is a failure")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.PARSE, "a textless 200 is a parse failure")
	node.free()

	# the quick route accepts a plain-text body
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, "  A single line.  ")]
	node = _node(transport)
	result = await node.quick("say hi", 42)
	PollinationsTest.check(bool(result.get("ok", false)), "the prompt route succeeds")
	PollinationsTest.equal(str(result.get("content", "")), "A single line.", "the plain body is the answer")
	PollinationsTest.equal(
		str(transport.requests[0].get("url", "")),
		"https://gen.pollinations.ai/text/say%20hi?model=nova-fast&seed=42",
		"the prompt route is built correctly"
	)
	node.free()

	# ...and a JSON one
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, CHAT_BODY)]
	node = _node(transport)
	result = await node.quick("say hi")
	PollinationsTest.equal(str(result.get("content", "")), "A quiet mill.", "a JSON prompt response is read too")
	node.free()

	# failures are reported, and the signal always fires
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(402, '{"error":"insufficient balance"}')]
	node = _node(transport)
	var seen: Array = []
	node.generated.connect(func(r: Dictionary) -> void: seen.append(r))
	result = await node.generate("hi")
	PollinationsTest.equal(seen.size(), 1, "the signal fires on failure too")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.BALANCE, "the failure kind survives")
	node.free()
