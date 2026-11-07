class_name Game
extends Node3D

const MAX_STEPS_PER_FRAME := 4
const EPS := 1e-6

@onready var arena_view: ArenaView = $ArenaView
@onready var actors_view: ActorsView = $ActorsView
@onready var camera_rig: CameraRig = $CameraRig
@onready var input_controller: InputController = $InputController
@onready var hud: Hud = get_node_or_null("Hud")

var match_state: MatchState # online: the mirror of the server's, null until the first snapshot
var _brains: Dictionary = {} # id -> BotBrain
var _acc := 0.0
var _seen_world: World = null
var _net: Node = null # online only
var _snapshots: SnapshotQueue = null # online only

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if hud:
		input_controller.bomb_area = hud.bomb_button
		input_controller.joystick = hud.joystick
		input_controller.action_area = hud.action_button
		input_controller.detonate_area = hud.detonate_button
	# The autoloads are reached through the tree: scripts run by the test harness cannot name them.
	var net := get_node_or_null(^"/root/Net")
	if net != null and net.is_online():
		_net = net
		_snapshots = SnapshotQueue.new()
		net.snapshot_received.connect(_on_snapshot) # a node: disconnected when the scene is freed
		return # nothing to show until the first snapshot
	match_state = MatchState.new(_session().config, rng)
	for mp in match_state.players:
		if mp.is_bot:
			_brains[mp.id] = BotBrain.new(rng)
	_refresh_world()
	_sync_views()

func _session() -> Node:
	return get_node(^"/root/Session")

func _refresh_world() -> void:
	var world := match_state.world
	if world == _seen_world:
		return
	_seen_world = world
	arena_view.build(world.arena)
	camera_rig.frame(world.arena)
	actors_view.reset()

# dt: the sim time the views move on by, one tick in solo, a snapshot interval online.
func _sync_views(dt: float = SimConfig.DT) -> void:
	var world := match_state.world
	arena_view.sync(world)
	actors_view.sync(world, match_state, dt)
	if hud:
		hud.sync(match_state)

func _process(delta: float) -> void:
	if _net != null:
		_process_online(delta)
		return
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

# Online: the server simulates. Its snapshots are played back through the queue and the local
# player's intent is sent once per sim tick of local time.
func _process_online(delta: float) -> void:
	var data: Variant = _snapshots.advance(delta)
	if data != null:
		match_state = SimCodec.apply_match(data, match_state, _net.config)
		_refresh_world()
		_sync_views(SnapshotQueue.INTERVAL)
	actors_view.render(_snapshots.alpha())
	_acc += delta
	var steps := 0
	while _acc >= SimConfig.DT - EPS and steps < MAX_STEPS_PER_FRAME:
		_acc -= SimConfig.DT
		steps += 1
		_send_intent()
	if steps == MAX_STEPS_PER_FRAME:
		_acc = minf(_acc, SimConfig.DT)

func _on_snapshot(data: Dictionary) -> void:
	_snapshots.push(data)

# Nothing to send before the first snapshot, or while watching (not in this round): the presses
# made meanwhile are dropped so they do not fire later.
func _send_intent() -> void:
	var me: PlayerState = null
	if match_state != null:
		me = match_state.world.players.get(_session().local_id)
	if me == null:
		input_controller.clear_presses()
		return
	_net.send_intent(input_controller.consume_intent(me, camera_rig))
