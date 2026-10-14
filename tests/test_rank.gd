extends SceneTree
const Fake = preload("res://addons/syntaxcircus_games/fake_games_service.gd")
const Null = preload("res://addons/syntaxcircus_games/null_games_service.gd")
var answers: Array = []
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var fake = Fake.new()
	assert(fake.has_method("load_player_rank"), "Rank contract must exist")
	fake.rank_finished.connect(func(result): answers.append(result))
	fake.load_player_rank("lb", 17)
	assert(answers == [{"ok": true, "code": "completed", "board": "lb", "rank": 0, "request": 17}])
	fake.hold_rank = true
	fake.load_player_rank("other", 18)
	assert(answers.size() == 1 and fake.loaded_ranks == ["lb", "other"])
	assert(fake.rank_requests.back() == {"board": "other", "request": 18})
	fake.finish_rank("unavailable", 5)
	assert(answers.back().rank == 0 and answers.back().request == 18 and not answers.back().ok)
	fake.finish_rank("completed", 5)
	assert(answers.back().rank == 5)
	answers.clear()
	var unavailable = Null.new()
	unavailable.rank_finished.connect(func(result): answers.append(result))
	unavailable.load_player_rank("lb", 19)
	assert(answers.size() == 1 and answers[0].code == "unavailable" and answers[0].rank == 0 and answers[0].request == 19)
	print("RANK CONTRACT TESTS: passed")
	quit()
