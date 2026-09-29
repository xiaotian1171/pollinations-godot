class_name PollinationsSpeech
extends PollinationsNode

## Speech, music and sound effects from text. The response is decoded into an
## AudioStream, so it can go straight into an AudioStreamPlayer.
##
##	var speech := PollinationsSpeech.new()
##	add_child(speech)
##	var result := await speech.generate("Welcome to Pollen Village.")
##	if result.ok:
##		$AudioStreamPlayer.stream = result.stream

signal generated(result: Dictionary)

@export var model: String = PollinationsConfig.DEFAULT_SPEECH_MODEL
@export var voice: String = PollinationsConfig.DEFAULT_VOICE
## mp3, wav and ogg can be decoded in memory; the other formats come back as
## raw bytes that need to be written to a file first.
@export_enum("mp3", "wav", "ogg", "opus", "aac", "flac", "pcm") var response_format: String = "mp3"
## Optional delivery notes for models that support them.
@export_multiline var instructions: String = ""

## Formats this node can turn into an AudioStream without touching the disk.
const DECODABLE_FORMATS := ["mp3", "wav", "ogg"]

func generate(text: String) -> Dictionary:
	var client := ensure_client()
	var payload := {
		"model": model,
		"input": text,
		"voice": voice,
		"response_format": response_format,
	}
	if not instructions.strip_edges().is_empty():
		payload["instructions"] = instructions
	var result: Dictionary = await client.post_json(PollinationsUrls.speech(), payload)
	if result.get("ok", false):
		var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
		var stream := build_stream(bytes, response_format)
		if stream == null:
			result = PollinationsClient.failure(
				PollinationsErrors.Kind.PARSE,
				int(result.get("status", 0)),
				str(result.get("url", "")),
				"could not decode %d bytes of %s audio; use mp3, wav or ogg" % [bytes.size(), response_format]
			)
		else:
			result["stream"] = stream
			result["length"] = stream.get_length()
			result["format"] = response_format
	generated.emit(result)
	return result

## Builds an AudioStream from audio bytes. Returns null for formats Godot
## cannot decode from memory.
static func build_stream(bytes: PackedByteArray, format: String) -> AudioStream:
	if bytes.is_empty():
		return null
	match format.to_lower():
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null

## True when `generate` can hand back a playable stream for this format.
static func can_decode(format: String) -> bool:
	return DECODABLE_FORMATS.has(format.to_lower())
