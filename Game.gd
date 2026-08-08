extends Node2D

@export var is_2p: bool = false
@export var difficulty: String = "ふつう"

const PuckScene := preload("res://Puck.tscn")
const BombScene := preload("res://Bomb.tscn")
const PauseOverlayScene := preload("res://pause_overlay.gd")
const MAX_BOMBS: int = 5
const PUCK_SPAWN_CLEARANCE: float = 160.0

const BG_PATH := "res://assets/arena_background.png"
const HUD_HEIGHT := 92.0

var pucks: Array[RigidBody2D] = []
var bombs_p1: Array[Node2D] = []
var bombs_p2: Array[Node2D] = []
var score_p1: int = 0
var score_p2: int = 0
var time_left: float = 120.0
var game_over: bool = false
# 残り時間マークでパックを追加 [残り秒, 追加数]
var _puck_spawn_marks: Array = [[60.0, 1], [50.0, 1], [40.0, 1], [30.0, 2], [25.0, 2], [20.0, 3], [15.0, 4], [10.0, 5]]
var _spawn_mark_idx: int = 0

var bombs_remaining_p1: int = MAX_BOMBS
var bombs_remaining_p2: int = MAX_BOMBS

# アリーナ（背景画像の実寸からランタイム導出）
var arena_scale: float = 1.0
var half_w: float = 500.0
var half_h: float = 280.0
var goal_half_h: float = 90.0

# 画面シェイク（カメラオフセットで実現。アリーナ自体を揺らすと物理ボディの親が動き、
# パック（RigidBody2D）の統合が毎フレーム上書きされて止まってしまうため）
var camera: Camera2D
var shake_amp: float = 0.0
var shake_time: float = 0.0

# ヒットストップ（パックがボムに直接衝突したときのごく短い停止）
const HIT_STOP_COOLDOWN_MS: int = 1000
var _hit_stop_active: bool = false
var _last_hit_stop_ms: int = -100000

var com_difficulty_settings := {
	# かんたん: 反応が遅く、置き場所もほぼランダム
	"かんたん": {"timing_variance": 0.35, "pos_variance_px": 140.0, "radius_px": 220.0},
	"ふつう": {"timing_variance": 0.15, "pos_variance_px": 60.0, "radius_px": 100.0},
	# むずかしい: 反応が非常に速く、精度も高い
	"むずかしい": {"timing_variance": 0.03, "pos_variance_px": 20.0, "radius_px": 50.0},
}

@onready var ui: Control = $UILayer/UI
@onready var arena: Node2D = $Arena
@onready var arena_bg: Sprite2D = $Arena/ArenaBG
@onready var com_timer: Timer = $ComTimer
@onready var bgm: AudioStreamPlayer = $BGM
@onready var goal_se: AudioStreamPlayer2D = $GoalSE
@onready var goal_se2: AudioStreamPlayer2D = $GoalSE2
@onready var puck_add_se: AudioStreamPlayer2D = $PuckAddSE

var goal_left: Area2D
var goal_right: Area2D
var overlay: ColorRect
var light_strips: Array[ColorRect] = []
var pause_overlay: Control

func _ready() -> void:
	add_to_group("game")
	ui.init_ui(self)
	ui.update_bomb_count(bombs_remaining_p1, bombs_remaining_p2)
	ui.update_score(0, 0)
	_setup_arena()
	com_timer.timeout.connect(_on_com_timer_timeout)
	ui.retry_button.pressed.connect(_on_retry_pressed)
	ui.title_button.pressed.connect(_on_title_pressed)
	if is_2p:
		com_timer.stop()
	else:
		com_timer.start()
	goal_se.bus = AudioSettings.BUS_SE
	goal_se2.bus = AudioSettings.BUS_SE
	puck_add_se.bus = AudioSettings.BUS_SE
	# ポーズオーバーレイ（Esc で開閉し、ツリー全体を一時停止する）
	pause_overlay = PauseOverlayScene.new()
	pause_overlay.setup(self)
	$UILayer.add_child(pause_overlay)
	_spawn_initial_puck()
	_start_bgm()
	ui.show_goal_pop("GO!")

