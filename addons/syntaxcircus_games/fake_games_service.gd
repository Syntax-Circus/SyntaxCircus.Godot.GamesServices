extends "res://addons/syntaxcircus_games/games_service.gd"
## Tests only: records every call and replays scripted outcomes. `hold` keeps submit_score unanswered until finish_score().
var available := true
var platform_name := "game_center"
var signed_in := false
var sign_in_succeeds := true
var score_code := "completed"
var achievement_code := "completed"
var hold := false
var player_rank := 0
var rank_code := "completed"
var hold_rank := false
var loaded_ranks: Array = []
var rank_requests: Array = []
var failing_boards: Array = [] # platform board ids that always answer "failed"
var submitted: Array = []
var unlocked: Array = []
var progress: Array = []
var shown_boards: Array = []
var shown_weekly: Array = []
var sign_in_calls := 0

func is_available() -> bool:
	return available

func platform() -> String:
	return platform_name

func is_signed_in() -> bool:
	return signed_in

func sign_in() -> void:
	sign_in_calls += 1
	if not signed_in:
		signed_in = sign_in_succeeds
	sign_in_finished.emit(outcome(CODE_COMPLETED if signed_in else CODE_SIGNED_OUT))

func submit_score(board_id: String, value: int) -> void:
	submitted.append({"board": board_id, "value": value})
	if not hold:
		score_finished.emit(outcome("failed" if failing_boards.has(board_id) else score_code, {"board": board_id, "value": value}))

## Answers the most recent held submit.
func finish_score(code: String) -> void:
	var last: Dictionary = submitted.back() if not submitted.is_empty() else {"board": "", "value": 0}
	score_finished.emit(outcome(code, {"board": last.board, "value": last.value}))

func load_player_rank(board_id: String, request: int = 0) -> void:
	loaded_ranks.append(board_id)
	rank_requests.append({"board": board_id, "request": request})
	if not hold_rank:
		finish_rank(rank_code, player_rank)

func finish_rank(code: String, rank: int) -> void:
	var last: Dictionary = rank_requests.back() if not rank_requests.is_empty() else {"board": "", "request": 0}
	rank_finished.emit(outcome(code, {"board": last.board, "rank": maxi(0, rank) if code == CODE_COMPLETED else 0, "request": last.request}))

func show_board(board_id: String, weekly := false) -> void:
	shown_boards.append(board_id)
	shown_weekly.append(weekly)
	board_closed.emit()

func unlock(achievement_id: String) -> void:
	unlocked.append(achievement_id)
	achievement_finished.emit(outcome(achievement_code, {"id": achievement_id}))

func report_progress(achievement_id: String, count: int, target: int) -> void:
	progress.append({"id": achievement_id, "count": count, "target": target})
	achievement_finished.emit(outcome(achievement_code, {"id": achievement_id}))

func show_achievements() -> void:
	board_closed.emit()
