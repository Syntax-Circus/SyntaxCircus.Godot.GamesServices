@tool
extends EditorPlugin
## Registers the export plugin. The adapters are plain scripts the game preloads; nothing else is added to the editor.
const ExportPlugin = preload("res://addons/syntaxcircus_games/export_plugin.gd")

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
