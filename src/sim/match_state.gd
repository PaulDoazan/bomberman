class_name MatchState
extends RefCounted

class MatchPlayer:
	var id: int
	var name: String
	var is_bot: bool
	var color: Color
	var wins := 0
	var team := -1 # -1: no team (solo)
	var tag := "" # 3 letters shown over the character, empty in solo

enum Phase { PLAYING, ROUND_OVER }

var cfg: SimConfig
var players: Array[MatchPlayer] = []
var world: World
var phase := Phase.PLAYING
var phase_timer := 0.0
var round_number := 0
var last_winners: Array[int] = []
var rng: RandomNumberGenerator
var team_wins: Dictionary = {} # team id -> rounds won
var hold_next_round := false # the server decides when the next round starts

func _init(p_cfg: SimConfig, p_rng: RandomNumberGenerator, roster: Variant = null, auto_start := true) -> void:
	cfg = p_cfg
	rng = p_rng
	if roster == null:
		for id in cfg.player_count():
			var mp := MatchPlayer.new()
			mp.id = id
			mp.is_bot = id > 0
			mp.name = "Bot %d" % id if mp.is_bot else "Toi"
			mp.color = SimConfig.PLAYER_COLORS[id]
			players.append(mp)
	else:
		players.assign(roster)
	if auto_start:
		start_round()

static func tag_of(p_name: String) -> String:
	return p_name.strip_edges().left(3).to_upper()

# Replaces the roster, keeping the wins of players already present.
func sync_roster(roster: Array[MatchPlayer]) -> void:
	for mp in roster:
		var old := player(mp.id)
		if old != null:
			mp.wins = old.wins
	players = roster

# The players list is read here, so anyone added between two rounds joins the next one.
func start_round() -> void:
	players.sort_custom(func(a: MatchPlayer, b: MatchPlayer) -> bool:
		return a.team < b.team or (a.team == b.team and a.id < b.id))
	var ids: Array[int] = []
	var teams := {}
	var team_sizes: Array[int] = []
	var last_team := -2
	for mp in players:
		ids.append(mp.id)
		if mp.team >= 0:
			teams[mp.id] = mp.team
		if mp.team != last_team:
			team_sizes.append(0)
			last_team = mp.team
		team_sizes[-1] += 1
	# Without any team, spawns stay evenly spread (solo).
	if teams.is_empty():
		team_sizes.clear()
	var arena := MapGen.generate(cfg.grid_size(), players.size(), rng, team_sizes)
	world = World.new(arena, ids, cfg, rng, teams)
	phase = Phase.PLAYING
	round_number += 1

func step(intents: Dictionary) -> void:
	if phase == Phase.PLAYING:
		world.step(intents)
		if world.finished:
			var won_teams := {}
			for id in world.winners:
				player(id).wins += 1
				won_teams[world.team_of(id)] = true
			for t in won_teams:
				team_wins[t] = team_wins.get(t, 0) + 1
			last_winners = world.winners.duplicate()
			phase = Phase.ROUND_OVER
			phase_timer = SimConfig.SCOREBOARD_DURATION
	else:
		phase_timer = maxf(0.0, phase_timer - SimConfig.DT)
		if phase_timer <= 0.0 and not hold_next_round:
			start_round()

func player(id: int) -> MatchPlayer:
	for mp in players:
		if mp.id == id:
			return mp
	return null
