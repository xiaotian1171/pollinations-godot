class_name TestErrors
extends RefCounted

static func run() -> void:
	PollinationsTest.suite("errors")

	# transport-level failures win over any status code
	PollinationsTest.equal(
		PollinationsErrors.classify(0, "", HTTPRequest.RESULT_CANT_CONNECT),
		PollinationsErrors.Kind.NETWORK,
		"a broken connection is a network failure"
	)
	PollinationsTest.equal(
		PollinationsErrors.classify(200, "", HTTPRequest.RESULT_TIMEOUT),
		PollinationsErrors.Kind.NETWORK,
		"a timeout is a network failure even with a status code"
	)

	# status codes
	PollinationsTest.equal(PollinationsErrors.classify(200), PollinationsErrors.Kind.NONE, "200 is fine")
	PollinationsTest.equal(PollinationsErrors.classify(401), PollinationsErrors.Kind.AUTH, "401 is auth")
	PollinationsTest.equal(PollinationsErrors.classify(403), PollinationsErrors.Kind.AUTH, "403 is auth")
	PollinationsTest.equal(PollinationsErrors.classify(402), PollinationsErrors.Kind.BALANCE, "402 is out of pollen")
	PollinationsTest.equal(PollinationsErrors.classify(429), PollinationsErrors.Kind.RATE_LIMIT, "429 is rate limit")
	PollinationsTest.equal(PollinationsErrors.classify(500), PollinationsErrors.Kind.SERVER, "500 is a server error")
	PollinationsTest.equal(PollinationsErrors.classify(502), PollinationsErrors.Kind.SERVER, "502 is a server error")
	PollinationsTest.equal(PollinationsErrors.classify(400), PollinationsErrors.Kind.BAD_REQUEST, "400 is a bad request")
	PollinationsTest.equal(PollinationsErrors.classify(404), PollinationsErrors.Kind.BAD_REQUEST, "404 is a bad request")

	# a balance failure can also arrive as 400/500 with a body
	PollinationsTest.equal(
		PollinationsErrors.classify(400, '{"error":"INSUFFICIENT_BALANCE"}'),
		PollinationsErrors.Kind.BALANCE,
		"an insufficient balance body is a balance failure"
	)
	PollinationsTest.equal(
		PollinationsErrors.classify(500, "Insufficient balance for this request"),
		PollinationsErrors.Kind.BALANCE,
		"a balance message inside a 500 is a balance failure"
	)
	PollinationsTest.equal(
		PollinationsErrors.classify(400, '{"error":"unknown model"}'),
		PollinationsErrors.Kind.BAD_REQUEST,
		"an unknown model is a bad request"
	)

	# retry policy
	PollinationsTest.check(PollinationsErrors.retryable(PollinationsErrors.Kind.RATE_LIMIT), "rate limits are retryable")
	PollinationsTest.check(PollinationsErrors.retryable(PollinationsErrors.Kind.SERVER), "server errors are retryable")
	PollinationsTest.check(PollinationsErrors.retryable(PollinationsErrors.Kind.NETWORK), "network errors are retryable")
	PollinationsTest.check(not PollinationsErrors.retryable(PollinationsErrors.Kind.AUTH), "auth errors are not retryable")
	PollinationsTest.check(not PollinationsErrors.retryable(PollinationsErrors.Kind.BALANCE), "balance errors are not retryable")
	PollinationsTest.check(not PollinationsErrors.retryable(PollinationsErrors.Kind.BAD_REQUEST), "bad requests are not retryable")

	# backoff grows, then stops at the cap
	PollinationsTest.check(
		PollinationsErrors.backoff_seconds(1) > PollinationsErrors.backoff_seconds(0),
		"backoff grows with the attempt"
	)
	PollinationsTest.equal(PollinationsErrors.backoff_seconds(9, 0.75, 8.0), 8.0, "backoff is capped")
	PollinationsTest.check(PollinationsErrors.backoff_seconds(0, 0.75, 8.0) > 0.0, "backoff is positive")

	# readable output
	PollinationsTest.equal(PollinationsErrors.kind_name(PollinationsErrors.Kind.AUTH), "auth", "kinds have names")
	var description := PollinationsErrors.describe(PollinationsErrors.Kind.SERVER, 502, "bad gateway")
	PollinationsTest.contains(description, "server", "descriptions carry the kind")
	PollinationsTest.contains(description, "502", "descriptions carry the status")
	PollinationsTest.contains(
		PollinationsErrors.message(PollinationsErrors.Kind.BALANCE),
		"pollen",
		"the balance message tells the player what to do"
	)
