extends Node
# The dedicated server scene: listens on PORT (or 9080) and polls ServerCore every frame.

const DEFAULT_PORT := 9080

var core := ServerCore.new()

func _ready() -> void:
	Engine.max_fps = 60 # otherwise the headless loop takes a whole CPU
	var port := DEFAULT_PORT
	var env := OS.get_environment("PORT")
	if env.is_valid_int():
		port = env.to_int()
	core.logged.connect(_log)
	var err := core.listen(port)
	if err != OK:
		printerr("Impossible d'écouter sur %d : %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	_log("Serveur à l'écoute sur %d" % port)

func _process(_delta: float) -> void:
	core.poll(Time.get_ticks_msec() / 1000.0)

func _exit_tree() -> void:
	core.stop()

func _log(text: String) -> void:
	print("[%s] %s" % [Time.get_datetime_string_from_system(), text])
