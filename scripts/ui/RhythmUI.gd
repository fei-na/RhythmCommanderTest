extends Control
class_name RhythmUI

## 节奏UI - 显示节拍指示、判定结果等

const CharacterCommand = preload("res://resources/character/CharacterCommand.gd")

@onready var beat_indicator: Label = $BeatIndicator
@onready var rating_label: Label = $RatingLabel
@onready var queue_display: Label = $QueueDisplay
@onready var command_label: Label = $CommandLabel

var rhythm_detector: RhythmDetector
var command_recognizer: CommandRecognizer

func _ready() -> void:
	# 查找相关节点
	rhythm_detector = get_tree().get_first_node_in_group("rhythm_detector")
	command_recognizer = get_tree().get_first_node_in_group("command_recognizer")

	if rhythm_detector:
		rhythm_detector.beat_triggered.connect(_on_beat_triggered)
		rhythm_detector.rhythm_judged.connect(_on_rhythm_judged)

	if command_recognizer:
		command_recognizer.queue_updated.connect(_on_queue_updated)
		command_recognizer.command_recognized.connect(_on_command_recognized)

	_update_ui()

func _on_beat_triggered(beat_number: int) -> void:
	_update_beat_indicator(beat_number)

func _on_rhythm_judged(rating: RhythmDetector.RhythmRating, drum: RhythmDetector.DrumType) -> void:
	_update_rating(rating)

func _on_queue_updated(drum: RhythmDetector.DrumType) -> void:
	_update_queue_display()

func _on_command_recognized(command: CharacterCommand, sequence: Array, time_since_beat: float) -> void:
	_update_command_display(command)

func _update_beat_indicator(beat: int) -> void:
	if beat_indicator:
		var beat_display := ""
		for i in range(4):
			if i == beat:
				beat_display += "●"
			else:
				beat_display += "○"
		beat_indicator.text = beat_display

func _update_rating(rating: RhythmDetector.RhythmRating) -> void:
	if rating_label:
		match rating:
			RhythmDetector.RhythmRating.PERFECT:
				rating_label.text = "PERFECT!"
				rating_label.modulate = Color.YELLOW
			RhythmDetector.RhythmRating.GOOD:
				rating_label.text = "GOOD"
				rating_label.modulate = Color.GREEN
			RhythmDetector.RhythmRating.BAD:
				rating_label.text = "Bad"
				rating_label.modulate = Color.RED
			_:
				rating_label.text = ""

func _update_queue_display() -> void:
	if queue_display and command_recognizer:
		queue_display.text = "队列: %d 拍" % command_recognizer.get_queue_size()

func _update_command_display(command: CharacterCommand) -> void:
	if command_label and command:
		var input_str = command.input_string
		if input_str.begins_with("ADAD"):
			command_label.text = "⚔️ 攻击"
		elif input_str.begins_with("DDDD"):
			command_label.text = "⬆️ 前进"
		elif input_str.begins_with("AAAA"):
			command_label.text = "⬇️ 后退"
		elif input_str.begins_with("DADA"):
			command_label.text = "🛡️ 防御"
		elif input_str.begins_with("SSSS"):
			command_label.text = "⚡ 蓄力"
		elif input_str.begins_with("WWWW"):
			command_label.text = "⬆️ 跳跃"
		elif input_str.begins_with("WWSS"):
			command_label.text = "✨ 净化"
		elif input_str.begins_with("WASD"):
			command_label.text = "🌟 大招"
		else:
			command_label.text = input_str
	else:
		if command_label:
			command_label.text = ""

func _update_ui() -> void:
	_update_beat_indicator(0)
	_update_queue_display()
	if rating_label:
		rating_label.text = ""
	if command_label:
		command_label.text = "等待输入..."
