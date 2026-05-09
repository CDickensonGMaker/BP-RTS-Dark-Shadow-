extends Node

# Preload to avoid parse-order issues with class_name
const OrderTypeScript = preload("res://battle_system/data/order_type.gd")

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
# Special Weapons/Abilities:
#   - breath_fire_01.ogg through breath_fire_02.ogg  # Dragon/monster fire breath
#   - breath_poison_01.ogg through breath_poison_02.ogg  # Poison breath (uses fire sounds)
#   - magic_missile_01.ogg through magic_missile_02.ogg  # Wizard projectile
#   - magic_cast_01.ogg through magic_cast_02.ogg  # Generic spell cast
#   - cannon_fire_01.ogg through cannon_fire_02.ogg  # Artillery fire
#   - explosion_01.ogg through explosion_03.ogg  # Spell/artillery impacts
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

# === AUDIO RATE LIMITING (for volleys) ===
# Prevents 24 archers from playing 24 identical sounds simultaneously
var _sfx_last_played: Dictionary = {}  # String -> float (msec timestamp)
var _sfx_rate_limits: Dictionary = {   # String pattern -> min interval (ms)
	"bow_release": 80,      # Max ~12 bow sounds per second (volley limit)
	"arrow_hit": 60,        # Slightly faster for impacts
	"sword_hit": 40,        # Melee sounds more frequent for layering
	"sword_clank": 40,      # Clanks layer with hits
	"sword_parry": 80,      # Parry sounds for filler
	"sword_swing": 40,      # Allow rapid swings
	"shield_block": 80,     # Block sounds for filler
	"metal_clang": 60,      # Metal clangs for layering
	"death": 120,           # Death cries slightly faster
	"breath_fire": 500,     # Breath weapons are slow, limit to 2/sec
	"breath_poison": 500,   # Same for poison breath
	"magic_missile": 200,   # Magic missiles can fire more often
	"magic_cast": 200,      # Spell cast sounds
	"cannon_fire": 300,     # Artillery is slow
	"cannon_boom": 300,     # Cannon boom cut short
	"explosion": 100,       # Explosions can overlap slightly
	"melee_ambience": 500,  # Ambient melee clash loop
	"combat_clashing": 400, # Ambient combat clashing layer
	"charge_shouting": 800, # Charge/engage sound (limit spam)
}
const DEFAULT_SFX_RATE_LIMIT: float = 25.0  # Default 25ms minimum between same sound

# === MELEE AMBIENCE SYSTEM ===
# Plays continuous ambient combat sounds during active melee engagements
# Uses AudioStreamPlayer3D for spatial audio positioned at combat centroid
var _melee_ambience_players: Array[AudioStreamPlayer3D] = []
var _melee_ambience_active: bool = false
var _melee_filler_timer: float = 0.0
var _melee_ambience_fade_tween: Tween = null  # For fade out on combat end
const MELEE_FILLER_INTERVAL: float = 0.3  # Play filler sounds every 0.3 seconds
const MAX_MELEE_AMBIENCE_PLAYERS: int = 4
const COMBAT_AUDIO_FADE_TIME: float = 0.8  # Fade out duration when combat ends

# === COMBAT CLASHING AMBIENT LAYER ===
# Plays 1-2 staggered combat clashing sounds when units are in combat
# Spatial audio - louder when camera is closer to fighting
var _combat_clashing_players: Array[AudioStreamPlayer3D] = []
var _combat_clashing_active: bool = false
var _combat_clashing_timer: float = 0.0
var _combat_clashing_stagger_timer: float = 0.0
var _combat_clashing_fade_tween: Tween = null  # For fade out on combat end
const COMBAT_CLASHING_INTERVAL: float = 2.5  # Time between clashing sound sets
const COMBAT_CLASHING_STAGGER: float = 0.3   # Stagger between layered sounds
const MAX_COMBAT_CLASHING_PLAYERS: int = 2   # 1-2 sounds staggered
const COMBAT_CLASHING_VARIANTS: int = 6      # combat clashing1-6.wav
const COMBAT_CLASHING_MAX_DISTANCE: float = 80.0  # Distance for full attenuation
const COMBAT_CLASHING_MIN_DISTANCE: float = 5.0   # Distance for full volume

