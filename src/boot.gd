class_name Boot
extends Node
# The main scene: a dedicated server build (or --server) runs the game server, anything else the game.

const SERVER_SCENE := "res://src/server/server.tscn"
const CLIENT_SCENE := "res://src/ui/home_screen.tscn"

static func is_server() -> bool:
	return OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--server")

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(SERVER_SCENE if is_server() else CLIENT_SCENE)
