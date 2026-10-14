extends SceneTree
## The Android adapter against a fake SyntaxCircusGames singleton: exactly-once answers, request correlation, status codes
## passed through, nothing native before sign_in, and the weekly span for the Daily boards.
const Android = preload("res://addons/syntaxcircus_games/android_games_service.gd")

class FakePlugin extends Object:
	signal sign_in_result(request: int, status: String, message: String)
	signal score_result(request: int, status: String, message: String)
	signal rank_result(request: int, status: String, rank: int, message: String)
	signal achievement_result(request: int, status: String, message: String)
	signal board_closed(request: int)
	var calls: Array = []
	func initialize() -> void:
		calls.append(["initialize"])
	func sign_in(request: int) -> void:
		calls.append(["sign_in", request])
	func is_authenticated() -> bool:
		return false
	func submit_score(board: String, score: int, request: int) -> void:
		calls.append(["submit_score", board, score, request])
	func show_leaderboard(board: String, time_span: int, request: int) -> void:
		calls.append(["show_leaderboard", board, time_span, request])
	func load_player_rank(board: String, request: int) -> void:
		calls.append(["load_player_rank", board, request])
	func unlock(id: String, request: int) -> void:
		calls.append(["unlock", id, request])
	func set_steps(id: String, steps: int, request: int) -> void:
		calls.append(["set_steps", id, steps, request])
	func show_achievements(request: int) -> void:
		calls.append(["show_achievements", request])
	func last_request(method: String) -> int:
		for index in range(calls.size() - 1, -1, -1):
			if calls[index][0] == method:
				return int(calls[index][calls[index].size() - 1])
		return -1
	func count(method: String) -> int:
		var total := 0
		for call: Array in calls:
			if call[0] == method:
				total += 1
		return total

