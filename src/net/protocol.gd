class_name Protocol
extends RefCounted
# Wire format: 1 byte of message type, then the body as var_to_bytes, DEFLATE-compressed.

const VERSION := 2 # bump when the messages change: it is part of SimCodec.schema_hash()

enum Msg {
	CREATE = 1, JOIN = 2, CREATE_TEAM = 3, JOIN_TEAM = 4, LEAVE_TEAM = 5,
	SETTINGS = 6, START = 7, TO_LOBBY = 8, INTENT = 9, PING = 10, LEAVE = 11,
	WELCOME = 20, LOBBY = 21, ERROR = 22, SNAPSHOT = 23, PONG = 24,
}

const ERR_UNKNOWN_CODE := "unknown_code"
const ERR_FULL := "full"
const ERR_NAME_TAKEN := "name_taken"
const ERR_BAD_NAME := "bad_name"
const ERR_TEAMS_FULL := "teams_full"
const ERR_HOST_ONLY := "host_only"
const ERR_CANNOT_START := "cannot_start"
const ERR_NOT_NOW := "not_now"
const ERR_VERSION := "version"
const SNAPSHOT_EVERY := 1 # sim ticks between two snapshots: 30 a second
const ERR_SERVER_FULL := "server_full"

const ERROR_LABELS := {
	ERR_UNKNOWN_CODE: "Code inconnu",
	ERR_FULL: "Partie pleine (12 joueurs)",
	ERR_NAME_TAKEN: "Ce pseudo est déjà pris",
	ERR_BAD_NAME: "Nom invalide",
	ERR_TEAMS_FULL: "Il y a déjà 4 équipes",
	ERR_HOST_ONLY: "Seul l'host peut faire ça",
	ERR_CANNOT_START: "Il faut au moins 2 joueurs, tous dans une équipe",
	ERR_NOT_NOW: "Pas pendant la partie",
	ERR_VERSION: "Nouvelle version du jeu : recharge la page",
	ERR_SERVER_FULL: "Serveur plein, réessaie plus tard",
}

const MAX_STRUGGLE := 10.0
const MAX_TARGET := 1000.0 # cells, either axis
const MAX_PACKET_BYTES := 32768 # compressed input accepted by decode
const MAX_BODY_BYTES := 65536 # inflated body accepted by decode

static func encode(type: int, body: Variant) -> PackedByteArray:
	var out := PackedByteArray([type])
	out.append_array(var_to_bytes(body).compress(FileAccess.COMPRESSION_DEFLATE))
	return out

# Returns [type, body], or [] when the message is invalid: bad compression,
# unknown type or an object inside. Never instantiates objects.
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.size() < 3 or bytes.size() > MAX_PACKET_BYTES or not Msg.values().has(bytes[0]):
		return []
	# Cheap zlib header check (RFC 1950) so garbage does not make the engine log errors.
	if (bytes[1] & 0x0F) != 8 or (bytes[1] * 256 + bytes[2]) % 31 != 0:
		return []
	var raw := _inflate(bytes.slice(1))
	if raw.is_empty():
		return []
	# A top-level object is refused before decoding (the engine would log an error).
	if raw.size() < 4 or raw[0] == TYPE_OBJECT or raw[0] >= TYPE_MAX:
		return []
	# Objects nested in an array or dictionary decode to null, never to an instance.
	var body: Variant = bytes_to_var(raw)
	if body == null and raw != var_to_bytes(null):
		return [] # malformed Variant
	if _has_object(body):
		return []
	return [bytes[0], body]

# Inflates a zlib stream, giving up (empty result) past MAX_BODY_BYTES.
static func _inflate(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var gz := StreamPeerGZIP.new()
	if gz.start_decompression(true) != OK:
		return out
	var pos := 0
	while pos < data.size():
		var fed: Array = gz.put_partial_data(data.slice(pos, pos + 1024))
		if fed[0] != OK:
			return PackedByteArray()
		pos += int(fed[1])
		while gz.get_available_bytes() > 0:
			var chunk: Array = gz.get_partial_data(mini(gz.get_available_bytes(), 4096))
			if chunk[0] != OK:
				return PackedByteArray()
			out.append_array(chunk[1])
			if out.size() > MAX_BODY_BYTES:
				return PackedByteArray()
		if fed[1] == 0 and gz.get_available_bytes() == 0:
			break
	return out

static func _has_object(v: Variant) -> bool:
	if typeof(v) == TYPE_OBJECT:
		return true
	if v is Array:
		for e: Variant in v:
			if _has_object(e):
				return true
	elif v is Dictionary:
		for k: Variant in v:
			if _has_object(k) or _has_object(v[k]):
				return true
	return false

static func intent_to_array(i: PlayerIntent) -> Array:
	return [i.moving, i.target.x, i.target.y, i.place_bomb, i.action, i.action_held, i.detonate, i.struggle]

static func intent_from_array(a: Variant) -> PlayerIntent:
	if not (a is Array) or (a as Array).size() != 8:
		return null
	var arr: Array = a
	for idx in [0, 3, 4, 5, 6]:
		if typeof(arr[idx]) != TYPE_BOOL:
			return null
	for idx in [1, 2, 7]:
		if typeof(arr[idx]) != TYPE_FLOAT and typeof(arr[idx]) != TYPE_INT:
			return null
		if not is_finite(float(arr[idx])):
			return null
	if absf(float(arr[1])) > MAX_TARGET or absf(float(arr[2])) > MAX_TARGET:
		return null
	var i := PlayerIntent.new()
	i.moving = arr[0]
	i.target = Vector2(float(arr[1]), float(arr[2]))
	i.place_bomb = arr[3]
	i.action = arr[4]
	i.action_held = arr[5]
	i.detonate = arr[6]
	i.struggle = clampf(float(arr[7]), 0.0, MAX_STRUGGLE)
	return i
