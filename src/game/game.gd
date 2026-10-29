class_name Game
extends Node3D

const MAX_STEPS_PER_FRAME := 4
const EPS := 1e-6

@onready var arena_view: ArenaView = $ArenaView
@onready var actors_view: ActorsView = $ActorsView
@onready var camera_rig: CameraRig = $CameraRig
@onready var input_controller: InputController = $InputController
@onready var hud: Hud = get_node_or_null("Hud")

var match_state: MatchState
var _brains: Dictionary = {} # id -> BotBrain
var _acc := 0.0
var _seen_world: World = null

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if hud:
		input_controller.bomb_area = hud.bomb_button
		input_controller.joystick = hud.joystick
		input_controller.action_area = hud.action_button
	match_state = MatchState.new(Session.config, rng)
	if hud:
		camera_rig.side_inset = Hud.column_inset(match_state.players.size())
	for mp in match_state.players:
		if mp.is_bot:
			_brains[mp.id] = BotBrain.new(rng)
	_refresh_world()
	_sync_views()

func _refresh_world() -> void:
	var world := match_state.world
	if world == _seen_world:
		return
	_seen_world = world
	arena_view.build(world.arena)
	camera_rig.frame(world.arena)
	actors_view.reset()

func _sync_views() -> void:
	var world := match_state.world
	arena_view.sync(world)
	actors_view.sync(world, match_state)
	if hud:
		hud.sync(match_state)

func _process(delta: float) -> void:
	_acc += delta
	var steps := 0
	while _acc >= SimConfig.DT - EPS and steps < MAX_STEPS_PER_FRAME:
		_acc -= SimConfig.DT
		steps += 1
		_step_once()
	if steps == MAX_STEPS_PER_FRAME:
		_acc = minf(_acc, SimConfig.DT) # drop the backlog after a long hitch
	if steps > 0:
		_refresh_world()
		_sync_views()
	actors_view.render(clampf(_acc / SimConfig.DT, 0.0, 1.0))

func _step_once() -> void:
	var world := match_state.world
	var intents: Dictionary = {}
	for id: int in world.players:
		if _brains.has(id):
			intents[id] = _brains[id].decide(world, id)
		elif id == 0:
			intents[id] = input_controller.consume_intent(world.players[id], camera_rig)
	match_state.step(intents)
