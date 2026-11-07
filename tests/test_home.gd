extends TestCase

# The home screen: the hash of an invitation link, the status line, the buttons that follow the form.

const TMP := "user://test_home.cfg"
const SCENE := "res://src/ui/home_screen.tscn"

# Runs body with a home screen built and an empty (or given) saved nickname, then cleans up.
func _with_home(nickname: String, body: Callable) -> void:
	var saved := OnlineStore.path
	OnlineStore.path = TMP
	DirAccess.remove_absolute(TMP)
	if nickname != "":
		OnlineStore.save_nickname(nickname)
	var home: HomeScreen = (load(SCENE) as PackedScene).instantiate()
	home.build() # tests run before the main loop exists: no tree, so no _ready
	home._refresh()
	body.call(home)
	home.free()
	DirAccess.remove_absolute(TMP)
	OnlineStore.path = saved

func test_code_from_hash() -> void:
	assert_eq(HomeScreen.code_from_hash("#k7p2qx"), "K7P2QX", "casse et dièse")
	assert_eq(HomeScreen.code_from_hash(""), "", "pas de hash")
	assert_eq(HomeScreen.code_from_hash("#k7p2"), "", "trop court")
	assert_eq(HomeScreen.code_from_hash("#K7P2QX/"), "K7P2QX", "barre finale")

func test_status_text() -> void:
	assert_true(HomeScreen.status_text(NetClient.Status.WAKING).contains("Réveil"), "réveil")
	assert_eq(HomeScreen.status_text(NetClient.Status.CONNECTING), "Connexion…", "connexion")
	assert_eq(HomeScreen.status_text(NetClient.Status.LOST), "Serveur injoignable, réessaie dans un instant", "perdu")
	assert_eq(HomeScreen.status_text(NetClient.Status.OFFLINE), "", "rien à dire")

func test_online_buttons_need_a_nickname() -> void:
	_with_home("", func(home: HomeScreen) -> void:
		assert_true(home.create_button.disabled, "créer désactivé sans pseudo")
		assert_true(home.join_button.disabled, "rejoindre désactivé sans pseudo")
		home.nickname_edit.text = "Paul"
		home.nickname_edit.text_changed.emit("Paul")
		assert_false(home.create_button.disabled, "créer actif avec un pseudo")
		assert_true(home.join_button.disabled, "rejoindre attend un code")
		home.code_edit.text = "k7p2qx"
		home.code_edit.text_changed.emit("k7p2qx")
		assert_false(home.join_button.disabled, "rejoindre actif avec un code valide"))

func test_saved_nickname_is_prefilled() -> void:
	_with_home("Paul", func(home: HomeScreen) -> void:
		assert_eq(home.nickname_edit.text, "Paul", "pseudo rempli")
		assert_false(home.create_button.disabled, "créer actif")
		assert_eq(home.nickname_edit.max_length, 12, "12 caractères"))

func test_error_is_shown_with_its_label() -> void:
	_with_home("Paul", func(home: HomeScreen) -> void:
		home.show_error("unknown_code")
		assert_eq(home.status_label.text, Protocol.ERROR_LABELS["unknown_code"], "libellé connu")
		home.show_error("zzz")
		assert_eq(home.status_label.text, "zzz", "code inconnu tel quel"))

func test_pasted_code_is_cleaned() -> void:
	for pasted in ["#k7p2qx", "k7p2 qx", "#K7P2QX/", "https://pauldoazan.github.io/bomberman/#K7P2QX"]:
		_with_home("Paul", func(home: HomeScreen) -> void:
			home.code_edit.text = pasted
			home.code_edit.text_changed.emit(pasted)
			assert_eq(home.code_edit.text, "K7P2QX", "code de " + pasted)
			assert_false(home.join_button.disabled, "rejoindre actif pour " + pasted))

func test_error_survives_the_quiet_close() -> void:
	_with_home("Paul", func(home: HomeScreen) -> void:
		home.show_error("unknown_code")
		home._on_status(NetClient.Status.OFFLINE) # Net closes the socket after a refusal
		assert_eq(home.status_label.text, Protocol.ERROR_LABELS["unknown_code"], "le message reste"))

func test_should_rejoin() -> void:
	assert_true(HomeScreen.should_rejoin("K7P2QX", "Paul", "tok", ""), "lien, pseudo et jeton")
	assert_false(HomeScreen.should_rejoin("", "Paul", "tok", ""), "pas de code")
	assert_false(HomeScreen.should_rejoin("K7P2QX", "", "tok", ""), "pas de pseudo")
	assert_false(HomeScreen.should_rejoin("K7P2QX", "Paul", "", ""), "pas de jeton (après Quitter)")
	assert_false(HomeScreen.should_rejoin("K7P2QX", "Paul", "tok", "Connexion perdue"), "retour avec un message")
