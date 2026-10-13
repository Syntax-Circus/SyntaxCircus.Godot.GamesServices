@tool
extends EditorExportPlugin
## Adds the Play Games Services plugin to an Android export, only when the preset names a Play Games application id.
## With no id the export is untouched (no AAR, no SDK, no meta-data), so a build without a games project has no games service and the
## game's adapter reports unavailable. The decisions are static functions so they are unit-tested without an editor.
##
## Preset option: syntaxcircus_games/play_games_app_id  (the numeric Play Games Services project id from Play Console)
const PLUGIN_NAME := "SyntaxCircusGames"
const OPTION_APP_ID := "syntaxcircus_games/play_games_app_id"
const GAMES_DEPENDENCY := "com.google.android.gms:play-services-games-v2:22.1.0"
const RESOURCE_NAME := "syntaxcircus_games_app_id"
const RESOURCE_FILE := "syntaxcircus_games.xml"

## Play Games project ids are numeric. Empty is valid and means "no games service in this build".
static func valid_app_id(app_id: String) -> bool:
	var id := app_id.strip_edges()
	if id.is_empty():
		return true
	if id.length() < 6 or id.length() > 20:
		return false
	for character in id:
		if character < "0" or character > "9":
			return false
	return true

## The id that will be used, or "" when there is none or it is not valid.
static func usable_app_id(app_id: String) -> String:
	var id := app_id.strip_edges()
	return id if not id.is_empty() and valid_app_id(id) else ""

static func libraries_for(app_id: String, debug: bool) -> PackedStringArray:
	if usable_app_id(app_id).is_empty():
		return PackedStringArray()
	var flavor := "debug" if debug else "release"
	return PackedStringArray(["syntaxcircus_games/bin/%s/SyntaxCircusGames-%s.aar" % [flavor, flavor]])

static func dependencies_for(app_id: String) -> PackedStringArray:
	if usable_app_id(app_id).is_empty():
		return PackedStringArray()
	return PackedStringArray([GAMES_DEPENDENCY])

static func manifest_contents_for(app_id: String) -> String:
	if usable_app_id(app_id).is_empty():
		return ""
	return '<meta-data android:name="com.google.android.gms.games.APP_ID" android:value="@string/%s" />' % RESOURCE_NAME

static func resource_xml_for(app_id: String) -> String:
	var id := usable_app_id(app_id)
	if id.is_empty():
		return ""
	return '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="%s" translatable="false">%s</string>\n</resources>\n' % [RESOURCE_NAME, id]

func _get_name() -> String:
	return PLUGIN_NAME

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	if not (platform is EditorExportPlatformAndroid):
		return []
	return [{"option": {"name": OPTION_APP_ID, "type": TYPE_STRING}, "default_value": ""}]

func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
	if platform is EditorExportPlatformAndroid and option == OPTION_APP_ID:
		var id := String(get_option(OPTION_APP_ID))
		if not valid_app_id(id):
			return "The Play Games project id must be numeric (6 to 20 digits). With an invalid id no games plugin is added to the build."
	return ""

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return libraries_for(String(get_option(OPTION_APP_ID)), debug)

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return dependencies_for(String(get_option(OPTION_APP_ID)))

func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
	return manifest_contents_for(String(get_option(OPTION_APP_ID)))

## Writes (or removes) the string resource in the generated Gradle project. A file of its own, so the game's strings.xml is never touched.
func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	var directory := ProjectSettings.globalize_path("res://android/build/res/values")
	var file_path := directory.path_join(RESOURCE_FILE)
	var xml := resource_xml_for(String(get_option(OPTION_APP_ID)))
	if xml.is_empty():
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)
		return
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("SyntaxCircusGames: cannot write %s (install the Android build template first)" % file_path)
		return
	file.store_string(xml)
	file.close()
