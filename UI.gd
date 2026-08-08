extends Control

const MAX_BOMBS: int = 5

@onready var bomb_p1: Label = $BombP1
@onready var bomb_p2: Label = $BombP2
@onready var score_p1: Label = $ScoreP1
@onready var score_p2: Label = $ScoreP2
@onready var timer_label: Label = $TimerLabel
@onready var result_label: Label = $ResultPanel/VBox/ResultLabel
@onready var result_panel: PanelContainer = $ResultPanel
@onready var retry_button: Button = $ResultPanel/VBox/BtnRow/BtnRetry
@onready var title_button: Button = $ResultPanel/VBox/BtnRow/BtnTitle
@onready var goal_pop: Label = $GoalPop
@onready var countdown_label: Label = $CountdownLabel

var game: Node2D
var _last_countdown: int = -1
var _countdown_tween: Tween
var _timer_last_sec: int = -1
var _bomb_p1_last: int = -1
var _bomb_p2_last: int = -1
var _score_tween_1: Tween
var _score_tween_2: Tween
var _score_p1_target: int = 0
var _score_p2_target: int = 0
var _goal_tween: Tween

func _ready() -> void:
	# Node2D の子としてインスタンス化された場合でも全画面に広げる
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# HUD がふわっと現れる
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.4)
	# 結果画面のボタンの手触り感
	UIJuice.setup_button(retry_button)
	UIJuice.setup_button(title_button)

func init_ui(game_node: Node2D) -> void:
	game = game_node

