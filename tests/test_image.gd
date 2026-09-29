class_name TestImage
extends RefCounted

static func _node(transport: FakeTransport) -> PollinationsImage:
	var node := PollinationsImage.new()
	node.client = PollinationsClient.new()
	node.client.transport = transport.callable()
	node.add_child(node.client)
	return node

static func run() -> void:
	PollinationsTest.suite("image node")

	# format sniffing
	PollinationsTest.equal(
		PollinationsImage.mime_of(PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0])),
		"image/jpeg",
		"JPEG is recognised"
	)
	var png := _png_bytes()
	PollinationsTest.equal(PollinationsImage.mime_of(png), "image/png", "PNG is recognised")
	PollinationsTest.equal(
		PollinationsImage.mime_of("RIFF____WEBPVP8 ".to_utf8_buffer()),
		"image/webp",
		"WebP is recognised"
	)
	PollinationsTest.equal(PollinationsImage.mime_of("GIF89a".to_utf8_buffer()), "image/gif", "GIF is recognised")
	PollinationsTest.equal(
		PollinationsImage.mime_of('<svg xmlns="http://www.w3.org/2000/svg"></svg>'.to_utf8_buffer()),
		"image/svg+xml",
		"SVG is recognised"
	)
	PollinationsTest.equal(PollinationsImage.mime_of("hello".to_utf8_buffer()), "application/octet-stream", "garbage is not an image")
	PollinationsTest.equal(PollinationsImage.mime_of(PackedByteArray()), "application/octet-stream", "nothing is not an image")

	# decoding
	var decoded := PollinationsImage.decode(png)
	PollinationsTest.truthy(decoded, "PNG bytes decode")
	if decoded != null:
		PollinationsTest.equal(decoded.get_width(), 4, "the decoded image keeps its size")
	PollinationsTest.equal(decoded.get_height(), 4, "the decoded image keeps its height")
	PollinationsTest.equal(PollinationsImage.decode(PackedByteArray()), null, "empty bytes do not decode")
	PollinationsTest.equal(PollinationsImage.decode("nope".to_utf8_buffer()), null, "text does not decode")

	# a live-shaped round trip
	var transport := FakeTransport.new()
	var response := FakeTransport.response(200, "")
	response["bytes"] = png
	transport.responses = [response]
	var node := _node(transport)
	var result: Dictionary = await node.generate("a small red square")
	PollinationsTest.check(bool(result.get("ok", false)), "an image response is a success")
	PollinationsTest.equal(str(result.get("mime", "")), "image/png", "the mime type is reported")
	PollinationsTest.truthy(result.get("image"), "an Image is produced")
	PollinationsTest.truthy(result.get("texture"), "a texture is produced")
	PollinationsTest.equal(str(transport.requests[0].get("url", "")), "https://gen.pollinations.ai/image/a%20small%20red%20square?model=tongyi-mai%2Fz-image-turbo", "the image route is built")
	node.free()

	# a 200 that is not an image is a parse failure
	transport = FakeTransport.new()
	transport.responses = [FakeTransport.response(200, '{"error":"model unavailable"}')]
	node = _node(transport)
	result = await node.generate("nope")
	PollinationsTest.check(not bool(result.get("ok", true)), "an unreadable image is a failure")
	PollinationsTest.equal(int(result.get("kind", -1)), PollinationsErrors.Kind.PARSE, "an unreadable image is a parse failure")
	node.free()

	# the exported knobs reach the URL
	transport = FakeTransport.new()
	response = FakeTransport.response(200, "")
	response["bytes"] = png
	transport.responses = [response]
	node = _node(transport)
	node.model = ""
	node.width = 256
	node.height = 256
	node.seed = 7
	node.safe = "true"
	node.transparent = true
	result = await node.generate("x")
	var url := str(transport.requests[0].get("url", ""))
	PollinationsTest.contains(url, "width=256", "the width is sent")
	PollinationsTest.contains(url, "height=256", "the height is sent")
	PollinationsTest.contains(url, "seed=7", "the seed is sent")
	PollinationsTest.contains(url, "safe=true", "the safety flag is sent")
	PollinationsTest.contains(url, "transparent=true", "the transparency flag is sent")
	node.free()

static func _png_bytes() -> PackedByteArray:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 0, 1))
	return image.save_png_to_buffer()
