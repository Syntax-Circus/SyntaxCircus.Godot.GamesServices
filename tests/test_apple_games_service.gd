extends SceneTree
## The Apple adapter against a fake GameCenterKit singleton: signals mapped to the interface codes, error strings classified
## conservatively (offline wording is unavailable), answers correlated by board or achievement id, nothing native before sign_in.
const Apple = preload("res://addons/syntaxcircus_games/apple_games_service.gd")

class FakeKit extends Object:
	signal authenticated(ok: bool, error: String)
	signal score_submitted(ok: bool, id: String, error: String)
	signal achievement_reported(ok: bool, id: String, error: String)
	signal panel_closed(panel: String)
	signal panel_failed(panel: String, error: String)
	var calls: Array = []
	var auth_state := false
	func authenticate() -> void:
		calls.append(["authenticate"])
	func is_authenticated() -> bool:
		return auth_state
	func submit_score(id: String, score: int) -> void:
		calls.append(["submit_score", id, score])
	func report_achievement(id: String, percent: float) -> void:
		calls.append(["report_achievement", id, percent])
	func show_leaderboard(id: String) -> void:
		calls.append(["show_leaderboard", id])
	func show_achievements() -> void:
		calls.append(["show_achievements"])
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
	test_error_classification()
	test_scores_and_achievements()
	test_panels()
	print("APPLE GAMES SERVICE TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func listen(service: RefCounted) -> void:
	answers.clear()
	service.sign_in_finished.connect(func(result: Dictionary): answers.append(["sign_in", result]))
	service.score_finished.connect(func(result: Dictionary): answers.append(["score", result]))
	service.achievement_finished.connect(func(result: Dictionary): answers.append(["achievement", result]))
	service.board_closed.connect(func(): answers.append(["board_closed", {}]))

func signed_in(kit: FakeKit) -> RefCounted:
	var service = Apple.new(kit)
	listen(service)
	service.sign_in()
	kit.auth_state = true
	kit.authenticated.emit(true, "")
	answers.clear()
	return service

func test_singleton_absent() -> void:
	check(not Apple.available(), "No GameCenterKit singleton is registered in the test host")
	var service = Apple.new()
	listen(service)
	check(not service.is_available() and service.platform() == "game_center", "Without the plugin the service is unavailable but names its platform")
	service.sign_in()
	service.submit_score("wfpdaily", 3)
	service.unlock("a")
	service.show_board("wfpdaily", true)
	check(answers.size() == 4 and answers[0][1].code == "unavailable" and answers[1][1].board == "wfpdaily", "Calls are answered unavailable exactly once")

func test_nothing_happens_at_construction() -> void:
	var kit := FakeKit.new()
	var service = Apple.new(kit)
	check(kit.calls.is_empty(), "Constructing the adapter does not authenticate (consent gate)")
	check(service.is_available() and not service.is_signed_in(), "A plugin makes it available, signed out")
	kit.free()

func test_sign_in() -> void:
	var kit := FakeKit.new()
	var service = Apple.new(kit)
	listen(service)
	service.sign_in()
	check(kit.count("authenticate") == 1 and answers.is_empty(), "Sign in authenticates and waits for the answer")
	kit.authenticated.emit(true, "")
	check(answers.size() == 1 and answers[0][1].ok and service.is_signed_in(), "An authenticated player completes sign in")
	service.sign_in()
	check(kit.count("authenticate") == 1 and answers.size() == 2 and answers[1][1].ok, "Signing in again answers at once")
	var other_kit := FakeKit.new()
	var other = Apple.new(other_kit)
	listen(other)
	other.sign_in()
	other_kit.authenticated.emit(false, "The operation couldn't be completed. Player cancelled sign in")
	check(answers[0][1].code == "signed_out" and not other.is_signed_in(), "A cancelled sign in is signed_out")
	kit.free()
	other_kit.free()

func test_error_classification() -> void:
	check(Apple.classify("The Internet connection appears to be offline.") == "unavailable", "Offline wording is unavailable")
	check(Apple.classify("The request timed out.") == "unavailable", "Timeouts are unavailable")
	check(Apple.classify("A network error occurred") == "unavailable", "Network wording is unavailable")
	check(Apple.classify("The requested operation could not be completed because the local player has not been authenticated.") == "signed_out", "Not authenticated is signed_out")
	check(Apple.classify("Player cancelled sign in") == "signed_out", "Cancelled sign in is signed_out")
	check(Apple.classify("The leaderboard id is not recognised") == "failed", "An unknown board is failed, not retried forever as unavailable")
	check(Apple.classify("") == "failed", "An empty error is failed")

func test_scores_and_achievements() -> void:
	var kit := FakeKit.new()
	var service = signed_in(kit)
	service.submit_score("wfpdaily", 2000000)
	check(kit.calls.back() == ["submit_score", "wfpdaily", 2000000], "The score goes to GameCenterKit with its id")
	kit.score_submitted.emit(true, "wfpdaily", "")
	check(answers.size() == 1 and answers[0][1].ok and answers[0][1].board == "wfpdaily" and int(answers[0][1].value) == 2000000, "The answer carries board and value")
	service.submit_score("wfplongestfling", 840)
	kit.score_submitted.emit(false, "wfplongestfling", "The Internet connection appears to be offline.")
	check(answers[1][1].code == "unavailable" and service.is_signed_in(), "Offline keeps the item and the sign in")
	service.submit_score("wfpdaily", 1)
	kit.score_submitted.emit(false, "wfpdaily", "The local player has not been authenticated")
	check(answers[2][1].code == "signed_out" and not service.is_signed_in(), "Not authenticated signs the service out")
	# Sign back in (the not-authenticated answer signed the service out) before reporting achievements.
	service.sign_in()
	kit.authenticated.emit(true, "")
	answers.clear()
	service.unlock("wfpachpuisclear")
	check(kit.calls.back() == ["report_achievement", "wfpachpuisclear", 100.0], "Unlock reports 100 percent")
	kit.achievement_reported.emit(true, "wfpachpuisclear", "")
	check(answers.size() == 1 and answers[0][1].ok and answers[0][1].id == "wfpachpuisclear", "Unlock answers with its id")
	service.report_progress("wfpachpulverized", 20, 50)
	check(kit.calls.back() == ["report_achievement", "wfpachpulverized", 40.0], "Progress is a whole percent, rounded down")
	service.report_progress("wfpachpulverized", 49, 50)
	check(kit.calls.back()[2] == 98.0, "49 of 50 is 98 percent")
	kit.achievement_reported.emit(true, "wfpachpulverized", "")
	kit.achievement_reported.emit(true, "wfpachpulverized", "")
	kit.achievement_reported.emit(true, "wfpachpulverized", "")
	check(answers.size() == 3, "Each report is answered once, and a stray answer is ignored (%d)" % answers.size())
	service.report_progress("wfpachx", 1, 0)
	check(answers[answers.size() - 1][1].code == "failed", "A zero target cannot be reported")
	kit.free()

func test_panels() -> void:
	var kit := FakeKit.new()
	var service = signed_in(kit)
	service.show_board("wfpdaily", true)
	check(kit.calls.back() == ["show_leaderboard", "wfpdaily"], "A board opens by id; the weekly flag is ignored on Game Center")
	kit.panel_closed.emit("leaderboard")
	check(answers.size() == 1 and answers[0][0] == "board_closed", "Closing the panel answers board_closed once")
	service.show_achievements()
	kit.panel_failed.emit("achievements", "no")
	check(answers.size() == 2 and answers[1][0] == "board_closed", "A panel that failed to open still answers board_closed once")
	kit.panel_closed.emit("leaderboard")
	check(answers.size() == 2, "A stray panel signal is ignored")
	kit.free()
