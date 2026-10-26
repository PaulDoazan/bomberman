class_name TestCase
extends RefCounted

var failures: Array[String] = []

func assert_eq(a, b, msg := "") -> void:
	if a != b:
		failures.append("%s : attendu %s, obtenu %s" % [msg, str(b), str(a)])

func assert_true(c, msg := "") -> void:
	if not c:
		failures.append("%s : attendu true, obtenu %s" % [msg, str(c)])

func assert_false(c, msg := "") -> void:
	if c:
		failures.append("%s : attendu false, obtenu %s" % [msg, str(c)])

func assert_almost(a: float, b: float, eps := 0.01, msg := "") -> void:
	if absf(a - b) > eps:
		failures.append("%s : attendu %s, obtenu %s" % [msg, str(b), str(a)])
