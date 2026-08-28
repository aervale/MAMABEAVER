# =============================================================================
# game_sfx.gd — original, procedurally synthesised one-shot game sounds.
#
# The project previously had only background music. These four cues are built
# once into 16-bit mono AudioStreamWAV resources at startup, so they need no
# downloaded assets or third-party licence:
#   trigger_shot  — short descending energy zap
#   beaver_caught — bright three-note pickup chirp
#   mit_deposit   — cargo-release whoosh with mechanical pulses
#   victory       — ascending fanfare and resolved major chord
#
# Public play_* methods are called by spaceship_flight.gd. Play counters make
# event wiring deterministic to validate in a headless test where no physical
# audio output exists.
# =============================================================================
extends Node
class_name GameSFX

const SAMPLE_RATE := 32000
const SHOT := &"trigger_shot"
const CAUGHT := &"beaver_caught"
const DEPOSIT := &"mit_deposit"
const VICTORY := &"victory"

var _players: Dictionary = {}
var _play_counts: Dictionary = {
	SHOT: 0,
	CAUGHT: 0,
	DEPOSIT: 0,
	VICTORY: 0,
}


func _ready() -> void:
	_add_player(SHOT, 0.28, -4.0, 4, 1101)
	_add_player(CAUGHT, 0.62, -3.0, 3, 2202)
	_add_player(DEPOSIT, 1.25, -3.0, 2, 3303)
	_add_player(VICTORY, 2.4, -2.0, 1, 4404)


func _add_player(
	cue: StringName,
	duration: float,
	volume_db: float,
	polyphony: int,
	seed: int
) -> void:
	var player := AudioStreamPlayer.new()
	player.name = String(cue).to_pascal_case()
	player.stream = _synthesise(cue, duration, seed)
	player.volume_db = volume_db
	player.max_polyphony = polyphony
	add_child(player)
	_players[cue] = player


func _synthesise(cue: StringName, duration: float, seed: int) -> AudioStreamWAV:
	var sample_count := int(ceil(duration * SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	for index in sample_count:
		var time := float(index) / float(SAMPLE_RATE)
		var sample := _sample_cue(cue, time, duration, rng)
		var value := clampi(int(round(clampf(sample, -1.0, 1.0) * 32767.0)), -32768, 32767)
		pcm.encode_s16(index * 2, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


func _sample_cue(
	cue: StringName,
	time: float,
	duration: float,
	rng: RandomNumberGenerator
) -> float:
	var progress := clampf(time / duration, 0.0, 1.0)
	match cue:
		SHOT:
			# Integral of a linear 1320 -> 190 Hz chirp gives a clean laser sweep.
			var chirp_rate := (190.0 - 1320.0) / duration
			var phase := TAU * (1320.0 * time + 0.5 * chirp_rate * time * time)
			var envelope := minf(time / 0.008, 1.0) * pow(1.0 - progress, 2.2)
			var spark := rng.randf_range(-1.0, 1.0) * 0.16 * (1.0 - progress)
			return envelope * (0.62 * sin(phase) + 0.22 * sin(phase * 1.97) + spark)
		CAUGHT:
			var note_index := mini(int(progress * 3.0), 2)
			var frequencies := [523.25, 659.25, 880.0]
			var local := fposmod(time, duration / 3.0)
			var note_progress := local / (duration / 3.0)
			var bell := sin(PI * note_progress) * pow(1.0 - progress * 0.2, 2.0)
			var phase := TAU * float(frequencies[note_index]) * time
			return bell * (0.5 * sin(phase) + 0.16 * sin(phase * 2.01))
		DEPOSIT:
			var release := pow(1.0 - progress, 1.25)
			var whoosh := rng.randf_range(-1.0, 1.0) * 0.16 * sin(PI * progress)
			var motor_frequency := lerpf(240.0, 82.0, progress)
			var motor := sin(TAU * motor_frequency * time) * 0.18 * release
			var pulses := 0.0
			for pulse_time in [0.12, 0.38, 0.66, 0.92]:
				var since := time - float(pulse_time)
				if since >= 0.0:
					pulses += sin(TAU * 310.0 * since) * exp(-since * 15.0) * 0.24
			return (whoosh + motor + pulses) * minf(time / 0.015, 1.0)
		VICTORY:
			var fanfare := 0.0
			var starts := [0.0, 0.28, 0.56, 0.84]
			var frequencies := [523.25, 659.25, 783.99, 1046.5]
			for note in starts.size():
				var since := time - float(starts[note])
				if since >= 0.0:
					fanfare += sin(TAU * float(frequencies[note]) * since) * exp(-since * 1.45) * 0.19
			# A quiet major chord holds after the climb so the cue feels resolved.
			if time >= 0.84:
				var chord_time := time - 0.84
				var chord_envelope := exp(-chord_time * 0.8)
				for frequency in [523.25, 659.25, 783.99]:
					fanfare += sin(TAU * float(frequency) * chord_time) * chord_envelope * 0.075
			return fanfare * minf(time / 0.01, 1.0) * minf((duration - time) / 0.18, 1.0)
	return 0.0


func play_trigger_shot() -> void:
	_play(SHOT)


func play_beaver_caught() -> void:
	_play(CAUGHT)


func play_mit_deposit() -> void:
	_play(DEPOSIT)


func play_victory() -> void:
	_play(VICTORY)


func _play(cue: StringName) -> void:
	var player := _players.get(cue) as AudioStreamPlayer
	if player == null:
		return
	_play_counts[cue] = int(_play_counts.get(cue, 0)) + 1
	player.play()


func has_all_sounds() -> bool:
	for cue in [SHOT, CAUGHT, DEPOSIT, VICTORY]:
		var player := _players.get(cue) as AudioStreamPlayer
		if player == null or player.stream == null or player.stream.get_length() <= 0.1:
			return false
	return true


func get_play_count(cue: StringName) -> int:
	return int(_play_counts.get(cue, 0))