# Cached combat clashing sounds (spaces in filenames require preloading)
var _combat_clashing_cache: Array[AudioStream] = []

# Cached sword clank variants (new files with spaces)
var _sword_clank_space_cache: Array[AudioStream] = []
const SWORD_CLANK_SPACE_VARIANTS: int = 4  # sword clank1-4.wav

# Cached charge shouting sound
var _charge_shouting_cache: AudioStream = null

# Cached cannon boom cut short
var _cannon_boom_cache: AudioStream = null

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

	# Melee ambience player pool (dedicated for continuous combat sounds)
	# Uses AudioStreamPlayer3D for spatial positioning at combat centroid
	for i in range(MAX_MELEE_AMBIENCE_PLAYERS):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.bus = BUS_SFX
		player.volume_db = -8.0  # Slightly quieter for ambient
		player.max_distance = 100.0
		player.unit_size = 10.0  # Reference distance for attenuation
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_melee_ambience_players.append(player)

	# Combat clashing ambient layer players (spatial 3D audio)
	for i in range(MAX_COMBAT_CLASHING_PLAYERS):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.bus = BUS_SFX
		player.volume_db = -4.0  # Slightly louder ambient layer
		player.max_distance = COMBAT_CLASHING_MAX_DISTANCE
		player.unit_size = COMBAT_CLASHING_MIN_DISTANCE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_combat_clashing_players.append(player)


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

	# Preload combat clashing sounds (files have spaces in names)
	_preload_combat_clashing_sounds()

	# Preload sword clank variants with spaces (sword clank1-4.wav)
	_preload_sword_clank_space_sounds()

	# Preload charge shouting sound
	_preload_charge_shouting_sound()

	# Preload cannon boom cut short
	_preload_cannon_boom_sound()


func _preload_combat_clashing_sounds():
	"""Preload combat clashing sounds (filenames have spaces)"""
	_combat_clashing_cache.clear()
	# Files: combat clashing1.wav through combat clashing6.wav (note: 5 is separate naming)
	var filenames: Array[String] = [
		"combat clashing1.wav",
		"combat clashing2.wav",
		"combat clashing3.wav",
		"combat clashing4.wav",
		"combat clashing 5.wav",  # Has extra space before 5
		"combat clashing6.wav",
	]
	for filename in filenames:
		var path: String = PATH_SFX_COMBAT + filename
		if ResourceLoader.exists(path):
			_combat_clashing_cache.append(load(path))


func _preload_sword_clank_space_sounds():
	"""Preload sword clank sounds with spaces (sword clank1-4.wav)"""
	_sword_clank_space_cache.clear()
	for i in range(1, SWORD_CLANK_SPACE_VARIANTS + 1):
		var path: String = PATH_SFX_COMBAT + "sword clank%d.wav" % i
		if ResourceLoader.exists(path):
			_sword_clank_space_cache.append(load(path))


func _preload_charge_shouting_sound():
	"""Preload charge shouting sound"""
	var path: String = PATH_SFX_COMBAT + "charge shouting.wav"
	if ResourceLoader.exists(path):
		_charge_shouting_cache = load(path)


func _preload_cannon_boom_sound():
	"""Preload cannon boom cut short sound"""
	var path: String = PATH_SFX_COMBAT + "cannon boom cut short.wav"
	if ResourceLoader.exists(path):
		_cannon_boom_cache = load(path)


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
		BattleSignals.charge_impact.connect(_on_charge_impact)


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