func update_timer(time_left: float) -> void:
	var seconds := maxi(int(ceil(time_left)), 0)
	var minutes := int(seconds / 60.0)
	seconds = seconds % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	# 秒が変わるたびに小さく弾んで「時を刻む」手触り感
	if seconds != _timer_last_sec:
		_timer_last_sec = seconds
		timer_label.scale = Vector2(1.12, 1.12)
		var tw := timer_label.create_tween()
		tw.tween_property(timer_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 残り10秒で赤く点滅
	if time_left <= 10.0:
		var on := int(time_left * 3.0) % 2 == 0
		timer_label.add_theme_color_override("font_color", Color(1, 0.25, 0.25) if on else Color(1, 0.75, 0.75))
	else:
		timer_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_update_countdown(time_left)

func update_score(s1: int, s2: int) -> void:
	# 数字がなめらかにカウントアップする
	_animate_number(score_p1, s1, true)
	_animate_number(score_p2, s2, false)

func _animate_number(label: Label, target: int, is_p1: bool) -> void:
	# 直前の目標値から滑らかにアニメ（連続ゴールでも数字が飛ばない）
	var current: int = _score_p1_target if is_p1 else _score_p2_target
	if current == target:
		return
	if is_p1:
		_score_p1_target = target
		if _score_tween_1 and _score_tween_1.is_valid():
			_score_tween_1.kill()
	else:
		_score_p2_target = target
		if _score_tween_2 and _score_tween_2.is_valid():
			_score_tween_2.kill()
	var from_f: float = float(current)
	var tw := label.create_tween()
	tw.tween_method(func(v: float) -> void: label.text = str(int(v)), from_f, float(target), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_p1:
		_score_tween_1 = tw
	else:
		_score_tween_2 = tw

func _update_countdown(time_left: float) -> void:
	# 残り5秒から画面中央にカウントダウンを表示（数字が変わるときにトゥイーン）
	if time_left > 5.0:
		if countdown_label.visible:
			countdown_label.visible = false
		_last_countdown = -1
		return
	var secs := int(ceil(time_left))
	if secs < 1:
		countdown_label.visible = false
		return
	if secs == _last_countdown:
		return
	_last_countdown = secs
	countdown_label.text = str(secs)
	countdown_label.visible = true
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()
	# 数字チェンジ演出: 大きく出現→通常サイズに収束→フェードアウト
	countdown_label.scale = Vector2(2.0, 2.0)
	countdown_label.modulate.a = 1.0
	_countdown_tween = countdown_label.create_tween()
	_countdown_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_countdown_tween.tween_property(countdown_label, "modulate:a", 0.0, 0.45).set_delay(0.5)
	_countdown_tween.tween_callback(func() -> void: countdown_label.visible = false)

func pop_score(side: int) -> void:
	# side: -1 = 赤(1P)に得点, +1 = 青(2P)に得点
	var label := score_p1 if side < 0 else score_p2
	var team := Color(1, 0.35, 0.35) if side < 0 else Color(0.4, 0.6, 1)
	var gold := Color(1, 0.9, 0.35)
	# 1) 数字のポップ（拡大→通常）
	label.scale = Vector2(1.8, 1.8)
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 2) 数字の色フラッシュ（白→チーム色）と枠のゴールド発光
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", gold)
	var restore := get_tree().create_timer(0.22)
	restore.timeout.connect(func() -> void:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", team)
			label.add_theme_color_override("font_outline_color", Color(0.2, 0.05, 0.05) if side < 0 else Color(0.05, 0.1, 0.3)))
	# 3) 数字の周囲にチームカラーのグロー
	var c: Vector2 = label.global_position + label.size * 0.5
	var glow := TextureRect.new()
	glow.texture = load("res://assets/fx_glow.png")
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.position = c - Vector2(80, 80)
	glow.size = Vector2(160, 160)
	glow.pivot_offset = Vector2(80, 80)
	glow.modulate = Color(team.r, team.g, team.b, 0.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	# 数字の後ろに描画されるよう、ラベルの直前の兄弟順に移動（数字を霞ませない）
	move_child(glow, label.get_index())
	var gtw := glow.create_tween().set_parallel(true)
	gtw.tween_property(glow, "scale", Vector2(1.7, 1.7), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gtw.tween_property(glow, "modulate:a", 0.8, 0.1)
	gtw.chain().tween_property(glow, "modulate:a", 0.0, 0.5)
	gtw.chain().tween_callback(glow.queue_free)
	# 4) 数字の上に浮遊する「+1」
	var plus := Label.new()
	plus.text = "+1"
	plus.add_theme_font_size_override("font_size", 44)
	plus.add_theme_color_override("font_color", gold)
	plus.add_theme_color_override("font_outline_color", Color(0.4, 0.15, 0.05))
	plus.add_theme_constant_override("outline_size", 8)
	plus.position = c - Vector2(50, 90)
	plus.size = Vector2(100, 50)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plus)
	var ptw := plus.create_tween().set_parallel(true)
	ptw.tween_property(plus, "position:y", c.y - 150, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ptw.tween_property(plus, "modulate:a", 0.0, 0.55).set_delay(0.2)
	ptw.chain().tween_callback(plus.queue_free)

func update_bomb_count(b1: int, b2: int) -> void:
	_update_bomb_label(bomb_p1, b1, _bomb_p1_last)
	_update_bomb_label(bomb_p2, b2, _bomb_p2_last)
	_bomb_p1_last = b1
	_bomb_p2_last = b2

func _update_bomb_label(label: Label, b: int, prev: int) -> void:
	label.text = "●".repeat(b) + "○".repeat(MAX_BOMBS - b)
	if prev == -1 or prev == b:
		return
	# 残数が変わるときに弾む
	label.scale = Vector2(1.35, 1.35)
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func show_goal_pop(winner_text: String, side: int = 0) -> void:
	# side: -1 = 赤(1P)得点 → 画面左側に赤系のGOAL, +1 = 青(2P)得点 → 画面右側に青系のGOAL, 0 = ニュートラル → 中央・ゴールド
	var is_team := side != 0
	var fill := Color(1, 0.9, 0.3)          # ニュートラル: ゴールド
	var outline := Color(0.4, 0.1, 0.05)    # ニュートラル: 焦げ茶
	var glow_col := Color(1, 0.85, 0.35)
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	var target_rot := 0.0
	if side < 0:
		# 赤: 明るいレッド + 白系の縁取り + 黒シャドウで暗いフィールドに埋もれないように
		fill = Color(1, 0.36, 0.28)
		outline = Color(0.97, 0.92, 0.94)
		glow_col = Color(1, 0.4, 0.3)
		center = Vector2(size.x * 0.20, size.y * 0.40)
		target_rot = deg_to_rad(45.0)
	elif side > 0:
		# 青: 明るいブルー + 白系の縁取り
		fill = Color(0.5, 0.7, 1)
		outline = Color(0.95, 0.97, 1)
		glow_col = Color(0.5, 0.72, 1)
		center = Vector2(size.x * 0.80, size.y * 0.40)
		target_rot = deg_to_rad(-45.0)

	goal_pop.text = winner_text
	goal_pop.add_theme_color_override("font_color", fill)
	goal_pop.add_theme_color_override("font_outline_color", outline)
	goal_pop.add_theme_constant_override("outline_size", 20 if is_team else 18)
	# 視認性: フィールドと同系色に埋もれないよう黒いドロップシャドウを敷く
	goal_pop.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	goal_pop.add_theme_constant_override("shadow_offset_x", 5)
	goal_pop.add_theme_constant_override("shadow_offset_y", 5)
	# 絶対配置に切り替えて、指定位置を中心に配置（回転は文字の中心を支点に）
	goal_pop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	goal_pop.position = center - goal_pop.size * 0.5
	goal_pop.pivot_offset = goal_pop.size * 0.5
	goal_pop.rotation = target_rot
	goal_pop.scale = Vector2.ONE
	goal_pop.modulate.a = 1.0
	goal_pop.visible = true

	# トゥイーン: ポップイン → 回転の揺れ → 脈動 → フェードアウト
	# 回転の微揺れは赤=時計回り(+3°)、青=反時計回り(-3°)で左右対称にする
	var wobble_sign := -1.0 if side > 0 else 1.0
	if _goal_tween and _goal_tween.is_valid():
		_goal_tween.kill()
	var tw := goal_pop.create_tween()
	tw.tween_property(goal_pop, "scale", Vector2(1.16, 1.16), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(goal_pop, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(goal_pop, "rotation", target_rot + wobble_sign * deg_to_rad(3.0), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(goal_pop, "rotation", target_rot, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(goal_pop, "scale", Vector2(1.05, 1.05), 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.1)
	tw.tween_property(goal_pop, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(goal_pop, "modulate:a", 0.0, 0.4).set_delay(0.85)
	tw.tween_callback(func() -> void: goal_pop.visible = false)
	_goal_tween = tw

	# チーム得点時はチームカラーのグローを背後に敷く（視認性と臨場感）
	if is_team:
		var glow := TextureRect.new()
		glow.texture = load("res://assets/fx_glow.png")
		glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var gsize := Vector2(520, 520)
		glow.position = center - gsize * 0.5
		glow.size = gsize
		glow.pivot_offset = gsize * 0.5
		glow.modulate = Color(glow_col.r, glow_col.g, glow_col.b, 0.0)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)
		# 文字の後ろに描画されるよう、GOAL文字の直前の兄弟順に移動
		move_child(glow, goal_pop.get_index())
		var gtw := glow.create_tween().set_parallel(true)
		gtw.tween_property(glow, "modulate:a", 0.5, 0.16)
		gtw.tween_property(glow, "scale", Vector2(1.3, 1.3), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		gtw.chain().tween_property(glow, "modulate:a", 0.0, 0.5).set_delay(0.9)
		gtw.chain().tween_callback(glow.queue_free)

func show_result(text: String) -> void:
	result_label.text = text
	result_panel.visible = true
	countdown_label.visible = false
	# 必ず画面中央に配置（サイズは維持）
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	# パネル中央を支点にポップイン（左上起点の拡大にならないように）
	result_panel.pivot_offset = result_panel.size * 0.5
	result_panel.scale = Vector2(0.6, 0.6)
	var tw := result_panel.create_tween()
	tw.tween_property(result_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# お祝いの紙吹雪
	_spawn_confetti()

func _spawn_confetti() -> void:
	# 画面中央上部から金色の紙吹雪が降り注ぐ
	var confetti := CPUParticles2D.new()
	confetti.texture = load("res://assets/fx_spark.png")
	confetti.amount = 70
	confetti.lifetime = 1.8
	confetti.one_shot = true
	confetti.explosiveness = 1.0
	confetti.direction = Vector2(0, 1)
	confetti.spread = 30.0
	confetti.initial_velocity_min = 180.0
	confetti.initial_velocity_max = 480.0
	confetti.gravity = Vector2(0, 420)
	confetti.scale_amount_min = 1.5
	confetti.scale_amount_max = 3.2
	confetti.color = Color(1, 0.88, 0.4)
	confetti.z_index = 50
	confetti.position = Vector2(size.x * 0.5, -20.0)
	add_child(confetti)
	confetti.emitting = true
	var t := get_tree().create_timer(2.2)
	t.timeout.connect(confetti.queue_free)
