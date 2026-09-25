class_name CommunitySource
extends Node
## Where the community shelf's globes come from.
##
## The site provides a JSON array of globes (each one a preset, as saved by
## GlobePreset, with "name" and "creator"); an object with a "globes" array
## works too. Looked for, in order:
##   1. window.snowglobe.community on the page: the array itself or a URL.
##   2. ?community=<url> in the page address.
##   3. community.json next to the game's index.html.
## If none of those give anything (or when running outside a browser), a
## generated demo shelf is used so everything can be tried out.

signal loaded(globes: Array)

@export var demo_count := 36

const DEMO_CREATORS := ["Stew", "Maddie", "PixelPete", "Jo", "ArcadeAce", "Sam", "TicketTyrant", "Riley", "SnowQueen", "Max", "Bex", "Coinop", "Nina", "Theo", "GlitterGal", "Dev", "Ollie", "Kit"]

var _http: HTTPRequest


## Starts loading; `loaded` fires once with the list.
func fetch() -> void:
	if OS.has_feature("web"):
		var inline = JavaScriptBridge.eval("JSON.stringify((window.snowglobe && window.snowglobe.community) || null)", true)
		var parsed = JSON.parse_string(String(inline)) if inline != null else null
		var list := _as_list(parsed)
		if not list.is_empty():
			_done.call_deferred(list)
			return
		var url := ""
		if parsed is String:
			url = parsed
		if url.is_empty():
			url = String(JavaScriptBridge.eval("new URLSearchParams(location.search).get('community') || ''", true))
		if url.is_empty():
			url = "community.json"
		_http = HTTPRequest.new()
		add_child(_http)
		_http.request_completed.connect(_on_response)
		if _http.request(url) == OK:
			return
	_done.call_deferred(demo(demo_count))


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var list := []
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		list = _as_list(JSON.parse_string(body.get_string_from_utf8()))
	_done(list if not list.is_empty() else demo(demo_count))


func _done(list: Array) -> void:
	loaded.emit(list)


static func _as_list(parsed) -> Array:
	if parsed is Dictionary and parsed.get("globes") is Array:
		parsed = parsed["globes"]
	if parsed is Array:
		return parsed.filter(func(g) -> bool: return g is Dictionary)
	return []


## A made-up community: the built-in presets plus random globes (everything
## unlocked, since other players could have bought anything), each with a
## maker's name.
static func demo(count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025
	var out := []
	var presets := GlobePreset.list_presets().filter(func(e: Dictionary) -> bool: return e["builtin"])
	for i in count:
		var data: Dictionary
		if i % 2 == 0 and i / 2 < presets.size():
			data = GlobePreset.load_file(presets[i / 2]["path"])
		else:
			data = GlobeRandomizer.roll(rng, false) if rng.randf() < 0.75 else GlobeRandomizer.roll_chaos(rng, false)
		data["creator"] = DEMO_CREATORS[rng.randi() % DEMO_CREATORS.size()]
		out.append(data)
	return out
