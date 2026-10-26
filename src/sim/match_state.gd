class_name MatchState
extends RefCounted

class MatchPlayer:
	var id: int
	var name: String
	var is_bot: bool
	var color: Color
	var wins := 0

enum Phase { PLAYING, ROUND_OVER }

var cfg: SimConfig
var players: Array[MatchPlayer] = []
var world: World
var phase := Phase.PLAYING
var phase_timer := 0.0
var round_number := 0
var last_winners: Array[int] = []
var rng: RandomNumberGenerator

func _init(p_cfg: SimConfig, p_rng: RandomNumberGenerator) -> void:
	cfg = p_cfg
	rng = p_rng
	for id in cfg.player_count():
		var mp := MatchPlayer.new()
		mp.id = id
		mp.is_bot = id > 0
		mp.name = "Bot %d" % id if mp.is_bot else "Toi"
		mp.color = SimConfig.PLAYER_COLORS[id]
		players.append(mp)
	start_round()

# The players list is read here, so anyone added between two rounds joins the next one.
func start_round() -> void:
	var ids: Array[int] = []
	for mp in players:
		ids.append(mp.id)
	var arena := MapGen.generate(cfg.grid_size(), players.size(), rng)
	world = World.new(arena, ids, cfg, rng)
	phase = Phase.PLAYING
	round_number += 1

func step(intents: Dictionary) -> void:
	if phase == Phase.PLAYING:
		world.step(intents)
		if world.finished:
			for id in world.winners:
				player(id).wins += 1
			last_winners = world.winners.duplicate()
			phase = Phase.ROUND_OVER
			phase_timer = SimConfig.SCOREBOARD_DURATION
	else:
		phase_timer -= SimConfig.DT
		if phase_timer <= 0.0:
			start_round()

func player(id: int) -> MatchPlayer:
	for mp in players:
		if mp.id == id:
			return mp
	return null
