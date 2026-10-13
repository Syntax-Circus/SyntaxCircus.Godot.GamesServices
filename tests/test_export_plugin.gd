extends SceneTree
## The export plugin's pure decisions: with no Play Games application id nothing is added to the build, with one the AAR, the
## games-v2 dependency, the APP_ID meta-data and the string resource are. Android-only; the id must look like a Play Games id.
const Export = preload("res://addons/syntaxcircus_games/export_plugin.gd")

var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_empty_id_adds_nothing()
	test_id_adds_the_plugin()
	test_id_validation()
	test_resource_xml()
	print("EXPORT PLUGIN TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_empty_id_adds_nothing() -> void:
	for app_id in ["", "   "]:
		check(Export.libraries_for(app_id, false).is_empty(), "No id, no AAR")
		check(Export.dependencies_for(app_id).is_empty(), "No id, no dependency")
		check(Export.manifest_contents_for(app_id) == "", "No id, no manifest entry")
		check(Export.resource_xml_for(app_id) == "", "No id, no resource")

func test_id_adds_the_plugin() -> void:
	var id := "123456789012"
	check(Export.libraries_for(id, true) == PackedStringArray(["syntaxcircus_games/bin/debug/SyntaxCircusGames-debug.aar"]), "The debug AAR for debug exports")
	check(Export.libraries_for(id, false) == PackedStringArray(["syntaxcircus_games/bin/release/SyntaxCircusGames-release.aar"]), "The release AAR for release exports")
	check(Export.dependencies_for(id) == PackedStringArray(["com.google.android.gms:play-services-games-v2:22.1.0"]), "The games-v2 SDK is a dependency of the game's own Gradle build")
	var manifest := Export.manifest_contents_for(id)
	check(manifest.contains("com.google.android.gms.games.APP_ID") and manifest.contains("@string/syntaxcircus_games_app_id"), "The APP_ID meta-data points at the string resource")
	check(not manifest.contains(id), "The id itself lives in the resource, not in the manifest text")

func test_id_validation() -> void:
	check(Export.valid_app_id("123456789012"), "A numeric project id is valid")
	check(Export.valid_app_id(""), "Empty means 'no games service' and is valid")
	check(not Export.valid_app_id("12ab34"), "Letters are not valid")
	check(not Export.valid_app_id("123"), "Too short")
	check(not Export.valid_app_id("1234567890123456789012345"), "Too long")
	check(not Export.valid_app_id("12345678</string>"), "Markup is refused")
	check(Export.libraries_for("12ab34", false).is_empty() and Export.resource_xml_for("12ab34") == "", "An invalid id adds nothing (the export warns and the pipeline asserts)")

func test_resource_xml() -> void:
	var xml := Export.resource_xml_for("123456789012")
	check(xml.contains('<string name="syntaxcircus_games_app_id" translatable="false">123456789012</string>'), "The resource holds the id, untranslatable")
	check(xml.begins_with("<?xml") and xml.contains("<resources>"), "It is a resources file")
