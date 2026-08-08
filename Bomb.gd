class_name Bomb
extends StaticBody2D

signal exploded

@export var is_p1: bool = true
@export var fuse_time: float = 2.0
@export var blast_radius: float = 260.0
# 爆風のパックへの衝撃力（ご要望で1.5倍に増強: 950→1425。近距離で約1.4倍速く吹き飛ぶ）
@export var blast_force: float = 1425.0

const FX_GLOW := "res://assets/fx_glow_orange.png"
const FX_SHOCKWAVE := "res://assets/fx_shockwave.png"
const FX_SPARK := "res://assets/fx_spark.png"
# ヒットストップ時間（ごくわずか）。パックがボムに直接衝突したときのみ発動。
const HIT_STOP_TIME: float = 0.005
# ボム設置から一定時間内（600ms）の接触は「衝突」とみなさない猶予時間（実時間ms）。
# このゲームではCOMがパックを狙って1秒ごとにボムを置くため、設置直後のボムには
# ほぼ必ずパックが当たる（＝設置アーティファクト。接触速度は高速でも同様）。
# 設置からしばらくは「置いただけ」とみなし、フィールドに定着したボムへパックが
# 飛んで当たった場合のみ停止を発生させる。爆発・ノックバック・シェイクは猶予中でも
# 従来通り発生する。
const HIT_STOP_SPAWN_GRACE_MS: int = 600
# パック出現直後の「置き重なり」接触は「衝突」とみなさない猶予時間（実時間ms）。
# パックはゴール後・時間経過でボムの存在を無視して再生成されるため、出現直後の接触は
# 「飛んできて当たった」のではなく「出現した場所にボムがあった」ケースが多い。
const HIT_STOP_PUCK_GRACE_MS: int = 300
# ヒットストップを発生させる最低の接触速度（px/s）。これ未満の低速な掠り接触は
# 爆発はするが「勢いよく当たった」わけではないので停止を発生させない。
# パックの巡航速度が300〜600のため、500以上＝しっかり勢いのある衝突だけが対象。
const HIT_STOP_MIN_SPEED: float = 500.0

@onready var sprite: Sprite2D = $Sprite
@onready var hit_area: Area2D = $HitArea
@onready var place_se: AudioStreamPlayer2D = $PlaceSE
@onready var explosion_se: AudioStreamPlayer2D = $ExplosionSE

var exploded_flag: bool = false
# 爆発の起因が「パックとの直接衝突」かどうか（ヒットストップ判定に使う）
var _exploded_by_contact: bool = false
var _spawn_time_ms: int = 0
var timer: Timer
var tween: Tween

