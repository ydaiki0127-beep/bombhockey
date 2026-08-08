class_name UIJuice
extends RefCounted

## UI共通の「手触り感」演出: ホバーでふわっと拡大 / 押すとぐっと縮む / 離すと弾んで戻る / クリック音

const CLICK_SOUND := "res://assets/se_place.wav"

static var _player: AudioStreamPlayer

static func setup_button(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2.ONE
	# ホバー: ふわっと拡大 + 軽いチック音
	btn.mouse_entered.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5
		_play(1.4, -20.0)
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	# ホバー解除: 元に戻る
	btn.mouse_exited.connect(func() -> void:
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	# 押す: ぐっと縮む
	btn.button_down.connect(func() -> void:
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(0.93, 0.93), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	# 実際にクリックしたときだけクリック音
	btn.pressed.connect(func() -> void: _play(1.05, -14.0))
	# 離す: 弾んで元に戻る
	btn.button_up.connect(func() -> void:
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

static func _play(pitch: float, vol: float) -> void:
	var p := _get_player()
	p.pitch_scale = pitch
	p.volume_db = vol
	p.play()

static func _get_player() -> AudioStreamPlayer:
	if _player == null or not is_instance_valid(_player):
		var tree := Engine.get_main_loop() as SceneTree
		_player = AudioStreamPlayer.new()
		_player.stream = load(CLICK_SOUND)
		_player.bus = AudioSettings.BUS_SE
		_player.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(_player)
	return _player
