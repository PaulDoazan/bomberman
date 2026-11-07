class_name OnlineStore
extends RefCounted
# What the browser remembers between visits: the nickname, and the token of each game joined
# (so a reload or a lost connection rejoins as the same player).

static var path := "user://online.cfg"

static func _load() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(path) # a missing file just means nothing saved yet
	return cf

static func _save(section: String, key: String, value: String) -> void:
	var cf := _load()
	cf.set_value(section, key, value)
	cf.save(path)

static func load_nickname() -> String:
	return str(_load().get_value("player", "nickname", ""))

static func save_nickname(n: String) -> void:
	_save("player", "nickname", n)

static func token_for(code: String) -> String:
	return str(_load().get_value("tokens", code, ""))

static func save_token(code: String, token: String) -> void:
	_save("tokens", code, token)

# After Quitter: the game is not rejoined automatically any more.
static func forget_token(code: String) -> void:
	var cf := _load()
	if cf.has_section_key("tokens", code):
		cf.erase_section_key("tokens", code)
		cf.save(path)
