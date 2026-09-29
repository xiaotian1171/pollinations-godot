class_name PollinationsUrls
extends RefCounted

## Every URL the add-on talks to, built in one place so the tests can check
## them without touching the network.

const GEN_BASE := "https://gen.pollinations.ai"
const ENTER_BASE := "https://enter.pollinations.ai"

## OpenAI-compatible chat completions.
static func chat_completions() -> String:
	return GEN_BASE + "/v1/chat/completions"

## Plain text for one prompt, the cheapest way to get a single string.
static func text_prompt(prompt: String, model: String = "", seed: int = -1) -> String:
	var url := GEN_BASE + "/text/" + prompt.uri_encode()
	var query := _query({"model": model, "seed": _seed(seed)})
	return url + query

## Image bytes for one prompt.
static func image_prompt(
	prompt: String,
	model: String = "",
	width: int = 0,
	height: int = 0,
	seed: int = -1,
	safe: String = "",
	quality: String = "",
	transparent: bool = false
) -> String:
	var url := GEN_BASE + "/image/" + prompt.uri_encode()
	var params := {
		"model": model,
		"width": width if width > 0 else "",
		"height": height if height > 0 else "",
		"seed": _seed(seed),
		"safe": safe,
		"quality": quality,
	}
	if transparent:
		params["transparent"] = "true"
	return url + _query(params)

## Speech, music or sound effects from text (OpenAI-compatible TTS body).
static func speech() -> String:
	return GEN_BASE + "/v1/audio/speech"

## Speech through the simple GET route.
static func audio_prompt(text: String, model: String = "", voice: String = "") -> String:
	var url := GEN_BASE + "/audio/" + text.uri_encode()
	return url + _query({"model": model, "voice": voice})

## Model catalogue for one modality: "text", "image", "audio", "embeddings".
static func models(kind: String) -> String:
	return "%s/%s/models" % [GEN_BASE, kind]

static func device_code() -> String:
	return ENTER_BASE + "/api/device/code"

static func device_token() -> String:
	return ENTER_BASE + "/api/device/token"

static func device_userinfo() -> String:
	return ENTER_BASE + "/api/device/userinfo"

## Page a player opens to approve a device code.
static func device_verification_page() -> String:
	return ENTER_BASE + "/device"

static func _seed(seed: int) -> String:
	return "" if seed < 0 else str(seed)

static func _query(params: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in params:
		var value: Variant = params[key]
		if value is String and (value as String).is_empty():
			continue
		parts.append("%s=%s" % [key.uri_encode(), str(value).uri_encode()])
	if parts.is_empty():
		return ""
	return "?" + "&".join(parts)
