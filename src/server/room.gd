class_name Room
extends RefCounted
# A game room on the server: who is in it, the teams, the settings and, once started, the match.
# This file holds the lobby rules; every action returns "" when accepted, else a Protocol.ERR_*.

const MAX_PLAYERS := 12
const MAX_TEAMS := 4
const NAME_MAX := 12
const TEAM_NAME_MAX := 16
const GRACE_IN_ROUND := 10.0 # seconds a disconnected player keeps their character
const FORGET_AFTER := 180.0 # seconds before a disconnected player is dropped
const EMPTY_ROOM_TTL := 60.0 # seconds a room without anyone connected survives
const NO_TEAM_COLOR := Color(0.6, 0.6, 0.6)

enum Phase { LOBBY, PLAYING }

class RoomPlayer:
	var id: int
	var name: String
	var token: String
	var team := -1
	var connected := true
	var disconnected_at := 0.0
	var forfeited := false

class Team:
	var id: int
	var name: String
	var color_index: int

var code: String
var phase := Phase.LOBBY
var host_id := -1
var players: Dictionary = {} # id -> RoomPlayer, connected or not
var teams: Dictionary = {} # id -> Team
var config := SimConfig.new()
var match_state: MatchState

var _rng: RandomNumberGenerator
var _next_player_id := 1
var _next_team_id := 0

func _init(p_code: String, p_rng: RandomNumberGenerator) -> void:
	code = p_code
	_rng = p_rng

# Returns {"id", "token"}, or {"error"}. A known token is a reconnection, allowed in any phase.
func join(p_name: String, token: String, now: float) -> Dictionary:
	if token != "":
		for p: RoomPlayer in players.values():
			if p.token == token:
				p.connected = true
				p.disconnected_at = 0.0
				_ensure_host()
				return {"id": p.id, "token": p.token}
	var clean := p_name.strip_edges()
	if not _valid_name(clean, NAME_MAX):
		return {"error": Protocol.ERR_BAD_NAME}
	if players.size() >= MAX_PLAYERS:
		return {"error": Protocol.ERR_FULL}
	var key := clean.to_lower()
	for p: RoomPlayer in players.values():
		if p.name.strip_edges().to_lower() == key:
			return {"error": Protocol.ERR_NAME_TAKEN}
	var rp := RoomPlayer.new()
	rp.id = _next_player_id
	_next_player_id += 1
	rp.name = clean
	rp.token = _new_token()
	players[rp.id] = rp
	if host_id == -1:
		host_id = rp.id
	_ensure_host()
	return {"id": rp.id, "token": rp.token}

func disconnect_player(id: int, now: float) -> void:
	var p: RoomPlayer = players.get(id)
	if p == null or not p.connected:
		return
	p.connected = false
	p.disconnected_at = now
	if id == host_id:
		_elect_host()

func create_team(id: int, team_name: String) -> String:
	var p: RoomPlayer = players.get(id)
	if p == null or _is_locked(p):
		return Protocol.ERR_NOT_NOW
	var clean := team_name.strip_edges()
	if not _valid_name(clean, TEAM_NAME_MAX):
		return Protocol.ERR_BAD_NAME
	var count := teams.size()
	if p.team != -1 and _team_size(p.team) == 1:
		count -= 1 # the team the player is about to leave disappears
	if count >= MAX_TEAMS:
		return Protocol.ERR_TEAMS_FULL
	_leave(p)
	var used: Array[int] = []
	for t: Team in teams.values():
		used.append(t.color_index)
	var t := Team.new()
	t.id = _next_team_id
	_next_team_id += 1
	t.name = clean
	t.color_index = TeamColors.free_index(used)
	teams[t.id] = t
	p.team = t.id
	return ""

func join_team(id: int, team_id: int) -> String:
	var p: RoomPlayer = players.get(id)
	if p == null or _is_locked(p) or not teams.has(team_id):
		return Protocol.ERR_NOT_NOW
	if p.team == team_id:
		return ""
	_leave(p)
	p.team = team_id
	return ""

func leave_team(id: int) -> String:
	var p: RoomPlayer = players.get(id)
	if p == null or _is_locked(p):
		return Protocol.ERR_NOT_NOW
	_leave(p)
	return ""

func set_config(id: int, cfg: SimConfig) -> String:
	var err := _host_check(id)
	if err != "":
		return err
	if phase != Phase.LOBBY:
		return Protocol.ERR_NOT_NOW
	# Round-trip through the codec so the room only ever holds values in range.
	config = SimCodec.decode_config(SimCodec.encode_config(cfg))
	return ""

