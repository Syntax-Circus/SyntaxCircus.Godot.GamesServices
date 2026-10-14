extends "res://addons/syntaxcircus_games/games_service.gd"
## Google Play Games Services v2 through the SyntaxCircusGames engine singleton (the plugin in android/).
## Nothing native happens at construction: the SDK is initialised and the player authenticated by the first sign_in(), so a game
## that calls sign_in() only after its own consent gate never starts Play Games before consent.
## The plugin answers with the interface's own status codes (completed, signed_out, unavailable, failed), so this class only
## correlates answers with requests and keeps the signed-in flag; it never guesses a reason.
const SINGLETON := "SyntaxCircusGames"
const SPAN_DEFAULT := -1
const SPAN_DAILY := 0
const SPAN_WEEKLY := 1
const SPAN_ALL_TIME := 2

var _plugin: Object
var _initialized := false
var _signed_in := false
## Native callbacks broadcast through one singleton, so IDs must remain unique when adapters are replaced.
static var _next_request := 0
var _pending: Dictionary = {} # request id -> {kind, board, value, id}

static func available() -> bool:
	return Engine.has_singleton(SINGLETON)

## `plugin` is only passed by tests; in a game call `.new()`.
func _init(plugin: Object = null) -> void:
	if plugin == null and available():
		plugin = Engine.get_singleton(SINGLETON)
	_plugin = plugin
	if _plugin == null:
		return
	_plugin.connect("sign_in_result", _on_sign_in_result)
	_plugin.connect("score_result", _on_score_result)
	if _plugin.has_signal("rank_result"):
		_plugin.connect("rank_result", _on_rank_result)
	_plugin.connect("achievement_result", _on_achievement_result)
	_plugin.connect("board_closed", _on_board_closed)

func is_available() -> bool:
	return _plugin != null

func platform() -> String:
	return "play_games"

func is_signed_in() -> bool:
	return _signed_in

func sign_in() -> void:
	if _plugin == null:
		sign_in_finished.emit(outcome(CODE_UNAVAILABLE))
		return
	if _signed_in:
		sign_in_finished.emit(outcome(CODE_COMPLETED))
		return
	if not _initialized:
		_initialized = true
		_plugin.call("initialize")
	_plugin.call("sign_in", _request({"kind": "sign_in"}))

func submit_score(board_id: String, value: int) -> void:
	var extra := {"board": board_id, "value": value}
	if _plugin == null:
		score_finished.emit(outcome(CODE_UNAVAILABLE, extra))
		return
	if not _signed_in:
		score_finished.emit(outcome(CODE_SIGNED_OUT, extra))
		return
	_plugin.call("submit_score", board_id, value, _request({"kind": "score", "board": board_id, "value": value}))

func load_player_rank(board_id: String, request: int = 0) -> void:
	var extra := {"board": board_id, "rank": 0, "request": request}
	if _plugin == null or not _plugin.has_method("load_player_rank") or not _plugin.has_signal("rank_result"):
		rank_finished.emit(outcome(CODE_UNAVAILABLE, extra))
		return
	if not _signed_in:
		rank_finished.emit(outcome(CODE_SIGNED_OUT, extra))
		return
	_plugin.call("load_player_rank", board_id, _request({"kind": "rank", "board": board_id, "request": request}))

func show_board(board_id: String, weekly := false) -> void:
	if _plugin == null or not _signed_in:
		board_closed.emit()
		return
	_plugin.call("show_leaderboard", board_id, SPAN_WEEKLY if weekly else SPAN_DEFAULT, _request({"kind": "board"}))

func unlock(achievement_id: String) -> void:
	if not _can_report(achievement_id):
		return
	_plugin.call("unlock", achievement_id, _request({"kind": "achievement", "id": achievement_id}))

## Absolute step count: Play Games treats it as "at least this many", so a repeat or a stale value changes nothing.
func report_progress(achievement_id: String, count: int, _target: int) -> void:
	if not _can_report(achievement_id):
		return
	_plugin.call("set_steps", achievement_id, count, _request({"kind": "achievement", "id": achievement_id}))

func show_achievements() -> void:
	if _plugin == null or not _signed_in:
		board_closed.emit()
		return
	_plugin.call("show_achievements", _request({"kind": "board"}))

## False after answering (unavailable or signed_out) when there is nothing to send to.
func _can_report(achievement_id: String) -> bool:
	if _plugin == null:
		achievement_finished.emit(outcome(CODE_UNAVAILABLE, {"id": achievement_id}))
		return false
	if not _signed_in:
		achievement_finished.emit(outcome(CODE_SIGNED_OUT, {"id": achievement_id}))
		return false
	return true

func _request(entry: Dictionary) -> int:
	_next_request += 1
	_pending[_next_request] = entry
	return _next_request

## Takes the entry for an answered request, or an empty dictionary for an unknown or repeated one (ignored).
func _take(request: int, kind: String) -> Dictionary:
	var entry: Dictionary = _pending.get(request, {})
	if entry.is_empty() or entry.kind != kind:
		return {}
	_pending.erase(request)
	return entry

func _on_sign_in_result(request: int, status: String, _message: String) -> void:
	if _take(request, "sign_in").is_empty():
		return
	_signed_in = status == CODE_COMPLETED
	sign_in_finished.emit(outcome(_known(status)))

func _on_score_result(request: int, status: String, _message: String) -> void:
	var entry := _take(request, "score")
	if entry.is_empty():
		return
	if status == CODE_SIGNED_OUT:
		_signed_in = false
	score_finished.emit(outcome(_known(status), {"board": entry.board, "value": entry.value}))

func _on_rank_result(request: int, status: String, rank: int, _message: String) -> void:
	var entry := _take(request, "rank")
	if entry.is_empty():
		return
	if status == CODE_SIGNED_OUT:
		_signed_in = false
	var code := _known(status)
	rank_finished.emit(outcome(code, {"board": entry.board, "rank": maxi(0, rank) if code == CODE_COMPLETED else 0, "request": entry.request}))

func _on_achievement_result(request: int, status: String, _message: String) -> void:
	var entry := _take(request, "achievement")
	if entry.is_empty():
		return
	if status == CODE_SIGNED_OUT:
		_signed_in = false
	achievement_finished.emit(outcome(_known(status), {"id": entry.id}))

func _on_board_closed(request: int) -> void:
	if _take(request, "board").is_empty():
		return
	board_closed.emit()

## A status the interface does not know is a failure, never a silent success.
func _known(status: String) -> String:
	return status if status in [CODE_COMPLETED, CODE_SIGNED_OUT, CODE_UNAVAILABLE, CODE_FAILED] else CODE_FAILED
