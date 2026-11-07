extends TestCase

const TMP := "user://test_online_store.cfg"

func _with_tmp_store(body: Callable) -> void:
	var saved := OnlineStore.path
	OnlineStore.path = TMP
	DirAccess.remove_absolute(TMP)
	body.call()
	DirAccess.remove_absolute(TMP)
	OnlineStore.path = saved

func test_nickname_round_trip() -> void:
	_with_tmp_store(func() -> void:
		assert_eq(OnlineStore.load_nickname(), "", "aucun pseudo au départ")
		OnlineStore.save_nickname("Paul")
		assert_eq(OnlineStore.load_nickname(), "Paul", "pseudo relu"))

func test_token_round_trip() -> void:
	_with_tmp_store(func() -> void:
		assert_eq(OnlineStore.token_for("K7P2QX"), "", "aucun jeton au départ")
		OnlineStore.save_nickname("Paul")
		OnlineStore.save_token("K7P2QX", "abc")
		OnlineStore.save_token("ZZZZZZ", "def")
		assert_eq(OnlineStore.token_for("K7P2QX"), "abc", "premier jeton")
		assert_eq(OnlineStore.token_for("ZZZZZZ"), "def", "second jeton")
		assert_eq(OnlineStore.load_nickname(), "Paul", "le pseudo reste"))
