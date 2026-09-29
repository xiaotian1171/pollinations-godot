class_name TestSpeech
extends RefCounted

static func _node(transport: FakeTransport) -> PollinationsSpeech:
	var node := PollinationsSpeech.new()
	node.client = PollinationsClient.new()
	node.client.transport = transport.callable()
	node.add_child(node.client)
	return node

static func run() -> void:
	PollinationsTest.suite("speech node")

	PollinationsTest.check(PollinationsSpeech.can_decode("mp3"), "mp3 decodes in memory")
	PollinationsTest.check(PollinationsSpeech.can_decode("WAV"), "wav decodes in memory")
	PollinationsTest.check(PollinationsSpeech.can_decode("ogg"), "ogg decodes in memory")
	PollinationsTest.check(not PollinationsSpeech.can_decode("aac"), "aac needs a file")
	PollinationsTest.check(not PollinationsSpeech.can_decode("pcm"), "raw pcm needs more than a buffer")
	PollinationsTest.equal(PollinationsSpeech.build_stream(PackedByteArray(), "mp3"), null, "empty audio makes no stream")
	PollinationsTest.equal(PollinationsSpeech.build_stream("not audio".to_utf8_buffer(), "aac"), null, "unsupported formats make no stream")

	# the request body
	var transport := FakeTransport.new()
	transport.responses = [FakeTransport.response(200, "")]
	var node := _node(transport)
	node.voice = "alloy"
	node.response_format = "mp3"
	node.instructions = ""
	var result: Dictionary = await node.generate("Welcome to Pollen Village.")
	var payload := transport.body_json(0)
	PollinationsTest.equal(str(transport.requests[0].get("url", "")), "https://gen.pollinations.ai/v1/audio/speech", "the speech route is used")
	PollinationsTest.equal(str(payload.get("input", "")), "Welcome to Pollen Village.", "the text is sent as input")
	PollinationsTest.equal(str(payload.get("voice", "")), "alloy", "the voice is sent")
	PollinationsTest.equal(str(payload.get("response_format", "")), "mp3", "the format is sent")
	PollinationsTest.check(payload.has("model"), "the model is sent")
	PollinationsTest.check(not payload.has("instructions"), "empty instructions are left out")
	# an empty body cannot be decoded, so this request is a parse failure
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.PARSE, "an empty audio body is a parse failure")
	node.free()

	# instructions are sent when set
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, "")]
	node = _node(transport)
	node.instructions = "whisper"
	result = await node.generate("hello")
	payload = transport.body_json(0)
	PollinationsTest.equal(str(payload.get("instructions", "")), "whisper", "instructions are sent when set")
	node.free()

	# an API failure is reported as-is
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(429, '{"error":"slow down"}')]
	node = _node(transport)
	node.client.max_retries = 0
	result = await node.generate("hello")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.RATE_LIMIT, "a rate limit is reported")
	PollinationsTest.check(result.get("stream") == null, "a failure carries no stream")
	node.free()
