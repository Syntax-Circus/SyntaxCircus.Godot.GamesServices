extends SceneTree
## The games service seam (P5-16): the null service answers "unavailable" once per call; the fake records calls and replays outcomes.
const NullService = preload("res://addons/syntaxcircus_games/null_games_service.gd")
const Fake = preload("res://addons/syntaxcircus_games/fake_games_service.gd")

var failures: Array[String] = []
var checks := 0
var _answers: Array = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_null()
	test_fake()
	print("GAMES SERVICE TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_null() -> void:
	var service = NullService.new()
	check(not service.is_available() and not service.is_signed_in() and service.platform() == "", "The null service is unavailable, signed out and has no platform")
	_answers.clear()
	service.score_finished.connect(func(result: Dictionary): _answers.append(result))
	service.submit_score("wfpdaily", 5)
	check(_answers.size() == 1 and _answers[0].code == "unavailable" and not bool(_answers[0].ok) and _answers[0].value == 5, "A submit answers unavailable exactly once")
	_answers.clear()
	service.sign_in_finished.connect(func(result: Dictionary): _answers.append(result))
	service.sign_in()
	check(_answers.size() == 1 and _answers[0].code == "unavailable", "Sign in answers unavailable exactly once")

func test_fake() -> void:
	var service = Fake.new()
	check(service.is_available() and not service.is_signed_in() and service.platform() == "game_center", "The fake starts available and signed out")
	_answers.clear()
	service.sign_in_finished.connect(func(result: Dictionary): _answers.append(result))
	service.sign_in_succeeds = false
	service.sign_in()
	check(_answers.size() == 1 and _answers[0].code == "signed_out" and not service.is_signed_in() and service.sign_in_calls == 1, "A declined sign in stays signed out")
	service.sign_in_succeeds = true
	service.sign_in()
	check(_answers[1].ok and service.is_signed_in(), "A later sign in succeeds")
	_answers.clear()
	service.score_finished.connect(func(result: Dictionary): _answers.append(result))
	service.submit_score("wfplongestfling", 840)
	check(service.submitted == [{"board": "wfplongestfling", "value": 840}] and _answers.size() == 1 and _answers[0].ok, "A submit is recorded and answered")
	service.hold = true
	service.submit_score("wfpdaily", 2000000)
	check(_answers.size() == 1, "A held submit has no answer yet")
	service.finish_score("failed")
	check(_answers.size() == 2 and _answers[1].code == "failed" and _answers[1].board == "wfpdaily" and _answers[1].value == 2000000, "finish_score answers the held submit")
	service.unlock("wfpachpuisclear")
	service.report_progress("wfpachpulverized", 20, 50)
	service.show_board("wfpdaily")
	service.show_board("daily_mon", true)
	check(service.unlocked == ["wfpachpuisclear"] and service.progress == [{"id": "wfpachpulverized", "count": 20, "target": 50}] and service.shown_boards == ["wfpdaily", "daily_mon"], "Unlocks, progress and shown boards are recorded")
	check(service.shown_weekly == [false, true], "Whether a board was opened on its weekly span is recorded")
