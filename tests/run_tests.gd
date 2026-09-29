extends SceneTree

## Headless test entry point:
##   godot --headless --path . --script tests/run_tests.gd
## Pure logic and scripted HTTP only: no network, no display, no keys needed.
## The live API check is a separate script: tests/live_check.gd

var _exit_code: int = 0
var _finished: bool = false

## The suite is started here and awaited inside the coroutine: awaiting inside
## `_process` would make the engine read a coroutine state as "quit now".
func _initialize() -> void:
	_run()

func _process(_delta: float) -> bool:
	return _finished

func _run() -> void:
	await _run_all()
	print("")
	_finished = true
	quit(_exit_code)

func _run_all() -> void:
	print("Pollinations add-on tests (offline)")
	TestErrors.run()
	TestUrls.run()
	TestModels.run()
	TestConfig.run()
	await TestClient.run()
	await TestNodes.run()
	await TestImage.run()
	await TestSpeech.run()
	await TestAuth.run()
	await TestCatalog.run()
	_exit_code = 1 if PollinationsTest.report("total") > 0 else 0
