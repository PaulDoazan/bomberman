class_name SimConfig
extends RefCounted

const TICK_RATE := 30
const DT := 1.0 / 30.0

const MAP_SIZES := {
	# About 1.2 times wider than they were, for landscape phone screens (odd widths): the most
	# that still fills the screen height there, right of the HUD column.
	"petite": Vector2i(17, 13),
	"normale": Vector2i(23, 15),
	"grande": Vector2i(31, 19),
	"immense": Vector2i(37, 23),
}
const MAP_SIZE_LABELS := {
	"petite": "Petite",
	"normale": "Normale",
	"grande": "Grande",
	"immense": "Immense",
}

const PLAYER_SPEED := 3.2
const GHOST_SPEED := 3.2 # as fast as the living: the original manual gives ghosts the same moves
const PLAYER_HALF := 0.35
const CORNER_ASSIST := 0.35
const STOP_DISTANCE := 0.1

const MAX_BOMBS := 2 # placed at once, without Bomb items
const BOMB_RADIUS := 2.0 # blast radius of a level 1 bomb
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
const EJECT_DISTANCE := 2.0 # cells a ghost is thrown back when it lets go of its victim
const EJECT_TIME := 0.5

const THROW_DISTANCE := 3
const THROW_FLIGHT := 0.5
const STUN_TIME := 1.5 # after landing from a throw
const BOMB_HIT_STUN_TIME := 3.0 # hit by a thrown or rolling bomb
const KNOCK_DISTANCE := 0.4 # cells a player hit by a bomb is knocked back
const KNOCK_TIME := 0.3 # seconds the knock-back lasts (a small hop in the view)
const STRUGGLE_TIME := 0.15 # seconds of stun removed per shake
const CARRY_ESCAPE := 3.0
const GRAB_REACH := 1.1 # how far ahead a player can grab another

const KICK_PUSH_TIME := 0.2 # seconds pushing against a bomb before kicking it
const KICK_SPEED := 6.0 # cells per second

# Items hidden in destructible blocks, as in Bomberman 64. Each can be turned off in the settings.
enum Item { FIRE, BOMB, POWER, REMOTE, HEART, SKULL, EVIL }
const ITEM_LABELS := {
	Item.FIRE: "Feu",
	Item.BOMB: "Bombe",
	Item.POWER: "Puissance",
	Item.REMOTE: "Télécommande",
	Item.HEART: "Cœur",
	Item.SKULL: "Tête de mort",
	Item.EVIL: "Mal",
}
const ITEM_CHANCE := 0.35 # share of blocks hiding an item (Evil aside)
const ITEM_WEIGHTS := {Item.FIRE: 25, Item.BOMB: 25, Item.POWER: 8, Item.REMOTE: 8, Item.HEART: 8, Item.SKULL: 12}
const MAX_BOMBS_CAP := 8 # Bomb items stop there
const FIRE_MAX := 3 # Fire level of a regular bomb; pumping goes up to LEVEL_MAX
const PUMP_MAX := 3 # pumps a held bomb takes
const LEVEL_MAX := 6
const LEVEL_RADIUS := 0.75 # blast radius added per level

# Skull sicknesses, one drawn at random.
enum Sick { NONE, BIG, TINY, DISARMED, REVERSE, DISGUISE, INSTANT, FIRE }
const SICK_LABELS := {
	Sick.BIG: "Géant", Sick.TINY: "Minuscule", Sick.DISARMED: "Désarmé", Sick.REVERSE: "Inversé",
	Sick.DISGUISE: "Déguisé", Sick.INSTANT: "Instantané", Sick.FIRE: "En feu",
}
const SICK_TIME := 15.0
const INSTANT_FUSE := 1.0
const BIG_SPEED := 0.6 # speed factor of a big player (Big sickness, Gulliver)
const TINY_SPEED := 1.5

# Evil: one per round, something happens to everyone for a while.
enum Evil { NONE, GULLIVER, TWISTER, THROW, SHUFFLE, MAXIMUM, DISCO, PLAGUE }
const EVIL_LABELS := {
	Evil.GULLIVER: "Gulliver", Evil.TWISTER: "Tornade", Evil.THROW: "Lancers", Evil.SHUFFLE: "Mélange",
	Evil.MAXIMUM: "Maximum", Evil.DISCO: "Disco", Evil.PLAGUE: "Peste",
}
const EVIL_TIME := 10.0
const TWISTER_SPEED := 2.5
const TWISTER_REACH := 0.6 # how close a player must come to be caught
const TWISTER_THROW := 3 # cells a caught player is flung
const PLAGUE_INTERVAL := 1.5 # seconds between two dizzy spells
const DIZZY_TIME := 1.0

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
var items := {} # Item -> false for the items turned off; every other item is on

func item_enabled(item: int) -> bool:
	return items.get(item, true)

# Blast radius of a bomb of the given power level.
static func blast_radius(level: int) -> float:
	return BOMB_RADIUS + LEVEL_RADIUS * (level - 1)

func grid_size() -> Vector2i:
	return MAP_SIZES[map_size]

func player_count() -> int:
	return bot_count + 1
