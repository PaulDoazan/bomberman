class_name PlayerIntent
extends RefCounted

var moving := false
var target := Vector2.ZERO # en coordonnées de case
var place_bomb := false
var action := false # pressed this tick
var action_held := false # still held down: charges a throw
var detonate := false # sets off the oldest remote bomb
var struggle := 0.0 # shakes this tick (arrow presses, mouse shaking): shortens a stun or a possession
