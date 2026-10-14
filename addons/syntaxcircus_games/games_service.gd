extends RefCounted
## Leaderboards and achievements behind one interface. Calls never block; every call ends in exactly one signal.
## Implementations: null (desktop, headless, no plugin), fake (tests), android_games_service (Play Games Services v2 plugin) and
## apple_games_service (Game Center through GameCenterKit).
## `completed` means the platform accepted it. `signed_out` and `unavailable` mean keep the item and try later; `failed` also keeps it
## but the caller counts an attempt, and drops the item after eight. Adapters must therefore report anything that can fix itself (no
## network, offline, a timeout, the store app busy) as `unavailable`, and use `failed` only for errors that will not go away on their own
## (an unknown board id, a rejected value). Cancelling a native board is a normal outcome, never an error.
signal sign_in_finished(result: Dictionary)
signal score_finished(result: Dictionary)
signal rank_finished(result: Dictionary)
signal achievement_finished(result: Dictionary)
signal board_closed

const CODE_COMPLETED := "completed"
const CODE_SIGNED_OUT := "signed_out"
const CODE_FAILED := "failed"
const CODE_UNAVAILABLE := "unavailable"

static func outcome(code: String, extra := {}) -> Dictionary:
	var result := {"ok": code == CODE_COMPLETED, "code": code}
	result.merge(extra)
	return result

## True when a platform (or the fake) is present. All board UI is hidden when this is false.
func is_available() -> bool:
	return false

## "game_center", "play_games" or "" (selects the id column in platform_ids.gd).
func platform() -> String:
	return ""

func is_signed_in() -> bool:
	return false

## Silent attempt; always ends in exactly one sign_in_finished, even when already signed in.
func sign_in() -> void:
	sign_in_finished.emit(outcome(CODE_UNAVAILABLE))

## `board_id` is the platform's id (platform_ids.gd). Exactly one score_finished with {board, value} follows.
func submit_score(board_id: String, value: int) -> void:
	score_finished.emit(outcome(CODE_UNAVAILABLE, {"board": board_id, "value": value}))

## Global public all-time, one-based player rank. Zero means no ranked score. Echoes the caller's request token.
func load_player_rank(board_id: String, request: int = 0) -> void:
	rank_finished.emit(outcome(CODE_UNAVAILABLE, {"board": board_id, "rank": 0, "request": request}))

## Opens the platform's UI for one board. `weekly` asks for the weekly span (the Play Games Daily boards, platform-mapping.md); adapters
## for platforms without time spans ignore it. board_closed follows when the platform says it was dismissed.
func show_board(_board_id: String, _weekly := false) -> void:
	board_closed.emit()

## Idempotent on both platforms. Exactly one achievement_finished with {id} follows.
func unlock(achievement_id: String) -> void:
	achievement_finished.emit(outcome(CODE_UNAVAILABLE, {"id": achievement_id}))

## Incremental achievements (Pu-lverized, 50 collisions). Same single answer as unlock.
func report_progress(achievement_id: String, _count: int, _target: int) -> void:
	achievement_finished.emit(outcome(CODE_UNAVAILABLE, {"id": achievement_id}))

func show_achievements() -> void:
	board_closed.emit()
