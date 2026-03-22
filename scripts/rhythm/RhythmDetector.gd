extends Node
class_name RhythmDetector

## 节奏检测器 - 核心系统
## 检测玩家的输入是否在正确的节拍上

signal beat_triggered(beat_number: int)  # 节拍触发信号 (0-3循环)
signal rhythm_judged(rating: RhythmRating, drum: DrumType)  # 节奏判定信号
signal input_missed()  # 漏拍/无效输入信号（直接断拍）

enum RhythmRating { NONE, BAD, GOOD, PERFECT }
enum DrumType { UP, DOWN, LEFT, RIGHT }

@export_group("节奏设置")
@export var bpm: int = 120
@export var perfect_window_ms: float = 50.0  # Perfect窗口 (毫秒)
@export var good_window_ms: float = 100.0    # Good窗口 (毫秒)

@export_group("节拍指示")
@export var is_on_beat: bool = false
@export var current_beat: int = 0  # 0-3 循环

var beat_interval: float = 0.5  # 每拍间隔时间 (秒)
var timer: Timer
var beat_count: int = 0
var last_judgment_beat: int = -1  # 上次判定的Beat编号（基于0.5s, 1.5s...时间轴）
var first_input_beat: int = -1  # 第一次输入时的 beat 编号
var cycle_manager: Node  # 引用节奏循环管理器
var last_input_time_since_beat: float = 0.0  # 最近一次输入的time_since_beat值

func _ready() -> void:
	# 计算节拍间隔: 60秒 / BPM = 每拍秒数
	beat_interval = 60.0 / bpm

	# 延迟获取节奏循环管理器（确保对方已添加到组）
	call_deferred("_fetch_cycle_manager")

	# 创建高精度定时器
	timer = Timer.new()
	timer.wait_time = beat_interval
	timer.autostart = true
	timer.timeout.connect(_on_beat)
	add_child(timer)

	print("🎵 节奏检测器已启动 - BPM: %d, 间隔: %.3fs" % [bpm, beat_interval])

## 延迟获取节奏循环管理器
func _fetch_cycle_manager() -> void:
	cycle_manager = get_tree().get_first_node_in_group("rhythm_cycle_manager")
	if cycle_manager:
		print("🔗 已连接到节奏循环管理器")
	else:
		print("⚠️ 无法连接到节奏循环管理器")

func _on_beat() -> void:
	current_beat = beat_count % 4
	beat_count += 1
	is_on_beat = true
	beat_triggered.emit(current_beat)

	# 重置节拍状态（在下一拍前）
	await get_tree().create_timer(0.05).timeout
	is_on_beat = false

## 处理鼓点输入
## 重置判定区间，用于切换阶段时清除之前的输入记录
func reset_judgment_beat() -> void:
	last_judgment_beat = -1
	first_input_beat = -1
	print("🔄 RhythmDetector 判定区间已重置")

## 获取第一次输入的 beat
func get_first_input_beat() -> int:
	return first_input_beat

## 获取当前实际的 beat 编号（以 beat 中心为基准，前后各半拍的范围）
func get_current_beat() -> int:
	# 计算从开始到现在经过的时间
	var current_time = (beat_count - 1) * beat_interval + (beat_interval - timer.time_left)
	# beat n 的范围：(n-0.5)*interval 到 (n+0.5)*interval
	# 公式：floor(current_time/interval + 0.5) % 4
	var beat = int(floor(current_time / beat_interval + 0.5)) % 4
	if beat < 0:
		beat += 4
	return beat

## 获取最近一次输入的time_since_beat（用于判断早晚按）
func get_last_input_time_since_beat() -> float:
	return last_input_time_since_beat

func input_drum(drum: DrumType) -> void:
	var time_in_current_beat = timer.time_left
	var time_since_beat = beat_interval - time_in_current_beat

	# 记录最近一次输入的time_since_beat（用于CommandRecognizer判断早晚按）
	last_input_time_since_beat = time_since_beat

	# 调试：显示输入归属于哪个 beat
	var actual_beat = get_current_beat()
	print("👆 输入归属beat: %d (time_since_beat=%.2fs)" % [actual_beat, time_since_beat])

	# 记录第一次输入的 beat
	if first_input_beat == -1:
		first_input_beat = actual_beat
		print("🎯 首次输入beat记录: %d" % first_input_beat)

	# 检查同一判定区间内是否已有输入（基于半拍时间轴）
	# WAITING和INPUT阶段都检测重复输入，IDLE阶段忽略
	var should_check_duplicate: bool = true
	if cycle_manager and cycle_manager.has_method("is_in_idle_phase"):
		should_check_duplicate = not cycle_manager.is_in_idle_phase()

	print("🔍 重复检测: current=%d, last=%d, should_check=%s" % [actual_beat, last_judgment_beat, should_check_duplicate])

	if should_check_duplicate and actual_beat == last_judgment_beat and last_judgment_beat != -1:
		rhythm_judged.emit(RhythmRating.BAD, drum)
		input_missed.emit()  # 直接触发断拍
		print("🥁 同一判定区间重复输入！判定: Miss")
		# 重置判定区间，允许下一次输入被正常处理
		last_judgment_beat = -1
		return

	last_judgment_beat = actual_beat

	# 计算输入时刻距离最近拍子的时间
	var deviation_ms: float = min(time_since_beat, time_in_current_beat) * 1000.0

	# 根据偏差计算判定
	# 越接近0ms越好（正好在拍子上）
	var rating: RhythmRating = RhythmRating.BAD

	if deviation_ms <= perfect_window_ms:
		rating = RhythmRating.PERFECT
	elif deviation_ms <= good_window_ms:
		rating = RhythmRating.GOOD
	# 否则是 BAD

	rhythm_judged.emit(rating, drum)
	print("🥁 输入: %s, 上次: %.1fms, 下次: %.1fms, 最近: %.1fms, 判定: %s" % [_drum_to_string(drum), time_since_beat * 1000, time_in_current_beat * 1000, deviation_ms, _rating_to_string(rating)])

func _drum_to_string(drum: DrumType) -> String:
	match drum:
		DrumType.UP: return "↑"
		DrumType.DOWN: return "↓"
		DrumType.LEFT: return "←"
		DrumType.RIGHT: return "→"
		_: return "?"

func _rating_to_string(rating: RhythmRating) -> String:
	match rating:
		RhythmRating.PERFECT: return "PERFECT!"
		RhythmRating.GOOD: return "Good"
		RhythmRating.BAD: return "Bad"
		_: return "None"

## 设置BPM
func set_bpm(new_bpm: int) -> void:
	bpm = new_bpm
	beat_interval = 60.0 / bpm
	if timer:
		timer.wait_time = beat_interval
	print("🎵 BPM已设置为: %d" % bpm)
