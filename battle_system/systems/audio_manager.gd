extends Node

## Centralized audio management for the battle system.
## Per bible §16, handles 5 audio layers:
## 1. Music - dynamic, escalating with battle intensity
## 2. Ambient - environmental loops
## 3. Unit chatter - order acknowledgments
## 4. Combat SFX - weapons, impacts, deaths
## 5. UI sounds - clicks, alerts

# === AUDIO BUSES ===
# Create these in Project Settings > Audio > Buses:
# - Master
#   - Music
#   - Ambient
#   - Voice
#   - SFX
#   - UI

const BUS_MUSIC: String = "Music"
const BUS_AMBIENT: String = "Ambient"
const BUS_VOICE: String = "Voice"
const BUS_SFX: String = "SFX"
const BUS_UI: String = "UI"

# === AUDIO PATHS ===
# Drop your audio files in these folders:
const PATH_MUSIC: String = "res://assets/audio/music/"
const PATH_SFX_COMBAT: String = "res://assets/audio/sfx/combat/"
const PATH_SFX_UI: String = "res://assets/audio/sfx/ui/"
const PATH_SFX_AMBIENT: String = "res://assets/audio/sfx/ambient/"
const PATH_VOICE_ORDERS: String = "res://assets/audio/voice/orders/"
const PATH_VOICE_COMBAT: String = "res://assets/audio/voice/combat/"
const PATH_VOICE_MORALE: String = "res://assets/audio/voice/morale/"

# === AUDIO FILE NAMING CONVENTIONS ===
# Music:
#   - music_calm.ogg / .mp3 / .wav
#   - music_battle_light.ogg
#   - music_battle_intense.ogg
#   - music_victory.ogg
#   - music_defeat.ogg
#
# Order Acknowledgments (per bible §16.3):
#   - order_select_01.ogg through order_select_05.ogg
#   - order_move_01.ogg through order_move_05.ogg
#   - order_attack_01.ogg through order_attack_05.ogg
#   - order_charge_01.ogg through order_charge_05.ogg
#   - order_retreat_01.ogg through order_retreat_05.ogg
#   - order_formation_01.ogg through order_formation_05.ogg
#   - order_guard_01.ogg through order_guard_05.ogg
#
# Combat SFX:
#   - sword_hit_01.ogg through sword_hit_05.ogg
#   - sword_miss_01.ogg
#   - arrow_fire_01.ogg
#   - arrow_hit_01.ogg
#   - shield_block_01.ogg
#   - death_01.ogg through death_05.ogg
#   - cavalry_charge_01.ogg
#   - hooves_01.ogg
#
# Morale Events (per bible §16.2):
#   - unit_routing.ogg (horror cue)
#   - cavalry_charge_incoming.ogg (drum hit / horn)
#   - ammo_empty.ogg (quiet click)
#   - battle_won.ogg (victory sting)
#   - battle_lost.ogg (defeat sting)
#
# Ambient:
#   - ambient_wind_01.ogg
#   - ambient_birds_01.ogg
#   - ambient_battlefield_01.ogg

# === AUDIO PLAYERS ===
var music_player: AudioStreamPlayer = null
var music_player_b: AudioStreamPlayer = null  # Second player for crossfade
var ambient_player: AudioStreamPlayer = null
var voice_players: Array[AudioStreamPlayer] = []
var sfx_players: Array[AudioStreamPlayer] = []

const MAX_VOICE_PLAYERS: int = 4
const MAX_SFX_PLAYERS: int = 16

# Crossfade state
var _music_tween: Tween = null
var _active_music_player: AudioStreamPlayer = null  # Which player is currently active

# === AUDIO CACHES ===
var _music_cache: Dictionary = {}      # String -> AudioStream
var _sfx_cache: Dictionary = {}        # String -> AudioStream
var _voice_cache: Dictionary = {}      # String -> Array[AudioStream]

# === STATE ===
var _current_music_intensity: float = 0.0
var _battle_active: bool = false

# === SIGNALS ===
signal music_changed(track_name: String)
signal sfx_played(sfx_name: String)
signal voice_played(voice_name: String)


func _ready():
	_setup_audio_players()
	_preload_audio()
	_connect_signals()


func _setup_audio_players():
	# Music player A (primary)
	music_player = AudioStreamPlayer.new()
	music_player.bus = BUS_MUSIC
	music_player.volume_db = -5.0
	add_child(music_player)

	# Music player B (for crossfade)
	music_player_b = AudioStreamPlayer.new()
	music_player_b.bus = BUS_MUSIC
	music_player_b.volume_db = -80.0  # Start silent
	add_child(music_player_b)

	_active_music_player = music_player

	# Ambient player
	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = BUS_AMBIENT
	ambient_player.volume_db = -10.0
	add_child(ambient_player)

	# Voice player pool
	for i in range(MAX_VOICE_PLAYERS):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = BUS_VOICE
		add_child(player)
		voice_players.append(player)

	# SFX player pool
	for i in range(MAX_SFX_PLAYERS):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		sfx_players.append(player)


