class_name TestUrls
extends RefCounted

static func run() -> void:
	PollinationsTest.suite("urls")

	PollinationsTest.equal(
		PollinationsUrls.chat_completions(),
		"https://gen.pollinations.ai/v1/chat/completions",
		"chat completions endpoint"
	)
	PollinationsTest.equal(
		PollinationsUrls.speech(),
		"https://gen.pollinations.ai/v1/audio/speech",
		"speech endpoint"
	)
	PollinationsTest.equal(
		PollinationsUrls.models("image"),
		"https://gen.pollinations.ai/image/models",
		"catalogue endpoint"
	)
	PollinationsTest.equal(
		PollinationsUrls.device_code(),
		"https://enter.pollinations.ai/api/device/code",
		"device code endpoint"
	)
	PollinationsTest.equal(
		PollinationsUrls.device_token(),
		"https://enter.pollinations.ai/api/device/token",
		"device token endpoint"
	)
	PollinationsTest.equal(
		PollinationsUrls.device_userinfo(),
		"https://enter.pollinations.ai/api/device/userinfo",
		"device userinfo endpoint"
	)

	# no parameters at all
	PollinationsTest.equal(
		PollinationsUrls.text_prompt("hello world"),
		"https://gen.pollinations.ai/text/hello%20world",
		"prompt only"
	)
	# model and seed
	PollinationsTest.equal(
		PollinationsUrls.text_prompt("hi", "nova-fast", 7),
		"https://gen.pollinations.ai/text/hi?model=nova-fast&seed=7",
		"prompt with model and seed"
	)
	# a negative seed means "let Pollinations pick"
	PollinationsTest.equal(
		PollinationsUrls.text_prompt("hi", "nova-fast"),
		"https://gen.pollinations.ai/text/hi?model=nova-fast",
		"a negative seed is dropped"
	)
	# slashes inside a prompt must not break the path
	PollinationsTest.contains(
		PollinationsUrls.text_prompt("a/b"),
		"%2F",
		"slashes are encoded"
	)

	PollinationsTest.equal(
		PollinationsUrls.image_prompt("a cat", "flux", 512, 512, 3),
		"https://gen.pollinations.ai/image/a%20cat?model=flux&width=512&height=512&seed=3",
		"image with size and seed"
	)
	PollinationsTest.equal(
		PollinationsUrls.image_prompt("a cat", "", 0, 0, -1, "true", "", true),
		"https://gen.pollinations.ai/image/a%20cat?safe=true&transparent=true",
		"image without a model keeps only the flags"
	)
