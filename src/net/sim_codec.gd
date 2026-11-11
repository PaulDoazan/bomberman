class_name SimCodec
extends RefCounted

# Turns a MatchState into plain data (Arrays, Dictionaries, numbers) for var_to_bytes, and back
# into a client mirror. Each object is an Array of its values in keys_of() order; the World's
# simple fields likewise, without WORLD_EXCLUDED. A mirror of the same round is updated in place
# (same World, Arena and objects) because the views key their nodes by instance.

# World fields sent separately (arena, objects), not needed (cfg, rng, events) or secret (hidden).
const WORLD_EXCLUDED := ["arena", "cfg", "rng", "players", "bombs", "explosions", "flying", "drops", "events", "hidden"]
const ARENA_KEYS := ["w", "h", "h2", "tiles", "stair_axis", "goal"]

static var _keys_cache: Dictionary = {} # Script -> Array[String]

# Script variables sorted by name, without the private ones (leading underscore).
static func keys_of(script: Script) -> Array[String]:
	if _keys_cache.has(script):
		return _keys_cache[script]
	var out: Array[String] = []
	for prop: Dictionary in script.get_script_property_list():
		var key: String = prop.name
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not key.begins_with("_"):
			out.append(key)
	out.sort()
	_keys_cache[script] = out
	return out

static func _world_keys() -> Array[String]:
	var out: Array[String] = []
	for key in keys_of(World):
		if not key in WORLD_EXCLUDED:
			out.append(key)
	return out

# Changes as soon as a field of the simulation is added, removed or renamed, or Protocol.VERSION.
static func schema_hash() -> int:
	var all: Array[String] = []
	for script: Script in [PlayerState, BombState, Explosion, FlyingObject, Drop, MatchState.MatchPlayer]:
		all.append_array(keys_of(script))
	all.append_array(_world_keys())
	all.append_array(ARENA_KEYS)
	return hash([Protocol.VERSION, all])

# Containers are copied so a snapshot never shares state with what it was taken from.
static func _copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
		return v.duplicate()
	return v

static func _pack(obj: Object, keys: Array[String]) -> Array:
	var out := []
	for key in keys:
		out.append(_copy(obj.get(key)))
	return out

# Typed arrays are restored with assign(), so they keep their type.
static func _unpack(obj: Object, keys: Array[String], values: Array) -> void:
	for i in keys.size():
		var cur: Variant = obj.get(keys[i])
		if cur is Array and (cur as Array).is_typed():
			(cur as Array).assign(values[i])
		else:
			obj.set(keys[i], _copy(values[i]))

# An object's state as plain values, and back: a copy kept aside (Prediction).
static func values_of(obj: Object, script: Script) -> Array:
	return _pack(obj, keys_of(script))

static func set_values(obj: Object, script: Script, values: Array) -> void:
	_unpack(obj, keys_of(script), values)

static func _pack_all(objects: Array, script: Script) -> Array:
	var keys := keys_of(script)
	var out := []
	for obj: Object in objects:
		out.append(_pack(obj, keys))
	return out

static func encode_match(m: MatchState) -> Dictionary:
	var w := m.world
	var a := w.arena
	return {
		"round": m.round_number,
		"phase": m.phase,
		"phase_timer": m.phase_timer,
		"last_winners": _copy(m.last_winners),
		"team_wins": _copy(m.team_wins),
		"hold": m.hold_next_round,
		"roster": _pack_all(m.players, MatchState.MatchPlayer),
		"arena": [a.width, a.height, _copy(a.h2), _copy(a.tiles), _copy(a.stair_axis), a.goal],
		"world": _pack(w, _world_keys()),
		"players": _pack_all(w.players.values(), PlayerState),
		"bombs": _pack_all(w.bombs.values(), BombState),
		"explosions": _pack_all(w.explosions, Explosion),
		"flying": _pack_all(w.flying, FlyingObject),
		"drops": _pack_all(w.drops, Drop),
	}

