extends Control

signal difficulty_chosen(difficulty: String)
signal back_pressed

@onready var btn_easy: Button = $Center/VBox/BtnEasy
@onready var btn_normal: Button = $Center/VBox/BtnNormal
@onready var btn_hard: Button = $Center/VBox/BtnHard
@onready var btn_back: Button = $Center/VBox/BtnBack

func _ready() -> void:
	btn_easy.pressed.connect(func() -> void: difficulty_chosen.emit("かんたん"))
	btn_normal.pressed.connect(func() -> void: difficulty_chosen.emit("ふつう"))
	btn_hard.pressed.connect(func() -> void: difficulty_chosen.emit("むずかしい"))
	btn_back.pressed.connect(func() -> void: back_pressed.emit())
	# ボタンの手触り感
	UIJuice.setup_button(btn_easy)
	UIJuice.setup_button(btn_normal)
	UIJuice.setup_button(btn_hard)
	UIJuice.setup_button(btn_back)
	# 出てくるアニメーション（全体フェード + ボタンのスタガー）※所要時間は従来の約1/4
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.06)
	var children := $Center/VBox.get_children()
	for c in children:
		if c is Control:
			var ctl := c as Control
			ctl.pivot_offset = ctl.size * 0.5
			ctl.modulate.a = 0.0
			ctl.scale = Vector2(0.9, 0.9)
	var tw := create_tween()
	var d := 0.02
	for c in children:
		if c is Control:
			var ctl := c as Control
			tw.tween_property(ctl, "modulate:a", 1.0, 0.05).set_delay(d)
			tw.tween_property(ctl, "scale", Vector2.ONE, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(d)
			d += 0.02
