class_name PollinationsCatalog
extends PollinationsNode

## The live model catalogue. Pollinations adds models all the time, so a game
## can offer whatever exists right now instead of a hardcoded list.
##
##	var catalog := PollinationsCatalog.new()
##	add_child(catalog)
##	var result := await catalog.fetch("text")
##	if result.ok:
##		picker.add_item(...) for each id in catalog.ids()

## Emitted after a successful fetch.
signal loaded(modality: String, models: Array)
## Emitted when the catalogue could not be read.
signal failed(kind: PollinationsErrors.Kind, message: String)

@export_enum("text", "image", "audio", "embeddings") var modality: String = "text"

## The entries of the last successful fetch.
var models: Array = []

## Reads one catalogue; `modality_override` wins over the exported property.
func fetch(modality_override: String = "") -> Dictionary:
	var kind := modality_override if not modality_override.is_empty() else modality
	var client := ensure_client()
	var result: Dictionary = await client.get_json(PollinationsUrls.models(kind))
	if result.get("ok", false):
		var entries := PollinationsModels.parse(str(result.get("text", "")))
		if entries.is_empty():
			var failure := PollinationsClient.failure(
				PollinationsErrors.Kind.PARSE,
				int(result.get("status", 0)),
				str(result.get("url", "")),
				"the %s catalogue came back empty or unreadable" % kind
			)
			failed.emit(failure["kind"], failure["error"])
			return failure
		models = entries
		result["models"] = entries
		result["ids"] = PollinationsModels.ids(entries)
		loaded.emit(kind, entries)
		return result
	failed.emit(result.get("kind", PollinationsErrors.Kind.UNKNOWN), str(result.get("error", "")))
	return result

## Every id and alias in the last fetch.
func ids() -> PackedStringArray:
	return PollinationsModels.ids(models)

## Entries that accept one endpoint, e.g. "/v1/chat/completions".
func supporting(endpoint: String) -> Array:
	return PollinationsModels.supporting(models, endpoint)

## True when an id or alias exists in the last fetch.
func has(model_id: String) -> bool:
	return PollinationsModels.has_model(models, model_id)

## The entry for one id or alias, or {} when it is unknown.
func entry(model_id: String) -> Dictionary:
	for candidate: Dictionary in models:
		if PollinationsModels.id_of(candidate) == model_id:
			return candidate
		for alias: Variant in candidate.get("aliases", []):
			if str(alias) == model_id:
				return candidate
	return {}
