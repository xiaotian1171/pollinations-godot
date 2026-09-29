@tool
extends EditorPlugin

## Editor entry point. The add-on is usable from any script without the editor
## plugin, so this only reports that it loaded and registers the project
## settings the nodes read.

const SETTINGS := {
	"pollinations/api_key": {
		"value": "",
		"hint": "Server-side API key (sk_...). Leave empty to let each player sign in with their own Pollen instead.",
	},
	"pollinations/app_key": {
		"value": "",
		"hint": "Public app key (pk_...) used to attribute the device sign-in flow to your game.",
	},
}

func _enter_tree() -> void:
	for name: String in SETTINGS:
		var setting: Dictionary = SETTINGS[name]
		if not ProjectSettings.has_setting(name):
			ProjectSettings.set_setting(name, setting["value"])
		ProjectSettings.add_property_info({
			"name": name,
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_PLACEHOLDER_TEXT,
			"hint_string": setting["hint"],
		})
	print("[pollinations] add-on loaded; see the demo scene for a working example.")
	# Only the project settings are written to disk, so nothing else to save here.

func _exit_tree() -> void:
	pass
