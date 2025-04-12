class_name PTConfig
extends RefCounted

## Static class to hold paths and modify configs

const RENDER_CONFIG_PATH := "res://addons/path_tracer_engine/configs/"
const EDITOR_RENDER_CONFIG := RENDER_CONFIG_PATH + "editor_render_settings.tscn"
const RUNTIME_RENDER_CONFIG := RENDER_CONFIG_PATH + "runtime_render_settings.tscn"

# var CONFIG_DIR := DirAccess.new()


static func editor_render_config_exist() -> bool:
	return FileAccess.file_exists(EDITOR_RENDER_CONFIG)


static func runtime_render_config_exist() -> bool:
	return FileAccess.file_exists(RUNTIME_RENDER_CONFIG)


static func save_editor_render_config(window : PTRenderWindow) -> void:
	if !DirAccess.dir_exists_absolute(RENDER_CONFIG_PATH):
		DirAccess.make_dir_absolute(RENDER_CONFIG_PATH)

	if window.name.is_empty():
		window.name = "EditorSettings"
	var editor_scene := PackedScene.new()
	editor_scene.pack(window)
	ResourceSaver.save(editor_scene, EDITOR_RENDER_CONFIG)


static func save_runtime_render_config(window : PTRenderWindow) -> void:
	if !DirAccess.dir_exists_absolute(RENDER_CONFIG_PATH):
		DirAccess.make_dir_absolute(RENDER_CONFIG_PATH)

	if window.name.is_empty():
		window.name = "RuntimeSettings"
	var runtime_scene := PackedScene.new()
	runtime_scene.pack(window)
	ResourceSaver.save(runtime_scene, RUNTIME_RENDER_CONFIG)