func play_sfx(sfx_name: String, _position: Vector3 = Vector3.ZERO):
	"""Play a sound effect with rate limiting for volleys"""
	# Check rate limit to prevent volley spam
	if not _check_sfx_rate_limit(sfx_name):
		return  # Skip - played too recently

	var path: String = PATH_SFX_COMBAT + sfx_name
	var stream: AudioStream = _load_sfx(path)
	if stream:
		_play_on_pool(sfx_players, stream)
		sfx_played.emit(sfx_name)


func _check_sfx_rate_limit(sfx_name: String) -> bool:
	"""Returns true if the sound can be played, false if rate limited."""
	var current_time: float = Time.get_ticks_msec()

	# Determine rate limit for this sound type
	var rate_limit: float = DEFAULT_SFX_RATE_LIMIT
	for pattern in _sfx_rate_limits.keys():
		if sfx_name.begins_with(pattern):
			rate_limit = _sfx_rate_limits[pattern]
			break

	# Check if enough time has passed since last play
	if _sfx_last_played.has(sfx_name):
		var last_time: float = _sfx_last_played[sfx_name]
		if current_time - last_time < rate_limit:
			return false  # Rate limited

	# Update last played time
	_sfx_last_played[sfx_name] = current_time
	return true


func play_sfx_random(base_name: String, variant_count: int, _position: Vector3 = Vector3.ZERO):
	"""Play a random variant of a sound effect (e.g., sword_hit with 5 variants)"""
	# Check rate limit using base name (all variants share same limit)
	if not _check_sfx_rate_limit(base_name):
		return  # Skip - played too recently

	var idx: int = randi_range(1, variant_count)
	var sfx_name: String = "%s_%02d" % [base_name, idx]

	var path: String = PATH_SFX_COMBAT + sfx_name
	var stream: AudioStream = _load_sfx(path)
	if stream:
		_play_on_pool(sfx_players, stream)
		sfx_played.emit(sfx_name)


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


# === LAYERED SOUND SYSTEM ===
# Plays multiple sounds simultaneously for fuller combat audio

func play_layered_melee_hit(position: Vector3 = Vector3.ZERO):
	"""Play layered melee impact sounds for fuller combat feel.
	Combines sword_hit + sword_clank + occasional metal_clang.
	Now includes new sword clank variants (sword clank1-4.wav)."""
	# Primary hit sound
	play_sfx_random("sword_hit", 5, position)

	# Layer with sword clank (70% chance)
	# 50% chance to use new sword clank variants, 50% to use original
	if randf() < 0.7:
		if randf() < 0.5 and _sword_clank_space_cache.size() > 0:
			_play_sword_clank_space(position)
		else:
			play_sfx_random("sword_clank", 3, position)

	# Occasional metal clang for extra punch (30% chance)
	if randf() < 0.3:
		play_sfx_random("metal_clang", 3, position)


func _play_sword_clank_space(position: Vector3 = Vector3.ZERO):
	"""Play one of the sword clank sounds with spaces in filename."""
	if _sword_clank_space_cache.is_empty():
		return
	if not _check_sfx_rate_limit("sword_clank"):
		return
	var stream: AudioStream = _sword_clank_space_cache[randi() % _sword_clank_space_cache.size()]
	_play_on_pool(sfx_players, stream)
	sfx_played.emit("sword_clank_space")


func play_layered_arrow_hit(position: Vector3 = Vector3.ZERO):
	"""Play layered arrow impact sounds."""
	play_sfx_random("arrow_hit", 3, position)


func play_layered_bow_volley(position: Vector3 = Vector3.ZERO, archer_count: int = 1):
	"""Play bow release with intensity based on archer count."""
	# Play multiple bow sounds for volley effect (capped at 3)
	var sounds_to_play: int = mini(ceili(float(archer_count) / 8.0), 3)
	for i in sounds_to_play:
		play_sfx_random("bow_release", 3, position)


# === MELEE AMBIENCE SYSTEM ===
# Continuous ambient combat sounds during melee engagements
# Now uses 3D spatial audio positioned at combat centroid