# ================= アリーナ構築 =================

func _setup_arena() -> void:
	var tex: Texture2D = load(BG_PATH)
	var img_size := tex.get_size()  # 1287 x 680
	var vp := get_viewport().get_visible_rect().size
	# HUDの下に収まるよう画像をスケール（アスペクト維持）
	var avail_h := vp.y - HUD_HEIGHT - 24.0
	var avail_w := vp.x - 32.0
	arena_scale = minf(avail_h / img_size.y, avail_w / img_size.x)
	half_w = img_size.x * arena_scale * 0.5
	half_h = img_size.y * arena_scale * 0.5
	goal_half_h = half_h * 0.32
	arena_bg.texture = tex
	arena_bg.scale = Vector2(arena_scale, arena_scale)
	arena.position = Vector2(vp.x * 0.5, HUD_HEIGHT + half_h + 16.0)
	_build_collision()
	_build_light_frame()
	# 画面シェイク用カメラ（物理を揺らさず、描画だけを揺らす）
	var cam := Camera2D.new()
	cam.position = Vector2(vp.x * 0.5, vp.y * 0.5)
	add_child(cam)
	cam.make_current()
	camera = cam

func _build_collision() -> void:
	var wall_h := 16.0
	# 上下の壁（全幅）
	_add_wall(Vector2(0, -half_h - wall_h * 0.5), Vector2(half_w * 2.0 + 60.0, wall_h))
	_add_wall(Vector2(0, half_h + wall_h * 0.5), Vector2(half_w * 2.0 + 60.0, wall_h))
	# 左右の壁（ゴール開口を除く上下2分割）
	var seg_len := half_h - goal_half_h
	var l_top_y := -(half_h + goal_half_h) * 0.5
	var l_bot_y := (half_h + goal_half_h) * 0.5
	for y in [l_top_y, l_bot_y]:
		_add_wall(Vector2(-half_w - wall_h * 0.5, y), Vector2(wall_h, seg_len + 60.0))
		_add_wall(Vector2(half_w + wall_h * 0.5, y), Vector2(wall_h, seg_len + 60.0))
	# ゴール領域（壁の外側）
	goal_left = _add_goal(Vector2(-half_w - 30.0, 0.0), Color(1, 0.35, 0.35, 0.5))
	goal_right = _add_goal(Vector2(half_w + 30.0, 0.0), Color(0.4, 0.6, 1, 0.5))
	goal_left.body_entered.connect(_on_goal_left_body_entered)
	goal_right.body_entered.connect(_on_goal_right_body_entered)
	# ゴール口の視覚マーク（どこを狙うか分かるように）
	var mark_l := ColorRect.new()
	mark_l.position = Vector2(-half_w - 4.0, -goal_half_h)
	mark_l.size = Vector2(8.0, goal_half_h * 2.0)
	mark_l.color = Color(1, 0.4, 0.4, 0.55)
	mark_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(mark_l)
	var mark_r := ColorRect.new()
	mark_r.position = Vector2(half_w - 4.0, -goal_half_h)
	mark_r.size = Vector2(8.0, goal_half_h * 2.0)
	mark_r.color = Color(0.45, 0.65, 1, 0.55)
	mark_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(mark_r)
	# ゴール口に黄色中心の明確なマーカー
	_add_goal_marker(true)
	_add_goal_marker(false)

