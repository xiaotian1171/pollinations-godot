extends Control

## The example scene. Everything is built in code so the whole add-on can be
## read here in one file, and so the scene also runs headless in CI.
##
## Try it: open the project in Godot and press F5, then either paste a key or
## use "Sign in with Pollinations" (device flow, pays with the player's own
## pollen).

const TEXT_SYSTEM_PROMPT := "You are the miller of a small village. Answer in one short sentence."

var client: PollinationsClient
var text: PollinationsText
var image: PollinationsImage
var speech: PollinationsSpeech
var catalog: PollinationsCatalog
var auth: PollinationsAuth

var status_label: Label
var key_field: LineEdit
var text_prompt: LineEdit
var text_output: TextEdit
var text_model: OptionButton
var image_prompt: LineEdit
var image_view: TextureRect
var image_model: OptionButton
var speech_prompt: LineEdit
var speech_model: OptionButton
var player: AudioStreamPlayer
var auth_button: Button
var auth_hint: Label

func _ready() -> void:
	_build_nodes()
	_build_ui()
	_set_status("Ready. Anonymous requests work; sign in to use your own pollen.")
	_load_catalog()

func _build_nodes() -> void:
	client = PollinationsClient.new()
	client.name = "Client"
	client.debug = true
	add_child(client)

	text = PollinationsText.new()
	text.name = "Text"
	text.system_prompt = TEXT_SYSTEM_PROMPT
	add_child(text)

	image = PollinationsImage.new()
	image.name = "Image"
	add_child(image)

	speech = PollinationsSpeech.new()
	speech.name = "Speech"
	add_child(speech)

	catalog = PollinationsCatalog.new()
	catalog.name = "Catalog"
	add_child(catalog)

	auth = PollinationsAuth.new()
	auth.name = "Auth"
	add_child(auth)

	# Every node shares one client, so retries and the debug log are central.
	for node: PollinationsNode in [text, image, speech, catalog, auth]:
		node.client_path = node.get_path_to(client)

	auth.code_ready.connect(_on_auth_code)
	auth.signed_in.connect(_on_signed_in)
	auth.failed.connect(_on_auth_failed)

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)

	var title := Label.new()
	title.text = "Pollinations for Godot"
	title.add_theme_font_size_override("font_size", 24)
	rows.add_child(title)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(status_label)

	rows.add_child(HSeparator.new())
	rows.add_child(_section_label("Account (bring your own pollen)"))
	var account_row := HBoxContainer.new()
	rows.add_child(account_row)
	key_field = LineEdit.new()
	key_field.secret = true
	key_field.placeholder_text = "sk_... (leave empty for anonymous requests)"
	key_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_row.add_child(key_field)
	var use_key := Button.new()
	use_key.text = "Use this key"
	use_key.pressed.connect(_on_use_key)
	account_row.add_child(use_key)
	auth_button = Button.new()
	auth_button.text = "Sign in with Pollinations"
	auth_button.pressed.connect(_on_sign_in)
	account_row.add_child(auth_button)
	auth_hint = Label.new()
	auth_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(auth_hint)

	rows.add_child(HSeparator.new())
	rows.add_child(_section_label("Text"))
	var text_row := HBoxContainer.new()
	rows.add_child(text_row)
	text_prompt = LineEdit.new()
	text_prompt.text = "Describe the village mill in one sentence."
	text_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_row.add_child(text_prompt)
	text_model = OptionButton.new()
	text_model.custom_minimum_size = Vector2(220, 0)
	text_row.add_child(text_model)
	var ask := Button.new()
	ask.text = "Generate"
	ask.pressed.connect(_on_generate_text)
	text_row.add_child(ask)
	text_output = TextEdit.new()
	text_output.custom_minimum_size = Vector2(0, 80)
	text_output.editable = false
	rows.add_child(text_output)

	rows.add_child(HSeparator.new())
	rows.add_child(_section_label("Image"))
	var image_row := HBoxContainer.new()
	rows.add_child(image_row)
	image_prompt = LineEdit.new()
	image_prompt.text = "a wooden watermill at dusk, painting"
	image_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_row.add_child(image_prompt)
	image_model = OptionButton.new()
	image_model.custom_minimum_size = Vector2(220, 0)
	image_row.add_child(image_model)
	var draw := Button.new()
	draw.text = "Generate"
	draw.pressed.connect(_on_generate_image)
	image_row.add_child(draw)
	image_view = TextureRect.new()
	image_view.custom_minimum_size = Vector2(320, 320)
	image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rows.add_child(image_view)

	rows.add_child(HSeparator.new())
	rows.add_child(_section_label("Speech"))
	var speech_row := HBoxContainer.new()
	rows.add_child(speech_row)
	speech_prompt = LineEdit.new()
	speech_prompt.text = "Welcome to Pollen Village, traveller."
	speech_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speech_row.add_child(speech_prompt)
	speech_model = OptionButton.new()
	speech_model.custom_minimum_size = Vector2(220, 0)
	speech_row.add_child(speech_model)
	var say := Button.new()
	say.text = "Speak"
	say.pressed.connect(_on_generate_speech)
	speech_row.add_child(say)
	player = AudioStreamPlayer.new()
	rows.add_child(player)

