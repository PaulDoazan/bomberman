class_name SimConfig
extends RefCounted

const TICK_RATE := 30
const DT := 1.0 / 30.0

const MAP_SIZES := {
	"petite": Vector2i(15, 13),
	"normale": Vector2i(19, 15),
	"grande": Vector2i(25, 19),
	"immense": Vector2i(31, 23),
}
const MAP_SIZE_LABELS := {
	"petite": "Petite",
	"normale": "Normale",
	"grande": "Grande",
	"immense": "Immense",
}

const PLAYER_SPEED := 3.2
const GHOST_SPEED := 3.6
const PLAYER_HALF := 0.35
const CORNER_ASSIST := 0.35
const STOP_DISTANCE := 0.1

const MAX_BOMBS := 2
const BOMB_RADIUS := 2.0
const BOMB_BODY_RADIUS := 0.32 # a bomb's round body, for collisions with players
const PLAYER_BODY_RADIUS := 0.24 # the character's legs and feet, what a bomb on the ground touches
const FUSE := 2.5
const EXPLOSION_DURATION := 0.5

const RESPAWN_DELAY := 2.0
const INVULNERABLE_TIME := 2.0

const WATER_STEP_INTERVAL := 20.0
const WATER_WARNING := 3.0
const WATER_STEPS := [-1, 1, 3, 4]
const WATER_START_H2 := -3

const POSSESS_DURATION := 5.0
const POSSESS_COOLDOWN := 10.0
const POSSESS_REACH := 0.6

const THROW_DISTANCE := 3
const THROW_FLIGHT := 0.5
const STUN_TIME := 1.5 # after landing from a throw
const BOMB_HIT_STUN_TIME := 3.0 # hit by a thrown or rolling bomb
const STRUGGLE_TIME := 0.15 # seconds of stun removed per shake
const CARRY_ESCAPE := 3.0

const KICK_PUSH_TIME := 0.2 # seconds pushing against a bomb before kicking it
const KICK_SPEED := 6.0 # cells per second

const BLOCK_DENSITY := 0.15
const SPAWN_CLEARANCE := 2
const SCOREBOARD_DURATION := 4.0

const PLAYER_COLORS: Array[Color] = [
	Color("e6194b"), # rouge
	Color("3cb44b"), # vert
	Color("4363d8"), # bleu
	Color("ffe119"), # jaune
	Color("f58231"), # orange
	Color("911eb4"), # violet
	Color("42d4f4"), # cyan
	Color("f032e6"), # magenta
	Color("ffffff"), # blanc
	Color("2b2b2b"), # noir
]

var bot_count := 3 # 1 à 9
var map_size := "normale"
var round_time := 120.0 # 30 à 300
var lives := 3 # 1 à 9

func grid_size() -> Vector2i:
	return MAP_SIZES[map_size]

func player_count() -> int:
	return bot_count + 1