func _add_goal_marker(is_left: bool) -> void:
	# ゴール口に黄色中心の明確なしるし（発光ライン + 矢印 + 脈動）
	var cx := -half_w if is_left else half_w
	var dir := -1.0 if is_left else 1.0
	# 発光ライン（口の直前・黄色）
	var line := ColorRect.new()
	line.size = Vector2(6.0, goal_half_h * 2.0)
	line.position = Vector2(cx + dir * 3.0, -goal_half_h)
	line.color = Color(1, 0.88, 0.3, 0.95)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(line)
	# 淡いハロー（ぼかし感）
	var halo := ColorRect.new()
	halo.size = Vector2(16.0, goal_half_h * 2.0 + 20.0)
	halo.position = Vector2(cx + dir * 3.0 - 8.0, -goal_half_h - 10.0)
	halo.color = Color(1, 0.9, 0.35, 0.2)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(halo)
	# 矢印（ゴール方向を指すチブロン）
	var vx := cx + dir * 26.0
	var L := 30.0
	var h1 := 22.0
	var ang := rad_to_deg(atan2(h1, L))
	for k in [-1.0, 1.0]:
		var bar := ColorRect.new()
		bar.size = Vector2(L, 8.0)
		var mid := Vector2(vx - dir * L * 0.5, k * h1 * 0.5)
		bar.position = mid - Vector2(L * 0.5, 4.0)
		bar.pivot_offset = Vector2(L * 0.5, 4.0)
		bar.rotation = deg_to_rad(ang * dir * -k)
		bar.color = Color(1, 0.92, 0.4, 0.95)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arena.add_child(bar)
	# 黄色ラインをゆっくり脈動させて存在を強調
	var tw := line.create_tween().set_loops()
	tw.tween_property(line, "color:a", 0.55, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(line, "color:a", 0.95, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _add_wall(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	arena.add_child(body)

func _add_goal(pos: Vector2, _tint: Color) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60.0, goal_half_h * 2.0)
	shape.shape = rect
	area.add_child(shape)
	arena.add_child(area)
	return area

func _build_light_frame() -> void:
	# イルミネーション: テーブル外周のLED枠 + 全面フラッシュ
	var strips := [
		Vector2(0, -half_h - 22.0), Vector2(half_w * 2.0 + 60.0, 10.0),
		Vector2(0, half_h + 22.0), Vector2(half_w * 2.0 + 60.0, 10.0),
		Vector2(-half_w - 22.0, 0), Vector2(10.0, half_h * 2.0 + 60.0),
		Vector2(half_w + 22.0, 0), Vector2(10.0, half_h * 2.0 + 60.0),
	]
	for i in range(4):
		var strip := ColorRect.new()
		strip.position = strips[i * 2] - strips[i * 2 + 1] * 0.5
		strip.size = strips[i * 2 + 1]
		strip.color = Color(1, 1, 1, 0.05)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arena.add_child(strip)
		light_strips.append(strip)
	overlay = ColorRect.new()
	overlay.position = Vector2(-half_w, -half_h)
	overlay.size = Vector2(half_w * 2.0, half_h * 2.0)
	overlay.color = Color(1, 1, 1, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(overlay)

# ================= パック =================

func _spawn_initial_puck() -> void:
	if game_over:
		return
	_spawn_puck(Vector2(0, 0))

func _spawn_puck(pos: Vector2) -> void:
	var puck := PuckScene.instantiate()
	puck.position = pos
	_aim_puck_random(puck)
	arena.add_child(puck)
	pucks.append(puck)

func _spawn_pucks(count: int) -> void:
	# ゴール後の再生成・時間マークの追加用。既存パックと重ならない位置に出す
	if game_over:
		return
	var positions := _find_puck_spawn_positions(count)
	for pos in positions:
		_spawn_puck(pos)

func _find_puck_spawn_positions(count: int) -> Array[Vector2]:
	# 基本は中央(X=0)。他のパックと重なる場合は同じX軸上の別のYにずらす
	var positions: Array[Vector2] = []
	var taken: Array[Vector2] = []
	for p in pucks:
		taken.append(p.position)
	# Y軸上の候補（中央から上下に分散。フィールド内に収める）
	var cand_y: Array[float] = [0.0]
	var step := half_h * 0.3
	var max_y := half_h - 60.0
	var k := 1
	while step * k <= max_y and k < 12:
		cand_y.append(step * k)
		cand_y.append(-step * k)
		k += 1
	for i in range(count):
		var best := Vector2(0, 0)
		var best_clear := -1.0
		for y in cand_y:
			var pos := Vector2(0, y)
			var min_d := 1e9
			for other in taken:
				min_d = minf(min_d, pos.distance_to(other))
			if min_d > best_clear:
				best_clear = min_d
				best = pos
			if min_d >= PUCK_SPAWN_CLEARANCE:
				break
		if best_clear < PUCK_SPAWN_CLEARANCE:
			# 空きがない場合: まずY軸上(X=0)で最も空いた場所を探す
			var trial_best := best
			var trial_clear := best_clear
			for t in range(10):
				var trial := Vector2(0, randf_range(-half_h + 90, half_h - 90))
				var min_d := 1e9
				for other in taken:
					min_d = minf(min_d, trial.distance_to(other))
				if min_d > trial_clear:
					trial_clear = min_d
					trial_best = trial
			# Y軸上が厳しい場合のみフィールド全体から探す
			if trial_clear < PUCK_SPAWN_CLEARANCE * 0.5:
				for t in range(10):
					var trial := Vector2(randf_range(-half_w + 90, half_w - 90), randf_range(-half_h + 90, half_h - 90))
					var min_d := 1e9
					for other in taken:
						min_d = minf(min_d, trial.distance_to(other))
					if min_d > trial_clear:
						trial_clear = min_d
						trial_best = trial
			best = trial_best
		positions.append(best)
		taken.append(best)
	return positions

func _aim_puck_random(puck: RigidBody2D) -> void:
	var angle := deg_to_rad(randf_range(-60, 60))
	if randf() > 0.5:
		angle += deg_to_rad(180)
	puck.linear_velocity = Vector2(cos(angle), sin(angle)) * randf_range(300, 600)

# ================= メインループ =================

func _process(delta: float) -> void:
	_update_shake(delta)
	if game_over:
		return
	time_left -= delta
	ui.update_timer(time_left)
	_check_puck_spawns()
	if time_left <= 0:
		_end_game()

func _check_puck_spawns() -> void:
	# 残り時間のマークを切るたびにパックを追加（60:+1, 50:+1, 40:+1, 30:+2, 25:+2, 20:+3, 15:+4, 10:+5）
	var spawned := false
	while _spawn_mark_idx < _puck_spawn_marks.size() and time_left <= _puck_spawn_marks[_spawn_mark_idx][0]:
		_spawn_pucks(int(_puck_spawn_marks[_spawn_mark_idx][1]))
		_spawn_mark_idx += 1
		spawned = true
	# パックが新しく追加されたタイミングで効果音（button23.mp3）を鳴らす
	if spawned:
		puck_add_se.play()

func _update_shake(delta: float) -> void:
	# ヒットストップ中（time_scale=0）はシェイクも止めて完全停止の見た目にする
	if Engine.time_scale == 0.0:
		return
	if shake_time > 0.0:
		shake_time -= delta
		var k := maxf(shake_time / 0.4, 0.0)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amp * k
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO

func add_shake(amp: float) -> void:
	shake_amp = maxf(shake_amp, amp)
	shake_time = 0.4

func _start_bgm() -> void:
	var stream: AudioStream = load("res://assets/bgm1.wav")
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = -1
	bgm.stream = stream
	bgm.bus = AudioSettings.BUS_BGM
	bgm.play()

func _exit_tree() -> void:
	# ヒットストップ中にシーンが切り替わっても時間を戻す
	Engine.time_scale = 1.0
	# ポーズ中にシーンが切り替わってもツリーが止まったままにならないようにする
	get_tree().paused = false

func hit_stop(duration: float) -> void:
	# 一瞬だけ時間を止める（パックがボムに直接衝突したときのみ呼ばれる）
	if _hit_stop_active or game_over:
		return
	# 連鎖爆発などで立て続けに発動して「止まり続けている」ように見えるのを防ぐ最短間隔
	var now := Time.get_ticks_msec()
	if now - _last_hit_stop_ms < HIT_STOP_COOLDOWN_MS:
		return
	_last_hit_stop_ms = now
	_hit_stop_active = true
	# フリーズ中は視点を基準位置に戻して完全停止の見た目にする
	camera.offset = Vector2.ZERO
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_stop_active = false

func _end_game() -> void:
	game_over = true
	com_timer.stop()
	var result_text := ""
	if score_p1 > score_p2:
		result_text = "1P 勝ち！"
	elif score_p2 > score_p1:
		result_text = "2P 勝ち！"
	else:
		result_text = "ひきわけ"
	ui.show_result(result_text)
	_celebrate_goal(1 if score_p2 > score_p1 else -1 if score_p1 > score_p2 else 0)

# ================= ボム =================

func place_bomb_p1(pos: Vector2) -> void:
	if bombs_remaining_p1 <= 0:
		return
	if pos.x > 0:
		return  # 1P は左側（x<0）のみ
	_spawn_bomb(pos, true)

func place_bomb_p2(pos: Vector2) -> void:
	if bombs_remaining_p2 <= 0:
		return
	if pos.x < 0:
		return  # 2P は右側（x>0）のみ
	_spawn_bomb(pos, false)

func _spawn_bomb(pos: Vector2, is_p1: bool) -> void:
	var bomb = BombScene.instantiate()
	bomb.is_p1 = is_p1
	bomb.position = _clamp_to_arena(pos)
	bomb.exploded.connect(_on_bomb_exploded.bind(is_p1))
	arena.add_child(bomb)
	if is_p1:
		bombs_p1.append(bomb)
		bombs_remaining_p1 -= 1
	else:
		bombs_p2.append(bomb)
		bombs_remaining_p2 -= 1
	ui.update_bomb_count(bombs_remaining_p1, bombs_remaining_p2)

func _clamp_to_arena(pos: Vector2) -> Vector2:
	var m := 70.0
	return Vector2(clampf(pos.x, -half_w + m, half_w - m), clampf(pos.y, -half_h + m, half_h - m))

func _on_bomb_exploded(is_p1: bool) -> void:
	if is_p1:
		bombs_remaining_p1 = mini(bombs_remaining_p1 + 1, MAX_BOMBS)
	else:
		bombs_remaining_p2 = mini(bombs_remaining_p2 + 1, MAX_BOMBS)
	ui.update_bomb_count(bombs_remaining_p1, bombs_remaining_p2)
	add_shake(14.0)

func _input(event: InputEvent) -> void:
	if game_over:
		return
	if event is InputEventScreenTouch and event.pressed:
		_on_tap(event.position)
	elif event is InputEventMouseButton and event.pressed:
		_on_tap(event.position)

func _on_tap(screen_pos: Vector2) -> void:
	var global_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var pos := arena.to_local(global_pos)
	if not is_2p:
		place_bomb_p1(pos)
	else:
		if pos.x < 0:
			place_bomb_p1(pos)
		else:
			place_bomb_p2(pos)

# ================= ゴール =================

func goal_scored(is_left: bool) -> void:
	# タイマーがゼロになった後（game_over）は得点・GOAL!演出を行わない
	if game_over:
		return
	var side := 1 if is_left else -1  # 左ゴール=2P(青)得点, 右ゴール=1P(赤)得点
	if is_left:
		score_p2 += 1
	else:
		score_p1 += 1
	ui.update_score(score_p1, score_p2)
	ui.pop_score(side)
	ui.show_goal_pop("GOAL!", side)
	_celebrate_goal(side)
	# ゴールしたパックの代わりに新しいパックを盤上に復活（他のパックと重ならない位置）
	call_deferred("_spawn_respawn_puck")

func _spawn_respawn_puck() -> void:
	if game_over:
		return
	_spawn_pucks(1)

func _on_goal_left_body_entered(body: Node2D) -> void:
	if body is RigidBody2D:
		if game_over:
			_bounce_puck_back(body, true)
		else:
			goal_scored(true)
			pucks.erase(body)
			body.queue_free()

func _on_goal_right_body_entered(body: Node2D) -> void:
	if body is RigidBody2D:
		if game_over:
			_bounce_puck_back(body, false)
		else:
			goal_scored(false)
			pucks.erase(body)
			body.queue_free()

func _bounce_puck_back(puck: RigidBody2D, is_left: bool) -> void:
	# ゲームオーバー後はゴールでパックを消さず、ゴール口から盤上へ跳ね返して動きの演出を残す
	puck.linear_velocity.x = absf(puck.linear_velocity.x) if is_left else -absf(puck.linear_velocity.x)
	# 口のすぐ内側へ戻す（physics flush 中なので deferred で安全に設定）
	puck.set_deferred("position", Vector2((-half_w + 40.0) if is_left else (half_w - 40.0), puck.position.y))

func _celebrate_goal(side: int) -> void:
	# イルミネーション: 白フラッシュ → 得点色で明滅（0=引き分けはゴールド）
	var color := Color(1, 0.9, 0.4) if side == 0 else (Color(1, 0.3, 0.3) if side < 0 else Color(0.4, 0.6, 1))
	for strip in light_strips:
		strip.color = Color(1, 1, 1, 0.0)
		var tw := strip.create_tween()
		tw.tween_property(strip, "color", Color(1, 1, 1, 0.95), 0.04)
		tw.tween_property(strip, "color", Color(color.r, color.g, color.b, 0.95), 0.06)
		tw.tween_property(strip, "color:a", 0.12, 0.14)
		tw.tween_property(strip, "color:a", 0.95, 0.06)
		tw.tween_property(strip, "color:a", 0.0, 0.4)
	# テーブル全面フラッシュ
	overlay.color = Color(1, 1, 1, 0.0)
	var ot := overlay.create_tween()
	ot.tween_property(overlay, "color:a", 0.32, 0.05)
	ot.tween_property(overlay, "color:a", 0.0, 0.45)
	# 得点側ゴール口でネオン発光バースト
	_spawn_goal_burst(side)
	# ゴール音（goal.mp3）はやや速め・高めのピッチにして軽快な手触りにする
	goal_se.pitch_scale = 1.3
	goal_se.play()
	# 追加のチャイム（button53.mp3）を同時に鳴らす
	goal_se2.play()
	add_shake(10.0)

func _spawn_goal_burst(side: int) -> void:
	# ゴール口でのネオン発光 + チームカラー紙吹雪
	if side == 0:
		return
	var goal_pos := Vector2(half_w + 46.0, 0.0) if side < 0 else Vector2(-half_w - 46.0, 0.0)
	var col := Color(1, 0.4, 0.4) if side < 0 else Color(0.4, 0.6, 1)
	# 二重のネオングロー（外側ハロー + 内側コア）
	for i in 2:
		var glow := Sprite2D.new()
		glow.texture = load("res://assets/fx_glow.png")
		glow.modulate = Color(col.r, col.g, col.b, 0.0)
		glow.position = goal_pos
		glow.z_index = 20
		arena.add_child(glow)
		var fs := 3.0 if i == 0 else 1.7
		glow.scale = Vector2(fs * 0.12, fs * 0.12)
		var tw := glow.create_tween().set_parallel(true)
		tw.tween_property(glow, "scale", Vector2(fs, fs), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(glow, "modulate:a", 0.45 if i == 0 else 0.9, 0.08)
		tw.chain().tween_property(glow, "modulate:a", 0.0, 0.55)
		tw.chain().tween_callback(glow.queue_free)
	# チームカラーの紙吹雪
	var parts := CPUParticles2D.new()
	parts.texture = load("res://assets/fx_spark.png")
	parts.amount = 36
	parts.lifetime = 0.9
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.direction = Vector2.ZERO
	parts.spread = 180.0
	parts.initial_velocity_min = 120.0
	parts.initial_velocity_max = 420.0
	parts.gravity = Vector2(0, 300)
	parts.scale_amount_min = 1.2
	parts.scale_amount_max = 2.4
	parts.color = col
	parts.z_index = 21
	parts.position = goal_pos
	arena.add_child(parts)
	parts.emitting = true
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(parts.queue_free)

# ================= COM =================

func com_think() -> void:
	if is_2p or game_over:
		return
	var settings: Dictionary = com_difficulty_settings[difficulty]
	var timing_variance: float = settings["timing_variance"]
	var pos_variance: float = settings["pos_variance_px"]
	var radius: float = settings["radius_px"]

	# 難易度に応じた先読み時間（むずかしいほど速いパックの移動先を予測して狙う）
	var lead_time := 0.0
	var use_defense := false
	var use_attack_lead := false
	match difficulty:
		"むずかしい":
			lead_time = 0.5
			use_defense = true
			use_attack_lead = true
		"ふつう":
			lead_time = 0.22

	# かんたん: 先読みなしでほぼランダムな場所に置く（たまにパックの近くへ）
	if difficulty == "かんたん":
		var easy_pos := Vector2(randf_range(10.0, half_w - 70.0), randf_range(-half_h + 70.0, half_h - 70.0))
		if randf() < 0.3:
			var nearest := Vector2(half_w * 0.6, 0.0)
			var nd := 1e9
			for p in pucks:
				var d := p.position.distance_to(Vector2(half_w * 0.4, 0.0))
				if d < nd:
					nd = d
					nearest = p.position
			easy_pos = nearest
		await get_tree().create_timer(timing_variance).timeout
		if game_over or not is_instance_valid(self):
			return
		place_bomb_p2(easy_pos)
		return

	# 自陣ゴール（右側）へ向かってくるパックは防衛ボムで押し戻す（むずかしいのみ）
	# ボムはパックの「ゴール側」（+x）に置く。パックが左側から当たると左（ゴールから遠い方）へ弾かれる。
	if use_defense:
		var threat := _find_goal_threat(lead_time)
		if threat != Vector2.INF and randf() < 0.75:
			var defend_pos := threat + Vector2(70.0, 0.0)
			defend_pos += Vector2(randf_range(-pos_variance, pos_variance), randf_range(-pos_variance, pos_variance))
			await get_tree().create_timer(timing_variance).timeout
			if game_over or not is_instance_valid(self):
				return
			place_bomb_p2(defend_pos)
			return

	# 右側（COM側）で最もパックに近い位置を狙う（速度予測付き）
	var anchor := Vector2(half_w * 0.4, 0)
	var best_pos := anchor
	var best_vel := Vector2.RIGHT * 100.0
	var min_dist := 1e9
	for p in pucks:
		var predicted := p.position + p.linear_velocity * lead_time
		var d := predicted.distance_to(anchor)
		if d < min_dist:
			min_dist = d
			best_pos = predicted
			best_vel = p.linear_velocity

	if best_pos.x < 0:
		best_pos.x = 10

	# むずかしい: パックがゴール方向（右）へ動いているときは「進行方向の手前」に置き、
	# 爆風でパックをゴールへ弾き飛ばす攻撃的な置き方をする
	if use_attack_lead and best_vel.length() > 120.0 and best_vel.normalized().x > 0.2:
		best_pos -= best_vel.normalized() * 55.0
		best_pos.x = maxf(best_pos.x, 10.0)

	var angle := randf_range(0, TAU)
	var dist := randf_range(0, radius)
	var final_pos := best_pos + Vector2(cos(angle), sin(angle)) * dist
	final_pos += Vector2(randf_range(-pos_variance, pos_variance), randf_range(-pos_variance, pos_variance))

	await get_tree().create_timer(timing_variance).timeout
	if game_over or not is_instance_valid(self):
		return
	place_bomb_p2(final_pos)

func _find_goal_threat(lead_time: float) -> Vector2:
	# 自陣ゴール（右側 x=half_w）へ向かって近づくパックを検出し、lead_time 秒後の予測位置を返す。
	# 脅威がなければ Vector2.INF。
	var best: Vector2 = Vector2.INF
	var best_dist := 1e9
	for p in pucks:
		if p.linear_velocity.x <= 60.0:
			continue  # ゴール方向へ進んでいない
		if absf(p.position.y) > goal_half_h * 1.2:
			continue  # ゴール口の高さの範囲外
		var d := p.position.distance_to(Vector2(half_w, p.position.y))
		if d < best_dist:
			best_dist = d
			best = p.position + p.linear_velocity * lead_time
	if best_dist < half_w * 0.55:
		return best
	return Vector2.INF

func _on_com_timer_timeout() -> void:
	com_think()

func _unhandled_input(event: InputEvent) -> void:
	if game_over and event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://Main.tscn")

# ================= 結果画面 =================

func _on_retry_pressed() -> void:
	# 同じ設定でもう一度プレイする（自分自身のシーンを再生成）
	var new_game: Node2D = (load("res://Game.tscn") as PackedScene).instantiate()
	new_game.is_2p = is_2p
	new_game.difficulty = difficulty
	get_parent().add_child(new_game)
	queue_free()

func _on_title_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")
