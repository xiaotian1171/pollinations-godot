class_name PollinationsText
extends PollinationsNode

## Text generation through the OpenAI-compatible chat route.
##
##	var text := PollinationsText.new()
##	add_child(text)
##	var result := await text.generate("Describe a village in one sentence.")
##	if result.ok:
##		print(result.content)

## Emitted for every finished request, successful or not.
signal generated(result: Dictionary)

@export var model: String = PollinationsConfig.DEFAULT_TEXT_MODEL
## Prepended as a system message when not empty.
@export var system_prompt: String = ""
## 0 leaves the choice to the server.
@export_range(0.0, 2.0, 0.05) var temperature: float = 0.8
## 0 leaves the choice to the server.
@export var max_tokens: int = 0

## One prompt in, one answer out.
func generate(prompt: String) -> Dictionary:
	return await chat(build_messages(prompt))

## Sends a full conversation. Each message is {"role": ..., "content": ...}.
func chat(messages: Array) -> Dictionary:
	var client := ensure_client()
	var payload := {"model": model, "messages": messages}
	if temperature > 0.0:
		payload["temperature"] = temperature
	if max_tokens > 0:
		payload["max_tokens"] = max_tokens
	var result: Dictionary = await client.post_json(PollinationsUrls.chat_completions(), payload)
	if result.get("ok", false):
		var content := extract_text(result.get("json"))
		if content.is_empty():
			result = PollinationsClient.failure(
				PollinationsErrors.Kind.PARSE,
				int(result.get("status", 0)),
				str(result.get("url", "")),
				"the model returned no text: %s" % str(result.get("text", "")).left(160)
			)
		else:
			result["content"] = content
			result["model"] = extract_model(result.get("json"))
			result["usage"] = extract_usage(result.get("json"))
	generated.emit(result)
	return result

## The cheap single-prompt route (`GET /text/{prompt}`): one line, no history.
func quick(prompt: String, seed: int = -1) -> Dictionary:
	var client := ensure_client()
	var result: Dictionary = await client.get_json(PollinationsUrls.text_prompt(prompt, model, seed))
	if result.get("ok", false):
		var content := extract_text(result.get("json"))
		if content.is_empty():
			content = str(result.get("text", "")).strip_edges()
		if content.is_empty():
			result = PollinationsClient.failure(
				PollinationsErrors.Kind.PARSE,
				int(result.get("status", 0)),
				str(result.get("url", "")),
				"the prompt route returned nothing"
			)
		else:
			result["content"] = content
	generated.emit(result)
	return result

## The conversation sent for one prompt, including the system message.
func build_messages(prompt: String) -> Array:
	var messages: Array = []
	if not system_prompt.strip_edges().is_empty():
		messages.append({"role": "system", "content": system_prompt})
	messages.append({"role": "user", "content": prompt})
	return messages

## Pulls the assistant text out of a chat response. Accepts the OpenAI shape,
## a bare string, and the flatter shapes some routes use.
static func extract_text(payload: Variant) -> String:
	if payload is String:
		return (payload as String).strip_edges()
	if payload is Array:
		var parts := PackedStringArray()
		for item: Variant in payload:
			var piece := extract_text(item)
			if not piece.is_empty():
				parts.append(piece)
		return "\n".join(parts).strip_edges()
	if not payload is Dictionary:
		return ""
	var dict: Dictionary = payload
	if dict.has("choices") and dict["choices"] is Array:
		var choices: Array = dict["choices"]
		if not choices.is_empty() and choices[0] is Dictionary:
			var choice: Dictionary = choices[0]
			if choice.has("message") and choice["message"] is Dictionary:
				return _content_to_text((choice["message"] as Dictionary).get("content"))
			if choice.has("text"):
				return _content_to_text(choice["text"])
	for key: String in ["content", "text", "response", "output_text", "message", "result"]:
		if dict.has(key):
			var value := _content_to_text(dict[key])
			if not value.is_empty():
				return value
	return ""

## Token usage when the response reports it, else an empty Dictionary.
static func extract_usage(payload: Variant) -> Dictionary:
	if payload is Dictionary:
		var usage: Variant = (payload as Dictionary).get("usage")
		if usage is Dictionary:
			return usage
	return {}

## Model name echoed by the server, else an empty string.
static func extract_model(payload: Variant) -> String:
	if payload is Dictionary:
		var dict: Dictionary = payload
		for key: String in ["model", "model_name"]:
			if dict.has(key) and dict[key] is String:
				return str(dict[key])
	return ""

## Message content can be a string or a list of typed parts.
static func _content_to_text(content: Variant) -> String:
	if content is String:
		return (content as String).strip_edges()
	if content is Array:
		var parts := PackedStringArray()
		for part: Variant in content:
			if part is Dictionary:
				var dict: Dictionary = part
				if dict.has("text"):
					parts.append(str(dict["text"]))
				elif dict.has("content"):
					parts.append(str(dict["content"]))
			elif part is String:
				parts.append(str(part))
		return "".join(parts).strip_edges()
	if content is Dictionary:
		var dict: Dictionary = content
		if dict.has("text"):
			return str(dict["text"]).strip_edges()
		if dict.has("content"):
			return str(dict["content"]).strip_edges()
	return ""
