class_name PlayerIntent
extends RefCounted

var moving := false
var target := Vector2.ZERO # en coordonnées de case
var place_bomb := false
var action := false # pressed this tick
var action_held := false # still held down: charges a throw
var detonate := false # sets off the oldest remote bomb
var seq := 0 # online: numbers the intents of a player, so the server can say which it applied last
var struggle := 0.0
# Server only: later intents walked in the same tick, after this one's step (a late intent caught up).
var catch_up: Array[PlayerIntent] = []
# Server only: a tick waiting for the player's late intent: still moving (pushing a bomb), no step.
var late := false # shakes this tick (arrow presses, mouse shaking): shortens a stun or a possession