func _section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 18)
	return label

func _set_status(message: String) -> void:
	status_label.text = message
	print("[demo] %s" % message)

## Reads the live catalogues so the model pickers list what exists right now.
func _load_catalog() -> void:
	var kinds := [
		{"modality": "text", "picker": text_model, "default": PollinationsConfig.DEFAULT_TEXT_MODEL, "endpoint": "/v1/chat/completions"},
		{"modality": "image", "picker": image_model, "default": PollinationsConfig.DEFAULT_IMAGE_MODEL, "endpoint": "/image/{prompt}"},
		{"modality": "audio", "picker": speech_model, "default": PollinationsConfig.DEFAULT_SPEECH_MODEL, "endpoint": "/v1/audio/speech"},
	]
	for kind: Dictionary in kinds:
		var picker: OptionButton = kind["picker"]
		picker.clear()
		picker.add_item(str(kind["default"]))
		picker.set_item_metadata(0, str(kind["default"]))
		var result := await catalog.fetch(str(kind["modality"]))
		if not result.get("ok", false):
			# The audio catalogue is the least stable one; the pickers stay
			# usable with the default model either way.
			picker.add_item("(catalogue unavailable)")
			picker.set_item_metadata(1, str(kind["default"]))
			continue
		var entries := catalog.supporting(str(kind["endpoint"]))
		print("[demo] %s catalogue: %d models (%d usable here)" % [str(kind["modality"]), catalog.models.size(), entries.size()])
		if entries.size() == 0:
			# The audio catalogue sometimes only lists transcription models, so
			# the default stays selectable instead of leaving an empty picker.
			picker.add_item("(no usable model in the catalogue)")
			picker.set_item_metadata(1, str(kind["default"]))
			continue
		var index := 0
		for entry: Dictionary in entries:
			index += 1
			var id := PollinationsModels.id_of(entry)
			if id.is_empty():
				continue
			picker.add_item("%s  -  %s" % [PollinationsModels.label_of(entry), id])
			picker.set_item_metadata(index, id)

func _selected(picker: OptionButton) -> String:
	var index := picker.get_selected_id()
	var metadata: Variant = picker.get_item_metadata(index)
	return str(metadata) if metadata != null else ""

func _on_use_key() -> void:
	var key := key_field.text.strip_edges()
	if key.is_empty():
		PollinationsConfig.set_api_key("")
		_set_status("Cleared the key; requests are anonymous again.")
		return
	PollinationsConfig.set_api_key(key)
	_set_status("Using the pasted key for the next requests (not stored on disk).")

func _on_sign_in() -> void:
	auth_button.disabled = true
	_set_status("Asking Pollinations for a device code...")
	auth_hint.text = ""
	var result := await auth.sign_in()
	auth_button.disabled = false
	if not result.get("ok", false):
		_set_status(str(result.get("error", "Sign-in failed.")))

func _on_auth_code(user_code: String, url: String, expires: int) -> void:
	auth_hint.text = "Open %s and enter %s (valid for %d minutes)." % [url, user_code, expires / 60]
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(user_code)
	_set_status("Waiting for the sign-in to be approved.")

func _on_signed_in(user: Dictionary) -> void:
	var name := str(user.get("preferred_username", ""))
	_set_status("Signed in%s. This player now pays with their own pollen." % ("" if name.is_empty() else " as %s" % name))
	auth_hint.text = ""

func _on_auth_failed(kind: PollinationsErrors.Kind, message: String) -> void:
	_set_status(message)
	if kind == PollinationsErrors.Kind.BAD_REQUEST:
		auth_hint.text = "The device flow needs a pk_ app key: Project Settings > pollinations/app_key."

func _on_generate_text() -> void:
	text.model = _selected(text_model)
	_set_status("Generating text with %s..." % text.model)
	var result := await text.generate(text_prompt.text)
	if result.get("ok", false):
		text_output.text = str(result.get("content", ""))
		_set_status(
			"Text ready in %d attempt(s) with %s." % [int(result.get("attempts", 1)), str(result.get("model", text.model))]
		)
		return
	_set_status(str(result.get("error", "Text generation failed.")))

func _on_generate_image() -> void:
	image.model = _selected(image_model)
	_set_status("Generating an image with %s..." % image.model)
	var result := await image.generate(image_prompt.text)
	if result.get("ok", false):
		image_view.texture = result.get("texture")
		_set_status("Image ready (%s, %s)." % [str(result.get("mime", "")), str(result.get("size", Vector2i.ZERO))])
		return
	_set_status(str(result.get("error", "Image generation failed.")))

func _on_generate_speech() -> void:
	speech.model = _selected(speech_model)
	_set_status("Generating speech with %s..." % speech.model)
	var result := await speech.generate(speech_prompt.text)
	if result.get("ok", false):
		player.stream = result.get("stream")
		_set_status("Speech ready (%.1f seconds)." % float(result.get("length", 0.0)))
		player.play()
		return
	_set_status(str(result.get("error", "Speech generation failed.")))