func _preload_audio():
	# Preload commonly used audio
	# Only loads files that exist
	_try_load_music("calm", PATH_MUSIC + "music_calm")
	_try_load_music("battle_light", PATH_MUSIC + "music_battle_light")
	_try_load_music("battle_intense", PATH_MUSIC + "music_battle_intense")
	_try_load_music("victory", PATH_MUSIC + "music_victory")
	_try_load_music("defeat", PATH_MUSIC + "music_defeat")

	# Preload order acknowledgments
	for order_type in ["select", "move", "attack", "charge", "retreat", "formation", "guard"]:
		_try_load_voice_variants("order_" + order_type, PATH_VOICE_ORDERS, 5)


func _try_load_music(key: String, base_path: String):
	for ext in [".ogg", ".mp3", ".wav"]:
		var path: String = base_path + ext
		if ResourceLoader.exists(path):
			_music_cache[key] = load(path)
			return


func _try_load_voice_variants(key: String, folder: String, count: int):
	var variants: Array[AudioStream] = []
	for i in range(1, count + 1):
		var filename: String = "%s_%02d" % [key, i]
		for ext in [".ogg", ".mp3", ".wav"]:
			var path: String = folder + filename + ext
			if ResourceLoader.exists(path):
				variants.append(load(path))
				break
	if variants.size() > 0:
		_voice_cache[key] = variants


func _connect_signals():
	if BattleSignals:
		BattleSignals.battle_started.connect(_on_battle_started)
		BattleSignals.battle_ended.connect(_on_battle_ended)
		BattleSignals.regiment_selected.connect(_on_regiment_selected)
		BattleSignals.order_given.connect(_on_order_given)
		BattleSignals.regiment_routing.connect(_on_regiment_routing)
		BattleSignals.regiment_attacked.connect(_on_regiment_attacked)
		BattleSignals.regiment_dead.connect(_on_regiment_dead)
		BattleSignals.ability_used.connect(_on_ability_used)
		BattleSignals.formation_type_changed.connect(_on_formation_changed)


# === PUBLIC API ===

func play_music(track_key: String, fade_time: float = 1.0):
	"""Play a music track by key (calm, battle_light, battle_intense, victory, defeat)"""
	if not _music_cache.has(track_key):
		push_warning("AudioManager: Music track not found: " + track_key)
		return

	# Cancel any existing fade
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	# Determine which player to fade in (swap between A and B)
	var fade_in_player: AudioStreamPlayer
	var fade_out_player: AudioStreamPlayer

	if _active_music_player == music_player:
		fade_in_player = music_player_b
		fade_out_player = music_player
	else:
		fade_in_player = music_player
		fade_out_player = music_player_b

	# Setup new track on fade-in player
	fade_in_player.stream = _music_cache[track_key]
	fade_in_player.volume_db = -80.0  # Start silent
	fade_in_player.play()

	# Crossfade using tween
	_music_tween = create_tween()
	_music_tween.set_parallel(true)

	# Fade out old player
	if fade_out_player.playing:
		_music_tween.tween_property(fade_out_player, "volume_db", -80.0, fade_time)
		_music_tween.tween_callback(fade_out_player.stop).set_delay(fade_time)

	# Fade in new player
	_music_tween.tween_property(fade_in_player, "volume_db", -5.0, fade_time)

	_active_music_player = fade_in_player
	music_changed.emit(track_key)


func stop_music(fade_time: float = 1.0):
	"""Stop the current music track with fade out"""
	# Cancel any existing fade
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	if not _active_music_player or not _active_music_player.playing:
		return

	# Fade out active player
	_music_tween = create_tween()
	_music_tween.tween_property(_active_music_player, "volume_db", -80.0, fade_time)
	_music_tween.tween_callback(_active_music_player.stop)


func play_ambient(ambient_key: String):
	"""Play an ambient loop"""
	var path: String = PATH_SFX_AMBIENT + ambient_key
	for ext in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(path + ext):
			ambient_player.stream = load(path + ext)
			ambient_player.play()
			return


func play_sfx(sfx_name: String, position: Vector3 = Vector3.ZERO):
	"""Play a sound effect"""
	var path: String = PATH_SFX_COMBAT + sfx_name
	var stream: AudioStream = _load_sfx(path)
	if stream:
		_play_on_pool(sfx_players, stream)
		sfx_played.emit(sfx_name)


