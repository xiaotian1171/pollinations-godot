class_name PollinationsTest
extends RefCounted

## A tiny assertion harness so the add-on can be tested with
## `godot --headless --path . --script tests/run_tests.gd` on a CI machine
## with no display and no network.

static var _passed: int = 0
static var _failed: int = 0
static var _failures: PackedStringArray = PackedStringArray()
static var _current: String = ""

static func suite(name: String) -> void:
	_current = name
	print("-- %s" % name)

static func check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: %s" % [_current, message])
		print("   FAIL %s" % message)

static func equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: %s (expected %s, got %s)" % [_current, message, str(expected), str(actual)])
		print("   FAIL %s (expected %s, got %s)" % [message, str(expected), str(actual)])

## Passes for anything that is neither null, false, zero, nor empty.
static func truthy(value: Variant, message: String) -> void:
	var ok := true
	match typeof(value):
		TYPE_NIL:
			ok = false
		TYPE_BOOL:
			ok = bool(value)
		TYPE_INT:
			ok = int(value) != 0
		TYPE_FLOAT:
			ok = not is_zero_approx(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			ok = not str(value).is_empty()
		TYPE_ARRAY, TYPE_DICTIONARY:
			ok = not (value as Variant).is_empty()
		TYPE_PACKED_BYTE_ARRAY:
			ok = not (value as PackedByteArray).is_empty()
	check(ok, message)

static func contains(haystack: String, needle: String, message: String) -> void:
	check(haystack.contains(needle), "%s (looked for %s in %s)" % [message, needle, haystack])

static func passed() -> int:
	return _passed

static func failed() -> int:
	return _failed

static func failures() -> PackedStringArray:
	return _failures

static func report(label: String) -> int:
	print("")
	print("%s: %d passed, %d failed" % [label, _passed, _failed])
	for failure: String in _failures:
		print("  - %s" % failure)
	return _failed
