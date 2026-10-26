class_name PlayerIntent
extends RefCounted

var moving := false
var target := Vector2.ZERO # en coordonnées de case
var place_bomb := false
var action := false
var struggle := 0.0 # shakes this tick (arrow presses, mouse shaking): shortens a stun