func start(id: int) -> String:
	var err := _host_check(id)
	if err != "":
		return err
	if phase != Phase.LOBBY:
		return Protocol.ERR_NOT_NOW
	if not can_start():
		return Protocol.ERR_CANNOT_START
	var by_team: Dictionary = {} # team id -> player ids, ascending
	var ids: Array = players.keys()
	ids.sort()
	for pid: int in ids:
		var p: RoomPlayer = players[pid]
		if not by_team.has(p.team):
			by_team[p.team] = []
		by_team[p.team].append(pid)
	var roster: Array[MatchState.MatchPlayer] = []
	for pid: int in ids:
		var p: RoomPlayer = players[pid]
		var members: Array = by_team[p.team]
		var mp := MatchState.MatchPlayer.new()
		mp.id = p.id
		mp.name = p.name
		mp.is_bot = false
		mp.team = p.team
		mp.color = TeamColors.tint(teams[p.team].color_index, members.find(pid), members.size())
		mp.tag = MatchState.tag_of(p.name)
		roster.append(mp)
	match_state = MatchState.new(SimCodec.decode_config(SimCodec.encode_config(config)), _rng, roster)
	phase = Phase.PLAYING
	return ""

func back_to_lobby(id: int) -> String:
	var err := _host_check(id)
	if err != "":
		return err
	if phase != Phase.PLAYING:
		return Protocol.ERR_NOT_NOW
	phase = Phase.LOBBY
	match_state = null
	return ""

# At least two teams and everybody in one.
func can_start() -> bool:
	if teams.size() < 2:
		return false
	for p: RoomPlayer in players.values():
		if p.team == -1:
			return false
	return true

func lobby_state() -> Dictionary:
	var team_list := []
	for t: Team in teams.values():
		team_list.append({"id": t.id, "name": t.name, "color_index": t.color_index})
	var player_list := []
	for p: RoomPlayer in players.values():
		player_list.append({
			"id": p.id, "name": p.name, "team": p.team, "connected": p.connected,
			"color": _lobby_color(p),
		})
	return {
		"code": code,
		"host": host_id,
		"phase": "lobby" if phase == Phase.LOBBY else "playing",
		"can_start": can_start(),
		"config": SimCodec.encode_config(config),
		"teams": team_list,
		"players": player_list,
	}

func _lobby_color(p: RoomPlayer) -> Color:
	if p.team == -1:
		return NO_TEAM_COLOR
	var rank := 0
	var count := 0
	for q: RoomPlayer in players.values():
		if q.team == p.team:
			count += 1
			if q.id < p.id:
				rank += 1
	return TeamColors.tint(teams[p.team].color_index, rank, count)

# While a match runs, someone who is in it cannot change team; a newcomer can.
func _is_locked(p: RoomPlayer) -> bool:
	return phase == Phase.PLAYING and match_state != null and match_state.player(p.id) != null

func _host_check(id: int) -> String:
	if not players.has(id):
		return Protocol.ERR_NOT_NOW
	if id != host_id:
		return Protocol.ERR_HOST_ONLY
	return ""

func _team_size(team_id: int) -> int:
	var n := 0
	for p: RoomPlayer in players.values():
		if p.team == team_id:
			n += 1
	return n

# Takes the player out of their team, deleting it when it becomes empty.
func _leave(p: RoomPlayer) -> void:
	var old := p.team
	p.team = -1
	if old != -1 and _team_size(old) == 0:
		teams.erase(old)

# The connected player with the smallest id, if any.
func _elect_host() -> void:
	var best := -1
	for p: RoomPlayer in players.values():
		if p.connected and (best == -1 or p.id < best):
			best = p.id
	if best != -1:
		host_id = best

# Tokens come from the OS entropy source, not from the match rng, so they cannot be predicted.
func _new_token() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()

# A name (already stripped) of 1 to max_len characters, without control characters.
func _valid_name(clean: String, max_len: int) -> bool:
	if clean.is_empty() or clean.length() > max_len:
		return false
	for i in clean.length():
		var c := clean.unicode_at(i)
		if c < 32 or c == 127:
			return false
	return true

# Somebody connected must hold the host role, so the room is never stuck.
func _ensure_host() -> void:
	var h: RoomPlayer = players.get(host_id)
	if h == null or not h.connected:
		_elect_host()
