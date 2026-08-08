extends Control
## ポーズオーバーレイ。Esc キーまたは「つづける」ボタンで開閉し、ゲーム全体を一時停止する。
## ポーズ中も操作できるよう process_mode を ALWAYS にしている（ボタン・音量スライダー・入力受付用）。

var game: Node2D

var _dim: ColorRect
var _panel: PanelContainer
var _btn_resume: Button
var _btn_title: Button

func setup(game_node: Node2D) -> void:
	game = game_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	# 暗幕（ポーズ中のタップ操作をブロック）
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.08, 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	center.add_child(_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "いったんていし"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.3))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_btn_resume = _make_button("つづける")
	_btn_resume.pressed.connect(_resume)
	vbox.add_child(_btn_resume)

	_btn_title = _make_button("タイトルへもどる")
	_btn_title.pressed.connect(_to_title)
	vbox.add_child(_btn_title)

	# 音量設定
	var sep := HSeparator.new()
	vbox.add_child(sep)
	var vol_title := Label.new()
	vol_title.text = "おんりょう"
	vol_title.add_theme_font_size_override("font_size", 20)
	vol_title.add_theme_color_override("font_color", Color(0.8, 0.85, 1))
	vol_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(vol_title)
	vbox.add_child(_make_slider("BGM", AudioSettings.get_bgm_volume_db(), func(db: float) -> void: AudioSettings.set_bgm_volume_db(db)))
	vbox.add_child(_make_slider("効果音", AudioSettings.get_se_volume_db(), func(db: float) -> void: AudioSettings.set_se_volume_db(db)))

	# ルールのヒント
	var hint := Label.new()
	hint.text = "タップでボムをおける（1P:ひだり / 2P・COM:みぎ）\nボムはパックにあたるか2びょうでばくはつし、まわりのパックをふきとばす\nボムは5こ。ばくはつすると1こかいふくする\nパックをあいてのゴールにいれると1てん。2ふんでてんすうのおおいほうがかち！\nのこりじかんがへるとパックがふえていく"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	UIJuice.setup_button(_btn_resume)
	UIJuice.setup_button(_btn_title)

func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 56)
	btn.add_theme_font_size_override("font_size", 24)
	return btn

func _make_slider(label_text: String, db: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(110, 0)
	lab.add_theme_font_size_override("font_size", 18)
	row.add_child(lab)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(180, 0)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = AudioSettings.db_to_percent(db) * 100.0
	slider.value_changed.connect(func(v: float) -> void: on_change.call(AudioSettings.percent_to_db(v / 100.0)))
	# ドラッグ終了時に設定を保存（ドラッグ中の連続書き込みを避ける）
	slider.drag_ended.connect(func(_changed: bool) -> void: AudioSettings.save_settings())
	row.add_child(slider)
	return row

func _unhandled_input(event: InputEvent) -> void:
	if game == null or not is_instance_valid(game) or game.game_over:
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle()

func _toggle() -> void:
	if visible:
		_resume()
	else:
		_pause()

func _pause() -> void:
	if visible:
		return
	visible = true
	# パネルのポップイン演出
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.18)
	get_tree().paused = true

func _resume() -> void:
	if not visible:
		return
	AudioSettings.save_settings()
	get_tree().paused = false
	visible = false

func _to_title() -> void:
	AudioSettings.save_settings()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Main.tscn")
