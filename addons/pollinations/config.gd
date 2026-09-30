class_name PollinationsConfig
extends RefCounted

## Where the add-on finds its credentials, in priority order:
##   1. a key set at runtime (`set_api_key`) — e.g. a player's device-flow key
##   2. the `pollinations/api_key` project setting (a server-side key)
##   3. the POLLINATIONS_API_KEY environment variable
##   4. a key previously stored on this device by PollinationsAuth
##
## The app key used by the device flow comes from `pollinations/app_key` or the
## POLLINATIONS_APP_KEY environment variable.
##
## Never ship a server-side key inside a released game: anyone can read it out
## of the binary. Use the device flow (BYOP) so each player pays with their own
## Pollen, and keep a server-side key for your own builds.

const PROJECT_SETTING_API_KEY := "pollinations/api_key"
const PROJECT_SETTING_APP_KEY := "pollinations/app_key"
const ENV_API_KEY := "POLLINATIONS_API_KEY"
const ENV_APP_KEY := "POLLINATIONS_APP_KEY"
const STORED_KEY_FILE := "user://pollinations_device_key.cfg"
const STORED_KEY_SECTION := "pollinations"
const STORED_KEY_FIELD := "device_key"
const DEFAULT_APP_KEY := "pk_godot"

static var _session_key: String = ""

## Defaults for the model pickers; every one of them can be overridden.
const DEFAULT_TEXT_MODEL := "nova-fast"
const DEFAULT_IMAGE_MODEL := "tongyi-mai/z-image-turbo"
## Speech models that the live audio catalogue serves (and that bill against
## free pollen, unlike the paid-only ones such as `elevenlabs/eleven-v3`).
const DEFAULT_SPEECH_MODEL := "openai/tts-1"
const DEFAULT_VOICE := "alloy"

## Use this key for every request until `clear_api_key`. `remember` also writes
## it to the device so the player stays signed in after a restart.
static func set_api_key(key: String, remember: bool = false) -> void:
	_session_key = key.strip_edges()
	if remember and not _session_key.is_empty():
		store_device_key(_session_key)

## Drop the in-memory key, and the stored one unless `keep_stored` is set.
static func clear_api_key(keep_stored: bool = false) -> void:
	_session_key = ""
	if not keep_stored:
		forget_device_key()

static func api_key() -> String:
	if not _session_key.is_empty():
		return _session_key
	var from_project := str(ProjectSettings.get_setting(PROJECT_SETTING_API_KEY, "")).strip_edges()
	if not from_project.is_empty():
		return from_project
	var from_env := OS.get_environment(ENV_API_KEY).strip_edges()
	if not from_env.is_empty():
		return from_env
	return load_device_key()

static func has_api_key() -> bool:
	return not api_key().is_empty()

## Ready-made header list for an authenticated request. Empty when no key is
## configured, which is fine: Pollinations also serves anonymous requests.
static func authorization_headers() -> PackedStringArray:
	return authorization_for(api_key())

static func authorization_for(key: String) -> PackedStringArray:
	if key.strip_edges().is_empty():
		return PackedStringArray()
	return PackedStringArray(["Authorization: Bearer %s" % key.strip_edges()])

## Public app key (`pk_...`) that identifies this game in the device flow.
static func app_key() -> String:
	var from_project := str(ProjectSettings.get_setting(PROJECT_SETTING_APP_KEY, "")).strip_edges()
	if not from_project.is_empty():
		return from_project
	var from_env := OS.get_environment(ENV_APP_KEY).strip_edges()
	if not from_env.is_empty():
		return from_env
	return DEFAULT_APP_KEY

static func store_device_key(key: String) -> bool:
	var config := ConfigFile.new()
	config.set_value(STORED_KEY_SECTION, STORED_KEY_FIELD, key)
	return config.save(STORED_KEY_FILE) == OK

static func load_device_key() -> String:
	var config := ConfigFile.new()
	if config.load(STORED_KEY_FILE) != OK:
		return ""
	return str(config.get_value(STORED_KEY_SECTION, STORED_KEY_FIELD, "")).strip_edges()

static func forget_device_key() -> void:
	if FileAccess.file_exists(STORED_KEY_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STORED_KEY_FILE))
