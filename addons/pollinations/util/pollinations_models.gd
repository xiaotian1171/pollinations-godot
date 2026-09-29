class_name PollinationsModels
extends RefCounted

## Reads the live model catalogues (/text/models, /image/models, /audio/models).
## Their payload is a JSON array of entries; OpenAI-style `{"data": [...]}`
## envelopes are accepted too.

## Parses a catalogue payload into an array of Dictionaries. Returns an empty
## array when the payload is not a catalogue.
static func parse(json_text: String) -> Array:
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return []
	var parsed: Variant = json.data
	if parsed == null:
		return []
	var entries: Variant = parsed
	if parsed is Dictionary:
		var dict: Dictionary = parsed
		entries = null
		for key: String in ["data", "models", "categories"]:
			if dict.has(key) and dict[key] is Array:
				entries = dict[key]
				break
		if entries == null:
			return []
	if not entries is Array:
		return []
	var out: Array = []
	for entry: Variant in entries:
		if entry is Dictionary:
			out.append(entry)
	return out

## The canonical id of an entry (`name` in the Pollinations catalogues).
static func id_of(entry: Dictionary) -> String:
	return str(entry.get("name", entry.get("id", "")))

## Every id and alias a game can pass as a model.
static func ids(entries: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in entries:
		var name := id_of(entry)
		if not name.is_empty():
			out.append(name)
	for entry: Dictionary in entries:
		for alias: Variant in entry.get("aliases", []):
			out.append(str(alias))
	return out

## Human-readable label for a model picker.
static func label_of(entry: Dictionary) -> String:
	var title := str(entry.get("title", ""))
	if title.is_empty():
		return id_of(entry)
	return title

## Entries that accept one endpoint, e.g. "/v1/chat/completions".
static func supporting(entries: Array, endpoint: String) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		var endpoints: Array = entry.get("supported_endpoints", [])
		if endpoints.is_empty() or endpoints.has(endpoint):
			out.append(entry)
	return out

## True when an id (or one of its aliases) is in the catalogue.
static func has_model(entries: Array, model: String) -> bool:
	if model.is_empty():
		return false
	for entry: Dictionary in entries:
		if id_of(entry) == model:
			return true
		for alias: Variant in entry.get("aliases", []):
			if str(alias) == model:
				return true
	return false

## Formats the price of one entry as a short string, or "" when it is free of
## per-token pricing.
static func price_hint(entry: Dictionary) -> String:
	var pricing: Variant = entry.get("pricing")
	if not pricing is Dictionary:
		return ""
	var parts := PackedStringArray()
	for key: String in ["promptTextTokens", "completionTextTokens"]:
		var dict: Dictionary = pricing
		if dict.has(key):
			parts.append("%s %s" % [key, str(dict[key])])
	return ", ".join(parts)
