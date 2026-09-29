class_name PollinationsImage
extends PollinationsNode

## Image generation. The response body is the image itself, so it is decoded
## into an Image and an ImageTexture ready to put on a Sprite2D or TextureRect.
##
##	var image := PollinationsImage.new()
##	add_child(image)
##	var result := await image.generate("a wooden village at dusk")
##	if result.ok:
##		$Sprite2D.texture = result.texture

signal generated(result: Dictionary)

@export var model: String = PollinationsConfig.DEFAULT_IMAGE_MODEL
## 0 keeps the server default for both.
@export var width: int = 0
@export var height: int = 0
## -1 lets Pollinations pick one.
@export var seed: int = -1
## "", "true" or "false"; empty leaves the choice to the server.
@export var safe: String = ""
## "", "low", "medium", "high" or "hd"; empty leaves the choice to the server.
@export var quality: String = ""
@export var transparent: bool = false

func generate(prompt: String) -> Dictionary:
	var client := ensure_client()
	var url := PollinationsUrls.image_prompt(prompt, model, width, height, seed, safe, quality, transparent)
	var result: Dictionary = await client.get_json(url)
	if result.get("ok", false):
		var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
		var image := decode(bytes)
		if image == null:
			result = PollinationsClient.failure(
				PollinationsErrors.Kind.PARSE,
				int(result.get("status", 0)),
				url,
				"unsupported image payload (%s, %d bytes)" % [mime_of(bytes), bytes.size()]
			)
		else:
			result["image"] = image
			result["texture"] = ImageTexture.create_from_image(image)
			result["mime"] = mime_of(bytes)
			result["size"] = image.get_size()
	generated.emit(result)
	return result

## Decodes image bytes by sniffing their format. Returns null when the payload
## is not an image Godot can read.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image := Image.new()
	var format := mime_of(bytes)
	var error := FAILED
	match format:
		"image/jpeg":
			error = image.load_jpg_from_buffer(bytes)
		"image/png":
			error = image.load_png_from_buffer(bytes)
		"image/webp":
			error = image.load_webp_from_buffer(bytes)
		"image/svg+xml":
			error = image.load_svg_from_buffer(bytes)
		_:
			return null
	return image if error == OK else null

## Sniffs the MIME type from the leading bytes.
static func mime_of(bytes: PackedByteArray) -> String:
	if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		return "image/jpeg"
	if bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return "image/png"
	if bytes.size() >= 12 and bytes.slice(0, 4) == "RIFF".to_utf8_buffer() and bytes.slice(8, 12) == "WEBP".to_utf8_buffer():
		return "image/webp"
	if bytes.size() >= 4 and bytes.slice(0, 4) == "GIF8".to_utf8_buffer():
		return "image/gif"
	var head := bytes.slice(0, min(256, bytes.size())).get_string_from_utf8().strip_edges()
	if head.begins_with("<svg") or head.begins_with("<?xml") or head.begins_with("<!DOCTYPE svg"):
		return "image/svg+xml"
	return "application/octet-stream"
