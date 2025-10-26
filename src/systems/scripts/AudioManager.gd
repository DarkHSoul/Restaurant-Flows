extends Node
class_name AudioManager

## Global audio manager for playing sound effects and music
## This is an autoload singleton that can be accessed from anywhere

## Singleton instance
static var instance: AudioManager

## Audio bus names
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

## Volume settings (0.0 to 1.0)
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8

## Audio player pools
var _sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX_PLAYERS := 16  # Maximum simultaneous sound effects

## Sound effect cache (preloaded sounds would go here in the future)
var _sound_cache: Dictionary = {}

func _ready() -> void:
	# Singleton setup
	if instance and instance != self:
		queue_free()
		return
	instance = self

	# Create audio player pool for sound effects
	_create_sfx_player_pool()

	# Apply initial volume settings
	_apply_volume_settings()

	print("[AUDIO_MANAGER] Initialized with %d SFX players" % MAX_SFX_PLAYERS)

func _create_sfx_player_pool() -> void:
	"""Create a pool of AudioStreamPlayer nodes for playing sound effects."""
	for i in range(MAX_SFX_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		player.name = "SFXPlayer%d" % i
		add_child(player)
		_sfx_players.append(player)

func play_sfx(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	"""Play a sound effect by name.

	Args:
		sound_name: Name of the sound file (without extension) in res://assets/audio/sfx/
		volume_db: Volume adjustment in decibels (0 = normal, -6 = half, +6 = double)
		pitch_scale: Pitch multiplier (1.0 = normal, 0.5 = half speed, 2.0 = double speed)
	"""
	# Find an available audio player
	var player := _get_available_player()
	if not player:
		push_warning("[AUDIO_MANAGER] No available SFX players! Increase MAX_SFX_PLAYERS or wait.")
		return

	# Try to load the sound
	var sound_path := "res://assets/audio/sfx/%s.wav" % sound_name
	if not ResourceLoader.exists(sound_path):
		# Try .ogg extension
		sound_path = "res://assets/audio/sfx/%s.ogg" % sound_name
		if not ResourceLoader.exists(sound_path):
			# Try .mp3 extension
			sound_path = "res://assets/audio/sfx/%s.mp3" % sound_name
			if not ResourceLoader.exists(sound_path):
				push_warning("[AUDIO_MANAGER] Sound file not found: %s" % sound_name)
				return

	var sound := load(sound_path) as AudioStream
	if not sound:
		push_warning("[AUDIO_MANAGER] Failed to load sound: %s" % sound_path)
		return

	# Play the sound
	player.stream = sound
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

func play_sfx_3d(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0, max_distance: float = 20.0) -> void:
	"""Play a 3D positioned sound effect.

	Args:
		sound_name: Name of the sound file (without extension)
		position: 3D position where the sound originates
		volume_db: Volume adjustment in decibels
		pitch_scale: Pitch multiplier
		max_distance: Maximum distance at which sound can be heard
	"""
	# Try to load the sound
	var sound_path := "res://assets/audio/sfx/%s.wav" % sound_name
	if not ResourceLoader.exists(sound_path):
		sound_path = "res://assets/audio/sfx/%s.ogg" % sound_name
		if not ResourceLoader.exists(sound_path):
			sound_path = "res://assets/audio/sfx/%s.mp3" % sound_name
			if not ResourceLoader.exists(sound_path):
				push_warning("[AUDIO_MANAGER] Sound file not found: %s" % sound_name)
				return

	var sound := load(sound_path) as AudioStream
	if not sound:
		push_warning("[AUDIO_MANAGER] Failed to load sound: %s" % sound_path)
		return

	# Create a temporary 3D audio player
	var player := AudioStreamPlayer3D.new()
	player.stream = sound
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = max_distance
	player.bus = BUS_SFX
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

	# Add to scene at position
	if get_tree().current_scene:
		get_tree().current_scene.add_child(player)
		player.global_position = position
		player.play()

		# Auto-delete when finished
		player.finished.connect(func(): player.queue_free())
	else:
		player.queue_free()

func _get_available_player() -> AudioStreamPlayer:
	"""Get an available audio player from the pool."""
	for player in _sfx_players:
		if not player.playing:
			return player
	return null

func _apply_volume_settings() -> void:
	"""Apply volume settings to audio buses."""
	var master_idx := AudioServer.get_bus_index(BUS_MASTER)
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	var sfx_idx := AudioServer.get_bus_index(BUS_SFX)

	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))

func set_master_volume(volume: float) -> void:
	"""Set master volume (0.0 to 1.0)."""
	master_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()

func set_music_volume(volume: float) -> void:
	"""Set music volume (0.0 to 1.0)."""
	music_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()

func set_sfx_volume(volume: float) -> void:
	"""Set sound effects volume (0.0 to 1.0)."""
	sfx_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()