func play_sfx_random(base_name: String, variant_count: int, position: Vector3 = Vector3.ZERO):
	"""Play a random variant of a sound effect (e.g., sword_hit with 5 variants)"""
	var idx: int = randi_range(1, variant_count)
	var sfx_name: String = "%s_%02d" % [base_name, idx]
	play_sfx(sfx_name, position)


func play_ui_sfx(sfx_name: String):
	"""Play a UI sound effect"""
	var path: String = PATH_SFX_UI + sfx_name
	var stream: AudioStream = _load_sfx(path)
	if stream:
		# Use SFX pool for UI sounds too
		_play_on_pool(sfx_players, stream)


func play_order_acknowledgment(order_type: String):
	"""Play an order acknowledgment voice line"""
	var key: String = "order_" + order_type
	if _voice_cache.has(key):
		var variants: Array = _voice_cache[key]
		if variants.size() > 0:
			var stream: AudioStream = variants[randi() % variants.size()]
			_play_on_pool(voice_players, stream)
			voice_played.emit(key)


func play_morale_event(event_name: String):
	"""Play a morale-related audio cue"""
	var path: String = PATH_VOICE_MORALE + event_name
	var stream: AudioStream = _load_sfx(path)
	if stream:
		_play_on_pool(voice_players, stream)


func set_music_intensity(intensity: float):
	"""Set battle music intensity (0.0 = calm, 1.0 = intense)"""
	intensity = clampf(intensity, 0.0, 1.0)
	_current_music_intensity = intensity

	# Switch music tracks based on intensity
	if intensity < 0.3:
		if _music_cache.has("calm"):
			play_music("calm")
	elif intensity < 0.7:
		if _music_cache.has("battle_light"):
			play_music("battle_light")
	else:
		if _music_cache.has("battle_intense"):
			play_music("battle_intense")


# === HELPER FUNCTIONS ===

func _load_sfx(base_path: String) -> AudioStream:
	for ext in [".ogg", ".mp3", ".wav"]:
		var path: String = base_path + ext
		if ResourceLoader.exists(path):
			if not _sfx_cache.has(path):
				_sfx_cache[path] = load(path)
			return _sfx_cache[path]
	return null


func _play_on_pool(pool: Array[AudioStreamPlayer], stream: AudioStream):
	for player in pool:
		if not player.playing:
			player.stream = stream
			player.play()
			return
	# All players busy, use first one (interrupts oldest)
	if pool.size() > 0:
		pool[0].stream = stream
		pool[0].play()


# === SIGNAL HANDLERS ===

func _on_battle_started():
	_battle_active = true
	set_music_intensity(0.3)
	play_ambient("ambient_battlefield_01")


func _on_battle_ended(result: Dictionary):
	_battle_active = false
	if result.get("winner", "") == "player":
		play_music("victory")
	else:
		play_music("defeat")
	ambient_player.stop()


func _on_regiment_selected(regiment: Regiment):
	play_order_acknowledgment("select")


func _on_order_given(regiment: Regiment, order: OrderType.Type, target: Variant):
	match order:
		OrderType.Type.MOVE, OrderType.Type.ATTACK_MOVE:
			play_order_acknowledgment("move")
		OrderType.Type.CHARGE:
			play_order_acknowledgment("charge")
		OrderType.Type.HOLD_POSITION:
			play_order_acknowledgment("formation")
		OrderType.Type.GUARD:
			play_order_acknowledgment("guard")


func _on_regiment_routing(regiment: Regiment):
	play_morale_event("unit_routing")
	# Increase music intensity
	set_music_intensity(minf(_current_music_intensity + 0.2, 1.0))


func _on_regiment_attacked(attacker: Regiment, defender: Regiment, damage: int):
	# Play combat SFX based on unit type
	if attacker.data.unit_type == UnitType.Type.RANGED:
		play_sfx_random("arrow_hit", 3, defender.global_position)
	else:
		play_sfx_random("sword_hit", 5, defender.global_position)

	# Slight intensity increase
	if _battle_active:
		set_music_intensity(minf(_current_music_intensity + 0.05, 1.0))


func _on_regiment_dead(regiment: Regiment):
	# Play death cry when a regiment is destroyed
	if is_instance_valid(regiment):
		play_sfx_random("death", 5, regiment.global_position)
	else:
		play_sfx_random("death", 5, Vector3.ZERO)


func _on_ability_used(regiment: Regiment, ability: int):
	match ability:
		AbilityType.Type.CHARGE:
			play_sfx("cavalry_charge_01", regiment.global_position)
		AbilityType.Type.WAR_CRY:
			play_sfx("war_cry_01", regiment.global_position)
		AbilityType.Type.VOLLEY_FIRE:
			play_sfx("volley_fire_01", regiment.global_position)


func _on_formation_changed(_regiment: Node, _old_formation: int, _new_formation: int) -> void:
	# Play formation change sound
	play_order_acknowledgment("formation")
