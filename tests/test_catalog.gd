class_name TestCatalog
extends RefCounted

const CATALOG_BODY := """[
	{"name":"amazon/nova-micro-v1","aliases":["nova-fast"],"title":"Nova Micro","supported_endpoints":["/v1/chat/completions","/text/{prompt}"]},
	{"name":"openai/gpt-6-luna","aliases":["gpt-6-luna"],"title":"GPT-6 Luna","supported_endpoints":["/v1/chat/completions"]}
]"""

static func run() -> void:
	PollinationsTest.suite("catalog node")

	var transport := FakeTransport.new()
	transport.responses = [FakeTransport.response(200, CATALOG_BODY)]
	var node := PollinationsCatalog.new()
	node.client = PollinationsClient.new()
	node.client.transport = transport.callable()
	node.add_child(node.client)
	var loaded: Array = []
	var problems: Array = []
	node.loaded.connect(func(modality: String, _models: Array) -> void: loaded.append(modality))
	node.failed.connect(func(_kind: int, message: String) -> void: problems.append(message))

	var result: Dictionary = await node.fetch("text")
	PollinationsTest.check(bool(result.get("ok", false)), "a catalogue is fetched")
	PollinationsTest.equal(transport.requests.size(), 1, "one request is made")
	PollinationsTest.equal(
		str(transport.requests[0].get("url", "")),
		"https://gen.pollinations.ai/text/models",
		"the catalogue route is built"
	)
	PollinationsTest.equal(loaded.size(), 1, "the loaded signal fires")
	PollinationsTest.equal(str(loaded[0]), "text", "the modality is reported")
	PollinationsTest.equal(node.models.size(), 2, "the entries are kept")
	PollinationsTest.equal(node.ids().size(), 4, "ids and aliases are exposed")
	PollinationsTest.check(node.has("nova-fast"), "an alias resolves")
	PollinationsTest.check(not node.has("gpt-5.4-nano"), "an unknown model does not")
	PollinationsTest.equal(str(node.entry("nova-fast").get("name", "")), "amazon/nova-micro-v1", "the entry is found by alias")
	PollinationsTest.equal(node.entry("nope").size(), 0, "an unknown model has no entry")
	PollinationsTest.equal(node.supporting("/text/{prompt}").size(), 1, "endpoints filter the catalogue")
	PollinationsTest.equal(problems.size(), 0, "no failure was reported")
	node.free()

	# a catalogue that cannot be read is a parse failure
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, '{"error":"nope"}')]
	node = PollinationsCatalog.new()
	node.client = PollinationsClient.new()
	node.client.transport = transport.callable()
	node.add_child(node.client)
	problems = []
	node.failed.connect(func(_kind: int, message: String) -> void: problems.append(message))
	result = await node.fetch("image")
	PollinationsTest.check(not bool(result.get("ok", true)), "an unreadable catalogue fails")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.PARSE, "an unreadable catalogue is a parse failure")
	PollinationsTest.equal(problems.size(), 1, "the failure signal fires")
	node.free()
