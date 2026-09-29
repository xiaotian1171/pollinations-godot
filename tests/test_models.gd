class_name TestModels
extends RefCounted

const SAMPLE := """[
	{
		"name": "amazon/nova-micro-v1",
		"aliases": ["nova-micro", "nova-fast"],
		"category": "text",
		"title": "Nova Micro",
		"supported_endpoints": ["/v1/chat/completions", "/text", "/text/{prompt}"],
		"pricing": {"currency": "pollen", "promptTextTokens": "0.000000035", "completionTextTokens": "0.00000014"}
	},
	{
		"name": "openai/gpt-6-luna",
		"aliases": ["gpt-6-luna"],
		"category": "text",
		"title": "GPT-6 Luna",
		"supported_endpoints": ["/v1/chat/completions"],
		"pricing": {"currency": "pollen", "promptTextTokens": "0.0000001"}
	}
]"""

static func run() -> void:
	PollinationsTest.suite("models")

	var entries := PollinationsModels.parse(SAMPLE)
	PollinationsTest.equal(entries.size(), 2, "two entries are read")
	PollinationsTest.equal(PollinationsModels.id_of(entries[0]), "amazon/nova-micro-v1", "id comes from name")
	PollinationsTest.equal(PollinationsModels.label_of(entries[0]), "Nova Micro", "label comes from title")

	var known := PollinationsModels.ids(entries)
	PollinationsTest.check(known.has("amazon/nova-micro-v1"), "canonical ids are listed")
	PollinationsTest.check(known.has("nova-fast"), "aliases are listed")
	PollinationsTest.check(known.has("gpt-6-luna"), "every entry contributes")

	PollinationsTest.check(PollinationsModels.has_model(entries, "nova-fast"), "aliases resolve to a model")
	PollinationsTest.check(PollinationsModels.has_model(entries, "openai/gpt-6-luna"), "ids resolve")
	PollinationsTest.check(not PollinationsModels.has_model(entries, "gpt-5.4-nano"), "unknown models do not resolve")
	PollinationsTest.check(not PollinationsModels.has_model(entries, ""), "an empty model is not a model")

	var chat_only := PollinationsModels.supporting(entries, "/v1/chat/completions")
	PollinationsTest.equal(chat_only.size(), 2, "both entries accept chat completions")
	var prompt_only := PollinationsModels.supporting(entries, "/text/{prompt}")
	PollinationsTest.equal(prompt_only.size(), 1, "only nova accepts the prompt route")

	PollinationsTest.contains(
		PollinationsModels.price_hint(entries[0]),
		"completionTextTokens",
		"the price hint is readable"
	)
	PollinationsTest.equal(PollinationsModels.price_hint({"name": "x"}), "", "no pricing means no hint")

	# OpenAI-style envelope
	var wrapped := PollinationsModels.parse('{"data":[{"id":"speech-1","title":"Speech 1"}]}')
	PollinationsTest.equal(wrapped.size(), 1, "an OpenAI-style envelope is read")
	PollinationsTest.equal(PollinationsModels.id_of(wrapped[0]), "speech-1", "id falls back to the id field")

	# garbage in, empty out
	PollinationsTest.equal(PollinationsModels.parse("not json").size(), 0, "broken JSON gives no models")
	PollinationsTest.equal(PollinationsModels.parse("[]").size(), 0, "an empty catalogue gives no models")
	PollinationsTest.equal(PollinationsModels.parse('{"error":"nope"}').size(), 0, "an error body gives no models")
