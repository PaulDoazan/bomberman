class_name RoomCodes
extends RefCounted
# Game codes: 6 characters, no look-alikes (0/O, 1/I).

const ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const LENGTH := 6

# A random code that is not in taken (a Dictionary used as a set).
static func generate(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	while true:
		var code := ""
		for i in LENGTH:
			code += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
		if not taken.has(code):
			return code
	return ""

# What a player typed or pasted ("#k7p2 qx/") as a clean code, or "" when it cannot be one.
static func normalize(s: String) -> String:
	var out := s.replace("#", "").replace("/", "").replace(" ", "").to_upper()
	if out.length() != LENGTH:
		return ""
	for ch in out:
		if not ALPHABET.contains(ch):
			return ""
	return out
