extends Control

const DifficultyScene := preload("res://Difficulty.tscn")
const GameScene := preload("res://Game.tscn")

@onready var title_label: Label = $TitleLabel
@onready var mode_vbox: VBoxContainer = $ModeVBox
@onready var btn_1p_com: Button = $ModeVBox/Btn1PvsCOM
@onready var btn_1p_vs_2p: Button = $ModeVBox/Btn1Pvs2P
@onready var btn_quit: Button = $ModeVBox/BtnQuit
@onready var help_label: Label = $HelpLabel
@onready var bgm: AudioStreamPlayer = $BGM
@onready var btn_howto: Button = $ModeVBox/BtnHowTo
@onready var howto_dim: ColorRect = $HowToDim
@onready var howto_panel: PanelContainer = $HowToPanel
@onready var btn_howto_close: Button = $HowToPanel/VBox/BtnClose

var difficulty_instance: Control
var game_instance: Node2D

func _ready() -> void:
	btn_1p_com.pressed.connect(_on_1p_com_pressed)
	btn_1p_vs_2p.pressed.connect(_on_1p_vs_2p_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	btn_howto.pressed.connect(_on_howto_pressed)
	btn_howto_close.pressed.connect(_on_howto_close_pressed)
	_start_title_bgm()
	# ボタンの手触り感（ホバー・押下・クリック音）
	UIJuice.setup_button(btn_1p_com)
	UIJuice.setup_button(btn_1p_vs_2p)
	UIJuice.setup_button(btn_quit)
	UIJuice.setup_button(btn_howto)
	UIJuice.setup_button(btn_howto_close)
	# 出てくるアニメーション
	_play_entrance()
	# タイトルの雰囲気: パックがふわふわ浮く + ゆらゆら回る
	var tween := create_tween().set_loops()
	tween.tween_property($FloatingPuck, "position:y", 30.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property($FloatingPuck, "position:y", -30.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var rt := create_tween().set_loops()
	rt.tween_property($FloatingPuck, "rotation", 0.08, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rt.tween_property($FloatingPuck, "rotation", -0.08, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _play_entrance() -> void:
	# タイトルがふわっと現れ、ボタンは下から順に弾んで出てくる
	title_label.pivot_offset = title_label.size * 0.5
	title_label.scale = Vector2(0.6, 0.6)
	title_label.modulate.a = 0.0
	$SubTitle.modulate.a = 0.0
	help_label.modulate.a = 0.0
	for b in [btn_1p_com, btn_1p_vs_2p, btn_quit, btn_howto]:
		b.pivot_offset = b.size * 0.5
		b.modulate.a = 0.0
		b.scale = Vector2(0.92, 0.92)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(title_label, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title_label, "modulate:a", 1.0, 0.35)
	tw.tween_property($SubTitle, "modulate:a", 1.0, 0.4).set_delay(0.12)
	tw.tween_property(help_label, "modulate:a", 1.0, 0.5).set_delay(0.5)
	var d := 0.25
	for b in [btn_1p_com, btn_1p_vs_2p, btn_quit, btn_howto]:
		tw.tween_property(b, "modulate:a", 1.0, 0.28).set_delay(d)
		tw.tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(d)
		d += 0.1

func _start_title_bgm() -> void:
	var stream: AudioStream = load("res://assets/bgm2.wav")
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = -1
	bgm.stream = stream
	bgm.bus = AudioSettings.BUS_BGM
	bgm.play()

# ---- モード選択 ----

func _on_1p_com_pressed() -> void:
	# 1P vs COM → 難易度選択画面へ
	mode_vbox.visible = false
	title_label.visible = false
	help_label.visible = false
	$FloatingPuck.visible = false
	difficulty_instance = DifficultyScene.instantiate()
	difficulty_instance.difficulty_chosen.connect(_on_difficulty_chosen)
	difficulty_instance.back_pressed.connect(_on_difficulty_back)
	add_child(difficulty_instance)

func _on_difficulty_chosen(difficulty: String) -> void:
	launch_game(false, difficulty)

func _on_difficulty_back() -> void:
	if difficulty_instance:
		difficulty_instance.queue_free()
		difficulty_instance = null
	mode_vbox.visible = true
	title_label.visible = true
	help_label.visible = true
	$FloatingPuck.visible = true
	# 登場アニメーションが途中でも正しい状態に戻す
	title_label.modulate.a = 1.0
	title_label.scale = Vector2.ONE
	$SubTitle.modulate.a = 1.0
	help_label.modulate.a = 1.0
	for b in [btn_1p_com, btn_1p_vs_2p, btn_quit, btn_howto]:
		b.modulate.a = 1.0
		b.scale = Vector2.ONE

func _on_1p_vs_2p_pressed() -> void:
	launch_game(true, "ふつう")

func _on_quit_pressed() -> void:
	get_tree().quit()

# ---- あそびかた ----

func _on_howto_pressed() -> void:
	howto_dim.visible = true
	howto_panel.visible = true
	# パネルのポップイン
	howto_panel.pivot_offset = howto_panel.size * 0.5
	howto_panel.scale = Vector2(0.9, 0.9)
	howto_panel.modulate.a = 0.0
	var tw := howto_panel.create_tween()
	tw.tween_property(howto_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(howto_panel, "modulate:a", 1.0, 0.2)

func _on_howto_close_pressed() -> void:
	howto_dim.visible = false
	howto_panel.visible = false

func launch_game(is_2p: bool, difficulty: String) -> void:
	bgm.stop()
	if difficulty_instance:
		difficulty_instance.queue_free()
		difficulty_instance = null
	game_instance = GameScene.instantiate()
	game_instance.is_2p = is_2p
	game_instance.difficulty = difficulty
	add_child(game_instance)
	mode_vbox.visible = false
	title_label.visible = false
	help_label.visible = false
	$FloatingPuck.visible = false