func start_melee_ambience():
	"""Start playing ambient melee sounds when combat begins. Instant start."""
	# Cancel any fade-out in progress
	if _melee_ambience_fade_tween and _melee_ambience_fade_tween.is_valid():
		_melee_ambience_fade_tween.kill()
	if _combat_clashing_fade_tween and _combat_clashing_fade_tween.is_valid():
		_combat_clashing_fade_tween.kill()

	# Restore volume immediately for instant combat audio start
	for player in _melee_ambience_players:
		player.volume_db = -8.0  # Default melee ambience volume
	for player in _combat_clashing_players:
		player.volume_db = -4.0  # Default combat clashing volume

	if _melee_ambience_active:
		return
	_melee_ambience_active = true
	_melee_filler_timer = 0.0
	# Also start combat clashing layer
	_combat_clashing_active = true
	_combat_clashing_timer = 0.0


func stop_melee_ambience():
	"""Stop ambient melee sounds when all combats end. Fades out smoothly."""
	if not _melee_ambience_active:
		return

	_melee_ambience_active = false

	# Cancel any existing fade
	if _melee_ambience_fade_tween and _melee_ambience_fade_tween.is_valid():
		_melee_ambience_fade_tween.kill()

	# Fade out all melee ambience players
	_melee_ambience_fade_tween = create_tween()
	_melee_ambience_fade_tween.set_parallel(true)

	for player in _melee_ambience_players:
		if player.playing:
			_melee_ambience_fade_tween.tween_property(player, "volume_db", -80.0, COMBAT_AUDIO_FADE_TIME)

	# Stop players after fade completes
	_melee_ambience_fade_tween.chain().tween_callback(_stop_melee_players)

	# Also stop combat clashing layer with fade
	_stop_combat_clashing()


func _stop_melee_players():
	"""Called after fade completes to fully stop melee ambience players."""
	for player in _melee_ambience_players:
		player.stop()
		player.volume_db = -8.0  # Reset to default volume


func update_melee_ambience(delta: float, active_melee_count: int, melee_positions: Array):
	"""Called each frame to play filler sounds during active melee.
	melee_positions: Array of Vector3 positions where melee is happening.
	Uses 3D spatial audio for directional sound."""
	if not _melee_ambience_active or active_melee_count == 0:
		if _melee_ambience_active:
			stop_melee_ambience()
		return

	# Calculate combat centroid for 3D audio positioning
	var combat_centroid: Vector3 = _calculate_combat_centroid(melee_positions)

	_melee_filler_timer += delta

	# Play filler sounds at regular intervals
	if _melee_filler_timer >= MELEE_FILLER_INTERVAL:
		_melee_filler_timer = 0.0

		# Pick a random melee position for variety
		if melee_positions.size() > 0:
			var pos: Vector3 = melee_positions[randi() % melee_positions.size()]

			# Randomly play parry, block, or swing sounds using 3D players
			var filler_roll: float = randf()
			if filler_roll < 0.35:
				_play_3d_filler("sword_parry", 3, pos)
			elif filler_roll < 0.6:
				_play_3d_filler("shield_block", 3, pos)
			elif filler_roll < 0.85:
				_play_3d_filler("sword_swing", 3, pos)
			else:
				# Occasional extra clang (include new variants)
				if randf() < 0.5 and _sword_clank_space_cache.size() > 0:
					_play_3d_sound_from_cache(_sword_clank_space_cache, pos)
				else:
					_play_3d_filler("sword_clank", 3, pos)

	# Update combat clashing ambient layer
	_update_combat_clashing(delta, combat_centroid, active_melee_count)


func _play_3d_filler(base_name: String, variant_count: int, position: Vector3):
	"""Play a random variant of a filler sound at 3D position."""
	if not _check_sfx_rate_limit(base_name):
		return

	var idx: int = randi_range(1, variant_count)
	var sfx_name: String = "%s_%02d" % [base_name, idx]
	var path: String = PATH_SFX_COMBAT + sfx_name
	var stream: AudioStream = _load_sfx(path)
	if stream:
		_play_on_3d_pool(_melee_ambience_players, stream, position)


