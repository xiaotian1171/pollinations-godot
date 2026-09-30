class_name TestConfig
extends RefCounted

static func run() -> void:
	PollinationsTest.suite("config")

	# the session key wins over everything else
	PollinationsConfig.set_api_key("sk_session")
	PollinationsTest.equal(PollinationsConfig.api_key(), "sk_session", "a runtime key is used")
	PollinationsTest.check(PollinationsConfig.has_api_key(), "a runtime key counts as configured")

	# and is trimmed
	PollinationsConfig.set_api_key("  sk_padded  ")
	PollinationsTest.equal(PollinationsConfig.api_key(), "sk_padded", "keys are trimmed")

	# project settings are the second source
	PollinationsConfig.clear_api_key(true)
	ProjectSettings.set_setting(PollinationsConfig.PROJECT_SETTING_API_KEY, "sk_project")
	PollinationsTest.equal(PollinationsConfig.api_key(), "sk_project", "the project setting is used")
	PollinationsConfig.set_api_key("sk_session")
	PollinationsTest.equal(PollinationsConfig.api_key(), "sk_session", "the runtime key beats the project setting")
	PollinationsConfig.clear_api_key(true)
	ProjectSettings.set_setting(PollinationsConfig.PROJECT_SETTING_API_KEY, "")

	# with no key anywhere the add-on still works anonymously
	if OS.get_environment(PollinationsConfig.ENV_API_KEY).is_empty():
		PollinationsTest.equal(PollinationsConfig.api_key(), "", "no key means anonymous")
		PollinationsTest.check(not PollinationsConfig.has_api_key(), "no key means not configured")
		PollinationsTest.equal(
			PollinationsConfig.authorization_headers().size(),
			0,
			"no key means no Authorization header"
		)

	# header shape
	var headers := PollinationsConfig.authorization_for("sk_test")
	PollinationsTest.equal(headers.size(), 1, "one header for one key")
	PollinationsTest.equal(headers[0], "Authorization: Bearer sk_test", "the header is a bearer header")
	PollinationsTest.equal(PollinationsConfig.authorization_for("   ").size(), 0, "a blank key makes no header")

	# the app key identifies the game in the device flow
	ProjectSettings.set_setting(PollinationsConfig.PROJECT_SETTING_APP_KEY, "")
	if OS.get_environment(PollinationsConfig.ENV_APP_KEY).is_empty():
		PollinationsTest.equal(PollinationsConfig.app_key(), "", "no app key is assumed")
	ProjectSettings.set_setting(PollinationsConfig.PROJECT_SETTING_APP_KEY, "pk_my_game")
	PollinationsTest.equal(PollinationsConfig.app_key(), "pk_my_game", "the app key can be configured")
	ProjectSettings.set_setting(PollinationsConfig.PROJECT_SETTING_APP_KEY, "")

	# stored device keys round-trip, then go away
	PollinationsTest.check(PollinationsConfig.store_device_key("sk_stored"), "a device key is stored")
	PollinationsTest.equal(PollinationsConfig.load_device_key(), "sk_stored", "a device key is loaded")
	PollinationsConfig.forget_device_key()
	PollinationsTest.equal(PollinationsConfig.load_device_key(), "", "a forgotten device key stays gone")