var failures: Array[String] = []
var checks := 0
var answers: Array = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_singleton_absent()
	test_nothing_happens_at_construction()
	test_sign_in()
	test_signed_out_short_circuits()
	test_scores()
	test_ranks()
	test_rank_callbacks_do_not_cross_adapters()
	test_boards()
	test_achievements()
	test_unknown_requests_are_ignored()
	print("ANDROID GAMES SERVICE TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func listen(service: RefCounted) -> void:
	answers.clear()
	service.sign_in_finished.connect(func(result: Dictionary): answers.append(["sign_in", result]))
	service.score_finished.connect(func(result: Dictionary): answers.append(["score", result]))
	service.rank_finished.connect(func(result: Dictionary): answers.append(["rank", result]))
	service.achievement_finished.connect(func(result: Dictionary): answers.append(["achievement", result]))
	service.board_closed.connect(func(): answers.append(["board_closed", {}]))

func signed_in(plugin: FakePlugin) -> RefCounted:
	var service = Android.new(plugin)
	listen(service)
	service.sign_in()
	plugin.sign_in_result.emit(plugin.last_request("sign_in"), "completed", "")
	answers.clear()
	return service

func test_singleton_absent() -> void:
	check(not Android.available(), "No SyntaxCircusGames singleton is registered in the test host")
	var service = Android.new()
	listen(service)
	check(not service.is_available() and service.platform() == "play_games" and not service.is_signed_in(), "Without the plugin the service is unavailable but names its platform")
	service.sign_in()
	service.submit_score("lb", 5)
	service.show_board("lb", true)
	service.unlock("ach")
	service.report_progress("ach", 1, 5)
	service.show_achievements()
	check(answers.size() == 6, "Every call is answered exactly once without the plugin (%d)" % answers.size())
	check(answers[0][1].code == "unavailable" and answers[1][1].code == "unavailable" and answers[1][1].board == "lb" and int(answers[1][1].value) == 5, "Each answers unavailable and keeps its board and value")
	check(answers[3][1].code == "unavailable" and answers[3][1].id == "ach", "Achievement answers carry their id")
	check(answers[2][0] == "board_closed" and answers[5][0] == "board_closed", "Boards answer board_closed")

func test_nothing_happens_at_construction() -> void:
	var plugin := FakePlugin.new()
	var service = Android.new(plugin)
	check(plugin.calls.is_empty(), "Constructing the adapter initialises nothing and authenticates nobody (consent gate)")
	check(service.is_available() and not service.is_signed_in(), "A plugin makes it available, signed out")
	plugin.free()

func test_sign_in() -> void:
	var plugin := FakePlugin.new()
	var service = Android.new(plugin)
	listen(service)
	service.sign_in()
	check(plugin.count("initialize") == 1 and plugin.count("sign_in") == 1, "The first sign in initialises the SDK once, then signs in")
	check(answers.is_empty(), "No answer until the plugin answers")
	plugin.sign_in_result.emit(plugin.last_request("sign_in"), "completed", "")
	check(answers.size() == 1 and answers[0][1].ok and service.is_signed_in(), "A completed sign in answers once and signs in")
	service.sign_in()
	check(plugin.count("sign_in") == 1 and answers.size() == 2 and answers[1][1].ok, "Signing in again answers at once without another native call")
	var declined := FakePlugin.new()
	var other = Android.new(declined)
	listen(other)
	other.sign_in()
	declined.sign_in_result.emit(declined.last_request("sign_in"), "signed_out", "declined")
	check(answers.size() == 1 and answers[0][1].code == "signed_out" and not other.is_signed_in(), "A declined sign in is signed_out")
	other.sign_in()
	check(declined.count("initialize") == 1 and declined.count("sign_in") == 2, "The SDK is initialised once however often sign in is retried")
	declined.sign_in_result.emit(declined.last_request("sign_in"), "unavailable", "offline")
	check(answers[answers.size() - 1][1].code == "unavailable", "Offline during sign in is unavailable")
	plugin.free()
	declined.free()

func test_signed_out_short_circuits() -> void:
	var plugin := FakePlugin.new()
	var service = Android.new(plugin)
	listen(service)
	service.submit_score("lb", 9)
	service.unlock("ach")
	service.show_board("lb", false)
	check(plugin.calls.is_empty(), "A signed out player triggers no native call")
	check(answers[0][1].code == "signed_out" and answers[1][1].code == "signed_out" and answers[2][0] == "board_closed", "Each is answered signed_out or closed immediately")
	plugin.free()

func test_scores() -> void:
	var plugin := FakePlugin.new()
	var service = signed_in(plugin)
	service.submit_score("CgkIlb", 1234)
	check(plugin.count("submit_score") == 1 and plugin.calls.back()[1] == "CgkIlb" and plugin.calls.back()[2] == 1234, "The score goes to the plugin with its board id")
	plugin.score_result.emit(plugin.last_request("submit_score"), "completed", "")
	check(answers.size() == 1 and answers[0][1].ok and answers[0][1].board == "CgkIlb" and int(answers[0][1].value) == 1234, "The answer carries the board and value")
	service.submit_score("CgkIlb", 5)
	plugin.score_result.emit(plugin.last_request("submit_score"), "unavailable", "network")
	check(answers[1][1].code == "unavailable" and service.is_signed_in(), "Offline is unavailable and does not sign the player out")
	service.submit_score("CgkIlb", 6)
	plugin.score_result.emit(plugin.last_request("submit_score"), "signed_out", "")
	check(answers[2][1].code == "signed_out" and not service.is_signed_in(), "A signed_out answer signs the service out")
	plugin.free()

func test_boards() -> void:
	var plugin := FakePlugin.new()
	var service = signed_in(plugin)
	service.show_board("daily_tue", true)
	check(plugin.calls.back()[0] == "show_leaderboard" and plugin.calls.back()[2] == 1, "The Daily boards open on the weekly span")
	plugin.board_closed.emit(plugin.last_request("show_leaderboard"))
	check(answers.size() == 1 and answers[0][0] == "board_closed", "The board answers board_closed once")
	service.show_board("lb", false)
	check(plugin.calls.back()[2] == -1, "Other boards use the default span")
	plugin.board_closed.emit(plugin.last_request("show_leaderboard"))
	service.show_achievements()
	plugin.board_closed.emit(plugin.last_request("show_achievements"))
	check(answers.size() == 3, "Achievements UI answers board_closed too")
	plugin.free()

func test_ranks() -> void:
	var plugin := FakePlugin.new()
	var service = Android.new(plugin)
	listen(service)
	service.load_player_rank("lb", 70)
	check(answers.back()[1].code == "signed_out" and answers.back()[1].request == 70 and plugin.calls.is_empty(), "Rank lookup respects sign-in consent")
	service = signed_in(plugin)
	service.load_player_rank("lb", 71)
	var request := plugin.last_request("load_player_rank")
	check(plugin.calls.back()[1] == "lb" and answers.is_empty(), "Rank lookup waits for the matching native answer")
	plugin.rank_result.emit(request + 99, "completed", 1, "")
	check(answers.is_empty(), "Unknown rank request is ignored")
	plugin.rank_result.emit(request, "completed", 10, "")
	plugin.rank_result.emit(request, "completed", 1, "")
	check(answers.size() == 1 and answers[0][1] == {"ok": true, "code": "completed", "board": "lb", "rank": 10, "request": 71}, "Rank keeps board, rank and caller token and ignores duplicates")
	for status in ["completed", "unavailable", "nonsense", "signed_out"]:
		service.load_player_rank("lb", 72)
		plugin.rank_result.emit(plugin.last_request("load_player_rank"), status, -1, "")
		check(answers.back()[1].rank == 0 and answers.back()[1].code == ("failed" if status == "nonsense" else status), "Absent/error ranks return zero with mapped status")
	check(not service.is_signed_in(), "Rank signed_out updates authentication state")
	plugin.free()

func test_rank_callbacks_do_not_cross_adapters() -> void:
	var plugin := FakePlugin.new()
	var old_service = signed_in(plugin)
	old_service.load_player_rank("lb", 81)
	var old_request := plugin.last_request("load_player_rank")
	var current = Android.new(plugin)
	var current_answers: Array = []
	current.rank_finished.connect(func(result: Dictionary): current_answers.append(result))
	current.sign_in()
	plugin.sign_in_result.emit(plugin.last_request("sign_in"), "completed", "")
	current.load_player_rank("lb", 82)
	var current_request := plugin.last_request("load_player_rank")
	plugin.rank_result.emit(old_request, "completed", 1, "")
	check(current_answers.is_empty(), "A late previous-adapter rank cannot satisfy the current adapter request")
	plugin.rank_result.emit(current_request, "completed", 11, "")
	check(current_answers.size() == 1 and current_answers[0].rank == 11 and current_answers[0].request == 82, "The current adapter receives only its own native rank and caller token")
	plugin.free()

func test_achievements() -> void:
	var plugin := FakePlugin.new()
	var service = signed_in(plugin)
	service.unlock("ach1")
	plugin.achievement_result.emit(plugin.last_request("unlock"), "completed", "")
	check(answers.size() == 1 and answers[0][1].ok and answers[0][1].id == "ach1", "An unlock answers with its id")
	service.report_progress("ach2", 20, 50)
	check(plugin.calls.back()[0] == "set_steps" and plugin.calls.back()[1] == "ach2" and plugin.calls.back()[2] == 20, "Progress is sent as an absolute step count (idempotent)")
	plugin.achievement_result.emit(plugin.last_request("set_steps"), "unavailable", "offline")
	check(answers[1][1].code == "unavailable" and answers[1][1].id == "ach2", "Offline progress is unavailable")
	plugin.free()

func test_unknown_requests_are_ignored() -> void:
	var plugin := FakePlugin.new()
	var service = signed_in(plugin)
	service.submit_score("lb", 1)
	var request := plugin.last_request("submit_score")
	plugin.score_result.emit(request + 99, "completed", "")
	check(answers.is_empty(), "An answer for an unknown request is ignored")
	plugin.score_result.emit(request, "completed", "")
	plugin.score_result.emit(request, "completed", "")
	check(answers.size() == 1, "A repeated answer for the same request is ignored")
	plugin.free()