func _ready() -> void:
	_spawn_time_ms = Time.get_ticks_msec()
	# プレイヤーごとに色を変える
	sprite.texture = load("res://assets/bomb_red.png") if is_p1 else load("res://assets/bomb_blue.png")
	# 向かい合ってプレイする想定: 赤(1P)は右に90°・青(2P)は左に90°回転
	sprite.rotation = deg_to_rad(90.0) if is_p1 else deg_to_rad(-90.0)
	# 設置音
	place_se.stream = load("res://assets/se_place.wav")
	place_se.pitch_scale = randf_range(0.95, 1.05)
	place_se.bus = AudioSettings.BUS_SE
	explosion_se.bus = AudioSettings.BUS_SE
	place_se.play()
	# パック接触で即爆発
	hit_area.body_entered.connect(_on_body_entered)
	# 導火線タイマー
	timer = Timer.new()
	timer.wait_time = fuse_time
	timer.one_shot = true
	timer.timeout.connect(_explode)
	add_child(timer)
	timer.start()
	# 導火線中は点滅
	tween = create_tween().set_loops()
	tween.tween_property(sprite, "modulate:a", 0.45, 0.22)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.22)
	# 設置時のポップイン（弾んで現れる）
	var base_scale := sprite.scale
	sprite.scale = Vector2.ZERO
	var pop := create_tween()
	pop.tween_property(sprite, "scale", base_scale * 1.3, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(sprite, "scale", base_scale, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 設置時のリング（ボムの表示サイズに合わせて小さめに）
	var ring := Sprite2D.new()
	ring.texture = load(FX_SHOCKWAVE)
	ring.modulate = Color(1, 1, 1, 0.45)
	ring.z_index = 6
	add_child(ring)
	var tex_size: float = ring.texture.get_width()
	var ring_scale := 110.0 / tex_size
	var rtw := create_tween().set_parallel(true)
	rtw.tween_property(ring, "scale", Vector2(ring_scale, ring_scale), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rtw.tween_property(ring, "modulate:a", 0.0, 0.35)
	rtw.chain().tween_callback(ring.queue_free)

func _on_body_entered(body: Node2D) -> void:
	if body is Puck and not exploded_flag:
		var puck := body as Puck
		# ヒットストップ対象は「勢いよく衝突した」場合のみ:
		# 1) ボム設置直後の置き重なり（ボム側グレース）
		# 2) パック出現直後の置き重なり（パック側グレース）
		# 3) 低速な掠り接触（最低速度未満）
		# いずれも爆発自体は従来通り発生するが、停止は発生させない。
		var bomb_age: int = Time.get_ticks_msec() - _spawn_time_ms
		var puck_age: int = Time.get_ticks_msec() - puck._spawn_time_ms
		if bomb_age >= HIT_STOP_SPAWN_GRACE_MS \
				and puck_age >= HIT_STOP_PUCK_GRACE_MS \
				and puck.linear_velocity.length() >= HIT_STOP_MIN_SPEED:
			_exploded_by_contact = true
		_explode()

func _explode() -> void:
	if exploded_flag:
		return
	exploded_flag = true
	if tween:
		tween.kill()
	exploded.emit()

	# 爆風: 周囲のパックに円形の衝撃を加える（ノックバックは範囲内全てに適用）
	var arena := get_parent()
	for child in arena.get_children():
		if child is RigidBody2D:
			var body := child as RigidBody2D
			var diff: Vector2 = body.global_position - global_position
			var dist: float = diff.length()
			if dist < blast_radius:
				var force: float = blast_force * (1.0 - dist / blast_radius)
				body.apply_central_impulse(diff.normalized() * force)

	# 連鎖爆発: 爆風が隣接する未爆発のボムを誘爆させる
	for child in arena.get_children():
		if child is Bomb and child != self and not child.exploded_flag:
			if child.global_position.distance_to(global_position) <= blast_radius:
				child.ignite_chain()

	var game := get_tree().get_first_node_in_group("game")
	# ヒットストップは「パックがボムに直接衝突した」ときのみ、ごくわずか発生させる
	if _exploded_by_contact and game and game.has_method("hit_stop"):
		game.hit_stop(HIT_STOP_TIME)

	# 円形の爆発エフェクト
	_spawn_shockwave()
	_spawn_glow()
	_spawn_sparks()

	# 爆発音
	explosion_se.stream = load("res://assets/se_explosion.wav")
	explosion_se.pitch_scale = randf_range(0.95, 1.05)
	explosion_se.play()

	# 画面シェイク
	if game and game.has_method("add_shake"):
		game.add_shake(16.0)

	# 本体を消す（当たり判定も無効化。physics flush中はset_deferred）
	sprite.visible = false
	$CollisionShape2D.set_deferred("disabled", true)
	$HitArea/CollisionShape2D.set_deferred("disabled", true)
	await get_tree().create_timer(0.9).timeout
	queue_free()

func ignite_chain() -> void:
	# 連鎖用: 少しずらして爆発させる（ヒットストップ中も進むよう time_scale を無視）
	await get_tree().create_timer(randf_range(0.05, 0.13), true).timeout
	if exploded_flag or not is_instance_valid(self):
		return
	_explode()

func _spawn_shockwave() -> void:
	# 衝撃波リング: 広がりながら消える
	var ring := Sprite2D.new()
	ring.texture = load(FX_SHOCKWAVE)
	ring.modulate = Color(1, 0.85, 0.5, 1)
	ring.z_index = 10
	add_child(ring)
	var tex_size: float = ring.texture.get_width()
	var final_scale := blast_radius * 2.2 / tex_size
	ring.scale = Vector2(final_scale * 0.15, final_scale * 0.15)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(final_scale, final_scale), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)

func _spawn_glow() -> void:
	# オレンジのグロー: 一瞬光って消える
	var glow := Sprite2D.new()
	glow.texture = load(FX_GLOW)
	glow.modulate = Color(1, 0.7, 0.3, 1)
	glow.z_index = 9
	add_child(glow)
	var tex_size: float = glow.texture.get_width()
	var final_scale := blast_radius * 1.6 / tex_size
	glow.scale = Vector2(final_scale * 0.3, final_scale * 0.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(glow, "scale", Vector2(final_scale, final_scale), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(glow, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(glow.queue_free)

func _spawn_sparks() -> void:
	# 火花パーティクルが四方に飛び散る
	var parts := CPUParticles2D.new()
	parts.texture = load(FX_SPARK)
	parts.amount = 28
	parts.lifetime = 0.6
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.direction = Vector2.ZERO
	parts.spread = 180.0
	parts.initial_velocity_min = 150.0
	parts.initial_velocity_max = 520.0
	parts.gravity = Vector2(0, 260)
	parts.scale_amount_min = 1.2
	parts.scale_amount_max = 2.6
	parts.color = Color(1, 0.75, 0.35)
	parts.z_index = 11
	add_child(parts)
	parts.emitting = true
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(parts.queue_free)
