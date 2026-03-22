extends Node
class_name ScoreManager

## 计分系统 - 管理分数和Fever

const CharacterCommand = preload("res://resources/character/CharacterCommand.gd")

signal score_changed(new_score: int)
signal fever_started()
signal fever_ended()
signal progress1_unlocked()
signal progress2_unlocked()

@export var rhythm_detector: RhythmDetector
@export var rhythm_cycle_manager: RhythmCycleManager
@export var command_recognizer: CommandRecognizer

var current_score: int = 0
var fever_score_threshold: int = 20  # 触发Fever的分数阈值
var is_in_fever: bool = false

# Progress解锁状态
var has_progress1: bool = false
var has_progress2: bool = false
var progress2_threshold: int = 12  # 12分触发Progress2

# 评分记录（用于命令完成时计算总分）
var rating_queue: Array = []

func _ready() -> void:
	# 等待其他系统就绪
	await get_tree().create_timer(0.2).timeout

	rhythm_detector = get_tree().get_first_node_in_group("rhythm_detector")
	rhythm_cycle_manager = get_tree().get_first_node_in_group("rhythm_cycle_manager")

	if rhythm_detector:
		rhythm_detector.rhythm_judged.connect(_on_rhythm_judged)

	if command_recognizer:
		command_recognizer.command_recognized.connect(_on_command_recognized)

	print("📊 计分系统已就绪")

func _on_rhythm_judged(rating: RhythmDetector.RhythmRating, drum: RhythmDetector.DrumType) -> void:
	# 记录评分
	rating_queue.append(rating)

func _on_command_recognized(command: CharacterCommand, sequence: Array, time_since_beat: float) -> void:
	# 计算命令的总分
	# Bad = 0分, Good = 1分, Perfect = 2分
	var total_score: int = 0

	# 从rating_queue中获取这个命令对应的评分
	var start_index = rating_queue.size() - sequence.size()
	for i in range(sequence.size()):
		if start_index + i < rating_queue.size():
			var rating = rating_queue[start_index + i]
			match rating:
				RhythmDetector.RhythmRating.PERFECT:
					total_score += 2
				RhythmDetector.RhythmRating.GOOD:
					total_score += 1
				RhythmDetector.RhythmRating.BAD:
					total_score += 0  # Bad 不加分

	# 清空已使用的评分
	rating_queue.clear()

	# 空档期不計分（非Fever状态）
	if rhythm_cycle_manager and rhythm_cycle_manager.is_in_idle_phase() and not is_in_fever:
		print("🎵 空档期输入，不计分")
		return

	# 加分（只要敲了就加分，不管好坏）
	current_score += total_score
	score_changed.emit(current_score)
	print("📈 命令完成: +%d 分 (总分: %d)" % [total_score, current_score])

	# 检查Fever
	if not is_in_fever and current_score >= fever_score_threshold:
		_start_fever()

	# 检查Progress
	_check_progress()

## 当漏拍时调用
func on_missed_beat() -> void:
	_trigger_miss()

func _check_progress() -> void:
	# Progress1: 4分（2个Perfect）触发
	if not has_progress1 and current_score >= 4:
		has_progress1 = true
		progress1_unlocked.emit()
		print("🔓 Progress1 已解锁！")

	# Progress2: 12分触发
	if not has_progress2 and current_score >= progress2_threshold:
		has_progress2 = true
		progress2_unlocked.emit()
		print("🔓 Progress2 已解锁！")

func _start_fever() -> void:
	is_in_fever = true
	fever_started.emit()
	print("🔥 FEVER 启动！！")

func _trigger_miss() -> void:
	print("💀 Miss！重置到Base状态")
	_reset_to_base()

func _reset_to_base() -> void:
	current_score = 0
	is_in_fever = false
	has_progress1 = false
	has_progress2 = false
	score_changed.emit(current_score)
	fever_ended.emit()
	print("🔴 已重置到Base状态")

func get_current_score() -> int:
	return current_score

func is_fever_active() -> bool:
	return is_in_fever
