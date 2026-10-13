extends "res://addons/syntaxcircus_games/games_service.gd"
## Apple Game Center through the GameCenterKit engine singleton (keremvatandas/godot-ios-gamecenter, vendored by the game).
## Nothing native happens at construction: authenticate() is first called by sign_in(), which the game calls after its consent gate.
## GameCenterKit reports success flags and error strings, not codes, so errors are classified by wording, conservatively: only
## clear network wording is unavailable (kept and retried), only clear not-authenticated or cancelled wording is signed_out, and
## everything else is failed. The wording is a heuristic and is re-checked on a device.
const SINGLETON := "GameCenterKit"
const NETWORK_WORDS := ["network", "internet", "offline", "connection", "timed out", "timeout", "communications", "connectivity"]
const SIGNED_OUT_WORDS := ["not been authenticated", "not authenticated", "not signed in", "cancelled", "canceled", "sign in", "authenticate"]

var _kit: Object
var _signed_in := false
var _scores: Dictionary = {} # board id -> Array of value, answered in order
var _achievements: Dictionary = {} # achievement id -> count of reports waiting for an answer
var _panels := 0 # panels shown and not yet answered

static func available() -> bool:
	return Engine.has_singleton(SINGLETON)

## `kit` is only passed by tests; in a game call `.new()`.
func _init(kit: Object = null) -> void:
	if kit == null and available():
		kit = Engine.get_singleton(SINGLETON)
	_kit = kit
	if _kit == null:
		return
	_kit.connect("authenticated", _on_authenticated)
	_kit.connect("score_submitted", _on_score_submitted)
	_kit.connect("achievement_reported", _on_achievement_reported)
	_kit.connect("panel_closed", _on_panel_closed)
	_kit.connect("panel_failed", _on_panel_failed)

## Maps a GameCenterKit error string to an interface code. Public so the mapping is pinned by a test.
static func classify(error: String) -> String:
	var text := error.to_lower()
	if text.is_empty():
		return CODE_FAILED
	for word: String in NETWORK_WORDS:
		if text.contains(word):
			return CODE_UNAVAILABLE
	for word: String in SIGNED_OUT_WORDS:
		if text.contains(word):
			return CODE_SIGNED_OUT
	return CODE_FAILED

func is_available() -> bool:
	return _kit != null

func platform() -> String:
	return "game_center"

func is_signed_in() -> bool:
	return _signed_in

func sign_in() -> void:
	if _kit == null:
		sign_in_finished.emit(outcome(CODE_UNAVAILABLE))
		return
	if _signed_in:
		sign_in_finished.emit(outcome(CODE_COMPLETED))
		return
	_kit.call("authenticate")

func submit_score(board_id: String, value: int) -> void:
	var extra := {"board": board_id, "value": value}
	if _kit == null:
		score_finished.emit(outcome(CODE_UNAVAILABLE, extra))
		return
	if not _signed_in:
		score_finished.emit(outcome(CODE_SIGNED_OUT, extra))
		return
	if not _scores.has(board_id):
		_scores[board_id] = []
	_scores[board_id].append(value)
	_kit.call("submit_score", board_id, value)

## The weekly flag is ignored: Game Center's Daily is one recurring board whose current occurrence is what opens.
func show_board(board_id: String, _weekly := false) -> void:
	if _kit == null or not _signed_in:
		board_closed.emit()
		return
	_panels += 1
	_kit.call("show_leaderboard", board_id)

func unlock(achievement_id: String) -> void:
	_report(achievement_id, 100.0)

## Game Center takes a whole percent: count * 100 / target, rounded down.
func report_progress(achievement_id: String, count: int, target: int) -> void:
	if target <= 0:
		achievement_finished.emit(outcome(CODE_FAILED, {"id": achievement_id}))
		return
	_report(achievement_id, float(count * 100 / target))

func show_achievements() -> void:
	if _kit == null or not _signed_in:
		board_closed.emit()
		return
	_panels += 1
	_kit.call("show_achievements")

func _report(achievement_id: String, percent: float) -> void:
	if _kit == null:
		achievement_finished.emit(outcome(CODE_UNAVAILABLE, {"id": achievement_id}))
		return
	if not _signed_in:
		achievement_finished.emit(outcome(CODE_SIGNED_OUT, {"id": achievement_id}))
		return
	_achievements[achievement_id] = int(_achievements.get(achievement_id, 0)) + 1
	_kit.call("report_achievement", achievement_id, percent)

func _on_authenticated(ok: bool, error: String) -> void:
	if ok:
		_signed_in = true
		sign_in_finished.emit(outcome(CODE_COMPLETED))
		return
	_signed_in = false
	var code := classify(error)
	# A failed authenticate with no wording we recognise is the player not being signed in to Game Center, not a broken build.
	sign_in_finished.emit(outcome(CODE_SIGNED_OUT if code == CODE_FAILED else code))

func _on_score_submitted(ok: bool, id: String, error: String) -> void:
	var queue: Array = _scores.get(id, [])
	if queue.is_empty():
		return # a stray answer
	var value: int = queue.pop_front()
	var code := CODE_COMPLETED if ok else classify(error)
	if code == CODE_SIGNED_OUT:
		_signed_in = false
	score_finished.emit(outcome(code, {"board": id, "value": value}))

func _on_achievement_reported(ok: bool, id: String, error: String) -> void:
	var waiting := int(_achievements.get(id, 0))
	if waiting <= 0:
		return
	_achievements[id] = waiting - 1
	var code := CODE_COMPLETED if ok else classify(error)
	if code == CODE_SIGNED_OUT:
		_signed_in = false
	achievement_finished.emit(outcome(code, {"id": id}))

func _on_panel_closed(_panel: String) -> void:
	_answer_panel()

func _on_panel_failed(_panel: String, _error: String) -> void:
	_answer_panel()

func _answer_panel() -> void:
	if _panels <= 0:
		return
	_panels -= 1
	board_closed.emit()