# Updates mirror from data and returns it, or returns a new MatchState when there is no mirror
# yet or the round changed (new World and Arena: the views rebuild the map).
static func apply_match(data: Dictionary, mirror: MatchState, cfg: SimConfig) -> MatchState:
	var fresh: bool = mirror == null or int(data.round) != mirror.round_number
	var roster := _apply_roster(data.roster, null if fresh else mirror)
	if fresh:
		var rng := RandomNumberGenerator.new()
		mirror = MatchState.new(cfg, rng, roster, false)
		var arena := Arena.create(data.arena[0], data.arena[1])
		mirror.world = World.new(arena, [] as Array[int], cfg, rng)
		mirror.world.hidden.clear() # hide_in_blocks drew some: the mirror knows of none
	else:
		mirror.players.assign(roster)
	mirror.round_number = data.round
	mirror.phase = data.phase
	mirror.phase_timer = data.phase_timer
	mirror.last_winners.assign(data.last_winners)
	mirror.team_wins = _copy(data.team_wins)
	mirror.hold_next_round = bool(data.get("hold", false))
	var w := mirror.world
	_apply_arena(w.arena, data.arena, fresh)
	_unpack(w, _world_keys(), data.world)
	w.players = _apply_by(data.players, w.players, PlayerState, "id")
	w.bombs = _apply_by(data.bombs, w.bombs, BombState, "id")
	w.explosions = _apply_by(data.explosions, _index(w.explosions), Explosion, "uid").values()
	w.flying = _apply_by(data.flying, _index(w.flying), FlyingObject, "uid").values()
	w.drops = _apply_by(data.get("drops", []), _index(w.drops), Drop, "uid").values()
	return mirror

static func _apply_roster(rows: Array, mirror: MatchState) -> Array[MatchState.MatchPlayer]:
	var keys := keys_of(MatchState.MatchPlayer)
	var id_at := keys.find("id")
	var out: Array[MatchState.MatchPlayer] = []
	for row: Array in rows:
		var mp: MatchState.MatchPlayer = mirror.player(row[id_at]) if mirror != null else null
		if mp == null:
			mp = MatchState.MatchPlayer.new()
		_unpack(mp, keys, row)
		out.append(mp)
	return out

# Within a round only the tiles change (blocks destroyed or thrown).
static func _apply_arena(a: Arena, row: Array, fresh: bool) -> void:
	a.tiles = _copy(row[3])
	if fresh:
		a.h2 = _copy(row[2])
		a.stair_axis = _copy(row[4])
		a.goal = row[5]

static func _index(objects: Array) -> Dictionary:
	var out := {}
	for obj: Object in objects:
		out[obj.get("uid")] = obj
	return out

# Objects of the snapshot, in its order, keyed by `key`: the instance already in `old` when there
# is one, a new one otherwise. Objects missing from the snapshot are dropped.
static func _apply_by(rows: Array, old: Dictionary, script: Script, key: String) -> Dictionary:
	var keys := keys_of(script)
	var key_at := keys.find(key)
	var out := {}
	for row: Array in rows:
		var obj: Object = old.get(row[key_at], null)
		if obj == null:
			obj = script.new()
		_unpack(obj, keys, row)
		out[row[key_at]] = obj
	return out

static func encode_config(cfg: SimConfig) -> Dictionary:
	return {
		"bot_count": cfg.bot_count,
		"map_size": cfg.map_size,
		"round_time": cfg.round_time,
		"lives": cfg.lives,
		"items": cfg.items.duplicate(),
	}

# Settings from a client: anything missing, mistyped or out of range falls back or is clamped
# to what the settings screen allows.
static func decode_config(d: Dictionary) -> SimConfig:
	var cfg := SimConfig.new()
	cfg.bot_count = clampi(_int_or(d.get("bot_count"), cfg.bot_count), 1, 9)
	cfg.round_time = clampf(_float_or(d.get("round_time"), cfg.round_time), 30.0, 300.0)
	cfg.lives = clampi(_int_or(d.get("lives"), cfg.lives), 1, 9)
	var size: Variant = d.get("map_size")
	if size is String and SimConfig.MAP_SIZES.has(size):
		cfg.map_size = size
	var items: Variant = d.get("items")
	if items is Dictionary:
		for item: Variant in items:
			if item is int and item in SimConfig.Item.values() and items[item] is bool:
				cfg.items[item] = items[item]
	return cfg

static func _int_or(v: Variant, fallback: int) -> int:
	if v is int or v is float:
		return int(v)
	return fallback

static func _float_or(v: Variant, fallback: float) -> float:
	if v is int or (v is float and is_finite(v)):
		return float(v)
	return fallback
