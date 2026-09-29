# Pollinations for Godot

Text, image and speech generation inside a Godot 4 game, through the
[Pollinations](https://pollinations.ai) API. Includes a **device sign-in flow** so
each player can pay with their own Pollen instead of your key.

[![Tests](https://github.com/xiaotian1171/pollinations-godot/actions/workflows/tests.yml/badge.svg)](https://github.com/xiaotian1171/pollinations-godot/actions/workflows/tests.yml)

```gdscript
var text := PollinationsText.new()
add_child(text)
var result := await text.generate("Describe a watermill in one sentence.")
if result.ok:
    $Label.text = result.content
```

## What you get

| Node | What it does |
| --- | --- |
| `PollinationsText` | Chat and single-prompt text generation |
| `PollinationsImage` | Image generation, decoded into an `ImageTexture` |
| `PollinationsSpeech` | Speech, music and sound effects, decoded into an `AudioStream` |
| `PollinationsAuth` | Device sign-in so players pay with their own Pollen (BYOP) |
| `PollinationsCatalog` | The **live** model catalogue, so a game offers whatever exists today |
| `PollinationsClient` | One retrying HTTP layer shared by all of the above |

Also included: a stable error classification (auth / balance / rate limit / bad
request / server / network / parse), exponential backoff, binary-aware response
handling, an example scene, and a **headless test suite**.

## Requirements

- Godot **4.5** is what this repository is developed and tested against
  (`4.5.stable.official`); 4.3+ is expected to work.
- No HTTP middleware: the add-on uses `HTTPRequest` directly, so it works on
  desktop, mobile and web exports. On the web, the Pollinations API must allow
  your origin (CORS) — see *Notes*.

## Install

1. Copy the `addons/pollinations/` folder into your project's `addons/` folder.
2. `Project > Project Settings > Plugins` and enable **Pollinations**.
   This registers the two settings below; the add-on works without the editor
   plugin too, since every node creates its own client.
3. Project Settings:

   | Setting | Value |
   | --- | --- |
   | `pollinations/api_key` | `sk_...` for your own builds. **Do not ship this in a released game.** |
   | `pollinations/app_key` | `pk_...` app key of your game, used by the device flow. |

   Both can be left empty: paste a key at runtime, use the device flow, or send
   anonymous requests (rate limited — a key is the reliable path).

## Sign-in with the player's own Pollen (BYOP)

A shipped game must not contain a secret: anyone can extract it from the binary
and spend your pollen. Instead, let the player sign in once. The game shows a
short code, the player approves it in their browser, and the game receives a key
that belongs to that player.

```gdscript
var auth: PollinationsAuth

func _ready() -> void:
    auth = PollinationsAuth.new()
    add_child(auth)
    auth.code_ready.connect(_on_code)
    auth.signed_in.connect(func(user): print("signed in: ", user.get("preferred_username", "")))

func _on_code(user_code: String, url: String, _expires_in: int) -> void:
    # show these to the player; the URL is https://enter.pollinations.ai/device
    code_label.text = user_code
    url_label.text = url

func _sign_in_pressed() -> void:
    var result := await auth.sign_in()
    if not result.ok:
        status.text = result.error
```

Under the hood the node asks `/api/device/code` for a code, polls
`/api/device/token` every 5 seconds until the player approves, stores the key on
the device (7 days, revocable by the player) and optionally reads
`/api/device/userinfo`. The flow is the documented one, matching the same
`pk_...` app key convention used elsewhere in the Pollinations ecosystem.

## Usage

### Text

```gdscript
var text := PollinationsText.new()
text.system_prompt = "You are the miller of a small village. Answer in one sentence."
text.model = "nova-fast"          # or anything from the live catalogue
add_child(text)

var result := await text.generate("What is the mill like?")
if result.ok:
    print(result.content, " ", result.usage)
else:
    print(result.error, " ", PollinationsErrors.message(result.kind))
```

`generate()` sends a chat completion. `quick(prompt, seed)` uses the cheaper
`GET /text/{prompt}` route for one-line flavour text.

### Image

```gdscript
var image := PollinationsImage.new()
image.width = 512
image.height = 512
add_child(image)

var result := await image.generate("a wooden watermill, flat illustration")
if result.ok:
    $Sprite2D.texture = result.texture      # ImageTexture, ready to use
    print(result.mime, " ", result.size)    # image/jpeg (512, 512)
```

### Speech

```gdscript
var speech := PollinationsSpeech.new()
speech.voice = "alloy"
add_child(speech)

var result := await speech.generate("Welcome to Pollen Village, traveller.")
if result.ok:
    $AudioStreamPlayer.stream = result.stream
    $AudioStreamPlayer.play()
```

`mp3`, `wav` and `ogg` are decoded straight from the response. `opus`, `aac`,
`flac` and `pcm` come back as raw bytes in `result.bytes`, to be written to a
file if you need them.

### Live model catalogue

```gdscript
var catalog := PollinationsCatalog.new()
add_child(catalog)
var result := await catalog.fetch("text")
if result.ok:
    for id: String in catalog.ids():
        model_picker.add_item(id)
    # only the models that accept the chat route:
    for entry: Dictionary in catalog.supporting("/v1/chat/completions"):
        print(PollinationsModels.label_of(entry))
```

## Error handling

Every result is a Dictionary with `ok`, `kind`, `kind_name`, `status`, `error`,
`message`, `attempts` and `url`. `kind` is one of:

| Kind | Meaning | Retried |
| --- | --- | --- |
| `NONE` | Success | – |
| `AUTH` | Missing, invalid or revoked key | no |
| `BALANCE` | Key valid, no pollen left (`402`, or a body that says so) | no |
| `RATE_LIMIT` | `429` | yes, with backoff |
| `BAD_REQUEST` | Unknown model id, bad parameters | no |
| `SERVER` | `5xx` from Pollinations or the upstream model | yes, with backoff |
| `NETWORK` | DNS, TLS, timeout, dead connection | yes, with backoff |
| `PARSE` | `200` with a payload that cannot be used | no |

`PollinationsErrors.message(kind)` returns a player-facing sentence you can show
in-game. Rate limits and server errors are retried twice by default
(`client.max_retries`), waiting `0.75s`, then `1.5s`.

## The example scene

Open this repository as a project and press <kbd>F5</kbd>. `demo/main.gd` builds a
small UI around every node: paste a key or sign in, generate text, an image and
speech, and pick models from the live catalogues. Everything is built in code so
the whole example is one readable file.

## Tests

Two suites, both headless:

```bash
# 1. offline: pure logic and a scripted transport, no network, no keys
godot --headless --path . --import          # once, to build the class cache
godot --headless --path . --script tests/run_tests.gd     # 242 checks

# 2. live: talks to the real API, needs a key for the signed steps
POLLINATIONS_API_KEY=sk_... godot --headless --path . --script tests/live_check.gd
```

The offline suite covers URL building, error classification, response parsing,
the client's retry policy, image format sniffing and decoding, the speech
request shape, the whole device flow (with scripted `authorization_pending`
answers), and the catalogue. It never touches the network, which is what makes
it usable in CI — see `.github/workflows/tests.yml`.

`tests/live_check.gd` is the evidence script: it prints real status codes,
latencies, model names and payload shapes. A run on Godot 4.5 against the live
API produced, among others:

- `chat` `200` in ~1.6s, model `us.amazon.nova-micro-v1:0`, usage
  `{"prompt_tokens":14,"completion_tokens":23,"total_tokens":37}`
- the prompt route `200` in ~1.2s with a plain answer
- `image` `200` in ~2.8s: JPEG, 256×256, 19 113 bytes, decoded into a texture
- catalogues: 110 text models, 18 image models, 4 audio models
- `speech` `402` on a free account, classified as a balance failure with the
  message the API sent (speech models need paid pollen)
- the device flow: `POST /api/device/code` `200` with `user_code`,
  `expires_in=1800`, `interval=5`, then `POST /api/device/token` `400`
  `{"error":"authorization_pending"}` while nobody had approved

## Layout

```
addons/pollinations/
  plugin.cfg, plugin.gd      the editor plugin (registers the project settings)
  config.gd                  key resolution, defaults
  http/pollinations_client.gd  retries, classification, binary handling
  util/                      urls, errors, catalogue parsing
  nodes/                     the five usable nodes
demo/                        the example scene and its script
tests/                       offline suite, live check, scripted transport
```

## Notes and limits

- **Never ship a server-side key** in a released game. Use the device flow, or a
  key the player pastes.
- Speech models require **paid pollen**; text and image models answered on a free
  account in the run above.
- Anonymous requests are rate limited and were answered `200` and `401` at
  different times; treat a key as required.
- `PollinationsImage` sniffs JPEG, PNG, WebP, GIF and SVG. Godot cannot decode
  GIF or raw SVG bytes in every version; when it cannot, the node reports a
  `PARSE` failure instead of handing back an empty texture.
- On the web export the browser enforces CORS. If `gen.pollinations.ai` does not
  allow your origin, route the requests through your own backend. Desktop and
  mobile exports are not affected.
- The audio catalogue endpoint sometimes lists only transcription models; the
  demo keeps the default model selectable in that case.

## License

MIT, see [LICENSE](LICENSE).