func _play_3d_sound_from_cache(cache: Array[AudioStream], position: Vector3):
	"""Play a random sound from a preloaded cache at 3D position."""
	if cache.is_empty():
		return
	var stream: AudioStream = cache[randi() % cache.size()]
	_play_on_3d_pool(_melee_ambience_players, stream, position)


func _play_on_3d_pool(pool: Array[AudioStreamPlayer3D], stream: AudioStream, position: Vector3):
	"""Play a sound on the first available 3D player in the pool."""
	for player in pool:
		if not player.playing:
			player.stream = stream
			player.global_position = position
			player.play()
			return
	# All players busy, use first one (interrupts oldest)
	if pool.size() > 0:
		pool[0].stream = stream
		pool[0].global_position = position
		pool[0].play()


func _calculate_combat_centroid(melee_positions: Array) -> Vector3:
	"""Calculate the center point of all active combat positions."""
	if melee_positions.is_empty():
		return Vector3.ZERO
	var centroid: Vector3 = Vector3.ZERO
	for pos in melee_positions:
		centroid += pos
	return centroid / float(melee_positions.size())


# === COMBAT CLASHING AMBIENT LAYER ===
# Plays 1-2 staggered combat clashing sounds when units are in combat
# Uses spatial 3D audio - louder when camera is closer to fighting

func _update_combat_clashing(delta: float, combat_centroid: Vector3, active_melee_count: int):
	"""Update combat clashing ambient layer with staggered playback."""
	if not _combat_clashing_active or active_melee_count == 0:
		return

	if _combat_clashing_cache.is_empty():
		return  # No sounds loaded

	_combat_clashing_timer += delta

	# Time to play a new set of clashing sounds
	if _combat_clashing_timer >= COMBAT_CLASHING_INTERVAL:
		_combat_clashing_timer = 0.0
		_combat_clashing_stagger_timer = 0.0

		# Play first sound immediately
		_play_combat_clashing_sound(combat_centroid, active_melee_count)

		# Schedule second staggered sound (50% chance)
		if randf() < 0.5:
			# Use a timer callback for stagger
			get_tree().create_timer(COMBAT_CLASHING_STAGGER).timeout.connect(
				func(): _play_combat_clashing_sound(combat_centroid, active_melee_count),
				CONNECT_ONE_SHOT
			)


func _play_combat_clashing_sound(position: Vector3, intensity: int):
	"""Play a combat clashing sound at the given position.
	Volume is scaled by intensity (more combats = louder)."""
	if _combat_clashing_cache.is_empty():
		return

	if not _check_sfx_rate_limit("combat_clashing"):
		return

	# Pick a random clashing sound
	var stream: AudioStream = _combat_clashing_cache[randi() % _combat_clashing_cache.size()]

	# Scale volume based on combat intensity (more active melees = louder)
	var intensity_db: float = clampf(float(intensity) * 0.5, 0.0, 3.0)  # +0.5dB per melee, cap at +3dB

	# Find an available player
	for player in _combat_clashing_players:
		if not player.playing:
			player.stream = stream
			player.global_position = position
			player.volume_db = -4.0 + intensity_db  # Base volume + intensity bonus
			player.play()
			sfx_played.emit("combat_clashing")
			return

	# All busy, use first
	if _combat_clashing_players.size() > 0:
		_combat_clashing_players[0].stream = stream
		_combat_clashing_players[0].global_position = position
		_combat_clashing_players[0].volume_db = -4.0 + intensity_db
		_combat_clashing_players[0].play()
		sfx_played.emit("combat_clashing")


