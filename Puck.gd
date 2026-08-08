class_name Puck
extends RigidBody2D

const MAX_SPEED: float = 1400.0
const CLACK_MIN_SPEED: float = 140.0
const CLACK_INTERVAL_MS: int = 90
const FX_SPARK := "res://assets/fx_spark.png"
# 残像（アフターイメージ）エフェクト
const AFTERIMAGE_MIN_SPEED: float = 260.0
const AFTERIMAGE_LIFETIME: float = 0.3


@onready var hit_se: AudioStreamPlayer2D = $HitSE

var last_clack_ms: int = 0
var _contact_point: Vector2 = Vector2.ZERO
var _has_contact: bool = false
var _afterimage_timer: float = 0.0
# パックの出現時刻（実時間ms）。出現直後にボムへ重なる「置き重なり」の検出に使う
var _spawn_time_ms: int = 0

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# 最新の接触点を記録（壁エフェクトの接触点中心に使う）
	if state.get_contact_count() > 0:
		_contact_point = state.get_contact_local_position(0)
		_has_contact = true
	else:
		_has_contact = false

func _ready() -> void:
	_spawn_time_ms = Time.get_ticks_msec()
	hit_se.bus = AudioSettings.BUS_SE
	# 摩擦なし・跳ね返り係数1のエアホッケー仕様
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 1.0
	physics_material_override = mat
	gravity_scale = 0.0
	# 高速時にゴールや壁をすり抜けないようにする
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	# 壁・パック衝突の検知（カンカン音用）
	contact_monitor = true
	max_contacts_reported = 8
	# 出現ポップ（ふわっと弾んで現れる）
	var base_scale: Vector2 = $Sprite.scale
	$Sprite.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property($Sprite, "scale", base_scale * 1.35, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property($Sprite, "scale", base_scale, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	# 爆風などで速度が暴走しないように上限をかける
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)
	# 高速時だけ残像（アフターイメージ）を一定間隔で残す
	var spd := linear_velocity.length()
	if spd > AFTERIMAGE_MIN_SPEED:
		_afterimage_timer -= delta
		if _afterimage_timer <= 0.0:
			# 速度に応じて間隔を調整（移動距離ベースで約50pxごと）
			_afterimage_timer = clampf(50.0 / spd, 0.02, 0.05)
			_spawn_afterimage()
	_check_clack()

func _spawn_afterimage() -> void:
	# パックの現在位置に半透明の残像を残し、フェードアウトさせる
	var parent := get_parent()
	if parent == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = $Sprite.texture
	ghost.scale = $Sprite.scale
	ghost.modulate = Color(1, 0.95, 0.82, 0.4)
	# ツリーに追加してからグローバル座標を設定する（追加前だとローカル座標として扱われ、
	# 親（アリーナ）のオフセット分だけ残像がパックから離れた位置に出現してしまう）
	parent.add_child(ghost)
	ghost.global_position = global_position
	ghost.global_rotation = global_rotation
	# パックの直前（＝描画上は後ろ）に配置して、残像が後ろに残るようにする
	parent.move_child(ghost, get_index())
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tw.tween_property(ghost, "scale", ghost.scale * 0.85, AFTERIMAGE_LIFETIME)
	tw.chain().tween_callback(ghost.queue_free)

func _check_clack() -> void:
	if get_contact_count() <= 0:
		return
	var speed := linear_velocity.length()
	if speed < CLACK_MIN_SPEED:
		return
	var now := Time.get_ticks_msec()
	if now - last_clack_ms < CLACK_INTERVAL_MS:
		return
	last_clack_ms = now
	# 壁接触音: 高めのピッチで軽快に
	hit_se.pitch_scale = randf_range(1.5, 2.0)
	hit_se.volume_db = -8.0 + clampf((speed - CLACK_MIN_SPEED) / 900.0, 0.0, 1.0) * 10.0
	hit_se.play()
	var k := clampf(speed / MAX_SPEED, 0.0, 1.0)
	_spawn_contact_fx(k)

func _spawn_contact_fx(k: float) -> void:
	# 壁との接触点を中心に火花を飛び散らせる（衝撃が強いほど多く・速く飛ぶ）
	if not _has_contact:
		return
	var gpos: Vector2 = to_global(_contact_point)
	var arena := get_parent()
	if arena == null:
		return
	var dir: Vector2 = linear_velocity.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var parts := CPUParticles2D.new()
	parts.texture = load(FX_SPARK)
	parts.z_index = 8
	parts.amount = 4 + int(k * 10.0)
	parts.lifetime = 0.3
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.direction = dir
	parts.spread = 70.0
	parts.initial_velocity_min = 80.0 * k + 30.0
	parts.initial_velocity_max = 320.0 * k + 60.0
	parts.gravity = Vector2.ZERO
	parts.scale_amount_min = 0.8
	parts.scale_amount_max = 1.7
	parts.color = Color(1, 0.9, 0.55)
	# ツリーに追加してからグローバル座標を設定（追加前だとローカル座標扱いでずれる）
	arena.add_child(parts)
	parts.global_position = gpos
	parts.emitting = true
	var t := get_tree().create_timer(0.7)
	t.timeout.connect(parts.queue_free)