func _stop_combat_clashing():
	"""Stop all combat clashing sounds. Fades out smoothly."""
	if not _combat_clashing_active:
		return

	_combat_clashing_active = false

	# Cancel any existing fade
	if _combat_clashing_fade_tween and _combat_clashing_fade_tween.is_valid():
		_combat_clashing_fade_tween.kill()

	# Fade out all combat clashing players
	_combat_clashing_fade_tween = create_tween()
	_combat_clashing_fade_tween.set_parallel(true)

	for player in _combat_clashing_players:
		if player.playing:
			_combat_clashing_fade_tween.tween_property(player, "volume_db", -80.0, COMBAT_AUDIO_FADE_TIME)

	# Stop players after fade completes
	_combat_clashing_fade_tween.chain().tween_callback(_stop_clashing_players)


func _stop_clashing_players():
	"""Called after fade completes to fully stop combat clashing players."""
	for player in _combat_clashing_players:
		player.stop()
		player.volume_db = -4.0  # Reset to default volume


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


func _on_regiment_selected(_regiment):
	play_order_acknowledgment("select")


func _on_order_given(_regiment, order, _target):
	match order:
		OrderTypeScript.Type.MOVE, OrderTypeScript.Type.ATTACK_MOVE:
			play_order_acknowledgment("move")
		OrderTypeScript.Type.CHARGE:
			play_order_acknowledgment("charge")
		OrderTypeScript.Type.HOLD_POSITION:
			play_order_acknowledgment("formation")
		OrderTypeScript.Type.GUARD:
			play_order_acknowledgment("guard")


func _on_regiment_routing(_regiment):
	play_morale_event("unit_routing")
	# Increase music intensity
	set_music_intensity(minf(_current_music_intensity + 0.2, 1.0))


func _on_regiment_attacked(attacker, defender, _damage: int):
	# Play combat SFX based on unit type
	if attacker.data.unit_type == UnitType.Type.RANGED:
		play_sfx_random("arrow_hit", 3, defender.global_position)
	else:
		play_sfx_random("sword_hit", 5, defender.global_position)

	# Slight intensity increase
	if _battle_active:
		set_music_intensity(minf(_current_music_intensity + 0.05, 1.0))


func _on_regiment_dead(regiment):
	# Play death cry when a regiment is destroyed
	if is_instance_valid(regiment):
		play_sfx_random("death", 5, regiment.global_position)
	else:
		play_sfx_random("death", 5, Vector3.ZERO)


func _on_ability_used(regiment, ability: int):
	match ability:
		AbilityType.Type.CHARGE:
			play_sfx("cavalry_charge_01", regiment.global_position)
		AbilityType.Type.WAR_CRY:
			play_sfx("war_cry_01", regiment.global_position)
		AbilityType.Type.VOLLEY_FIRE:
			play_sfx("volley_fire_01", regiment.global_position)


func _on_formation_changed(_regiment, _old_formation: int, _new_formation: int) -> void:
	# Play formation change sound
	play_order_acknowledgment("formation")


func _on_charge_impact(charger, _target, _was_braced: bool):
	"""Play charge shouting sound when units charge into combat."""
	if not is_instance_valid(charger):
		return
	play_charge_shouting(charger.global_position)


# === CHARGE SHOUTING ===

func play_charge_shouting(position: Vector3 = Vector3.ZERO):
	"""Play charge/engage shouting sound at position."""
	if _charge_shouting_cache == null:
		return

	if not _check_sfx_rate_limit("charge_shouting"):
		return

	_play_on_pool(sfx_players, _charge_shouting_cache)
	sfx_played.emit("charge_shouting")


# === CANNON BOOM ===

func play_cannon_boom(position: Vector3 = Vector3.ZERO):
	"""Play cannon boom cut short sound for artillery fire.
	Alternative to cannon_fire sounds for a shorter, punchier effect."""
	if _cannon_boom_cache == null:
		# Fallback to regular cannon fire
		play_sfx_random("cannon_fire", 2, position)
		return

	if not _check_sfx_rate_limit("cannon_boom"):
		return

	_play_on_pool(sfx_players, _cannon_boom_cache)
	sfx_played.emit("cannon_boom")
