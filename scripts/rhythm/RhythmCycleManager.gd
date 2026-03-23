extends Node
class_name RhythmCycleManager

const RhythmDetector = preload("res://scripts/rhythm/RhythmDetector.gd")
const CharacterCommand = preload("res://resources/character/CharacterCommand.gd")

## 节奏循环管理器
## 管理输入期和空档期的交替循环

signal phase_changed(to_input_phase: bool)  # 阶段切换信号
signal beat_in_phase(beat: int)  # 阶段内的节拍信号
signal missed_beat()  # 漏拍信号
signal idle_phase_started()  # 空档期开始信号（移动开始）
signal input_phase_ended()  # 输入期结束信号（移动停止）
signal idle_input(drum: RhythmDetector.DrumType)  # 空档期按键信号
signal long_press_input(drum: RhythmDetector.DrumType, duration: float)  # 空档期长按释放信号
signal skill_triggered(drum: RhythmDetector.DrumType, held_beats: int, duration: float)  # 技能触发信号（携带按了几拍）

enum CyclePhase { WAITING, INPUT, IDLE }

@export var rhythm_detector: RhythmDetector
@export var command_recognizer: CommandRecognizer
@export var score_manager: ScoreManager

var current_phase: CyclePhase = CyclePhase.WAITING  # 当前阶段
var beats_in_current_phase: int = 0  # 当前阶段内的节拍数
var beats_per_phase: int = 4  # 每个阶段的节拍数
var is_enabled: bool = true  # 是否启用循环管理
var has_input_this_beat: bool = false  # 当前节拍是否有输入
var had_input_in_phase: bool = false  # 当前输入期内是否有输入
var command_recognized_in_phase: bool = false  # 当前输入期是否成功识别了命令
var waiting_for_idle: bool = false  # 等待进入空档期（敲完4拍后等下一个beat）
var pending_switch_to_idle: bool = false  # 标记需要切换到空档期，等待下一个beat触发
var just_switched_to_idle: bool = false  # 刚从WAITING切换到IDLE，跳过第一次IDLE执行

# 玩家输入起始 beat（用于空档期第1拍对齐）
var input_start_beat: int = 0  # 玩家开始敲第1拍时的 beat 编号
var should_start_idle_action: bool = false  # 是否应该发出空档期动作信号
var idle_phase_start_beat: int = 0  # 空档期动作应该开始的 beat 编号
var pending_time_since_beat: float = 0.0  # 待处理的第4拍输入的time_since_beat（用于判断早晚按）

# 大招模式
var is_ult_mode: bool = false  # 是否在大招模式
var ult_beats_remaining: int = 0  # 大招剩余节拍数

# Miss冷却期（防止断拍后继续输入立即被识别）
var miss_cooldown: bool = false  # Miss后冷却中
var miss_cooldown_duration: float = 0.5  # 冷却时间(秒)

func _ready() -> void:
	# 添加到组
	add_to_group("rhythm_cycle_manager")

	# 等待其他系统就绪
	await get_tree().create_timer(0.2).timeout
	rhythm_detector = get_tree().get_first_node_in_group("rhythm_detector")
	command_recognizer = get_tree().get_first_node_in_group("command_recognizer")
	score_manager = get_tree().get_first_node_in_group("score_manager")

	if rhythm_detector:
		rhythm_detector.beat_triggered.connect(_on_beat)
		rhythm_detector.rhythm_judged.connect(_on_rhythm_judged)
		rhythm_detector.input_missed.connect(_on_input_missed)

	# 监听命令识别，开始第一次命令后启动循环
	if command_recognizer:
		command_recognizer.command_recognized.connect(_on_command_recognized)

	# 连接输入管理器的长按释放信号
	var input_manager = get_tree().get_first_node_in_group("input_manager")
	if input_manager:
		input_manager.key_released.connect(_on_key_released)

	# 连接漏拍信号
	missed_beat.connect(_on_missed_beat)

	print("🔄 节奏循环管理器已就绪 - 等待玩家首次敲击...")

## 处理按键释放（长按检测）
func _on_key_released(drum: RhythmDetector.DrumType, duration: float) -> void:
	# 输入期：检测长按，触发技能
	if current_phase == CyclePhase.INPUT:
		_emit_input_phase_signals(drum, duration)
		return

	# 空档期：正常处理移动
	if current_phase != CyclePhase.IDLE:
		return

	if not rhythm_detector:
		# 如果没有rhythm_detector，使用默认阈值
		_emit_idle_signals(drum, duration, 2.0)
		return

	var beat_interval = rhythm_detector.beat_interval
	var held_beats = floor(duration / beat_interval) + 1
	held_beats = clampi(held_beats, 1, 4)

	_emit_idle_signals(drum, duration, beat_interval, held_beats)

## 输入期的长按信号处理
func _emit_input_phase_signals(drum: RhythmDetector.DrumType, duration: float) -> void:
	if not rhythm_detector:
		return

	var beat_interval = rhythm_detector.beat_interval
	var held_beats = floor(duration / beat_interval) + 1
	held_beats = clampi(held_beats, 1, 4)

	# 在输入期也触发技能信号，让Player处理
	skill_triggered.emit(drum, held_beats, duration)
	print("🎯 输入期技能检测: %s, 按住 %d 拍" % [_get_drum_str(drum), held_beats])

func _emit_idle_signals(drum: RhythmDetector.DrumType, duration: float, beat_interval: float, held_beats: int = 1) -> void:
	# 长按阈值：2/3/4拍
	var threshold_4 = beat_interval * 4.0
	var threshold_3 = beat_interval * 3.0
	var threshold_2 = beat_interval * 2.0

	if duration >= threshold_4:
		print("✋ 长按4拍释放: %s, 时长: %.2fs" % [_get_drum_str(drum), duration])
		long_press_input.emit(drum, duration)
		skill_triggered.emit(drum, 4, duration)
	elif duration >= threshold_3:
		print("✋ 长按3拍释放: %s, 时长: %.2fs" % [_get_drum_str(drum), duration])
		skill_triggered.emit(drum, 3, duration)
	elif duration >= threshold_2:
		print("✋ 长按2拍释放: %s, 时长: %.2fs" % [_get_drum_str(drum), duration])
		skill_triggered.emit(drum, 2, duration)
	else:
		print("👆 短按释放: %s, 时长: %.2fs" % [_get_drum_str(drum), duration])
		idle_input.emit(drum)
		skill_triggered.emit(drum, 1, duration)

func _get_drum_str(drum: RhythmDetector.DrumType) -> String:
	if drum == RhythmDetector.DrumType.UP:
		return "↑"
	elif drum == RhythmDetector.DrumType.DOWN:
		return "↓"
	elif drum == RhythmDetector.DrumType.LEFT:
		return "←"
	elif drum == RhythmDetector.DrumType.RIGHT:
		return "→"
	return "?"

func _on_missed_beat() -> void:
	# 漏拍时通知计分系统
	if score_manager:
		score_manager.on_missed_beat()

func _on_input_missed() -> void:
	# INPUT和WAITING阶段都触发Miss，IDLE阶段忽略
	if current_phase == CyclePhase.INPUT:
		print("🔴 输入期重复输入断拍！")
		missed_beat.emit()
		_reset_to_waiting()
	elif current_phase == CyclePhase.WAITING:
		print("🔴 等待期重复输入断拍！")
		missed_beat.emit()
		_reset_to_waiting()
	else:
		print("🔴 空档期重复输入（忽略）")

func _on_command_recognized(command: CharacterCommand, sequence: Array, time_since_beat: float) -> void:
	# 标记命令已识别
	command_recognized_in_phase = true

	# 设置 current_command（动作会在空档期执行）
	_execute_command(command)

	# 玩家第一次敲击命令后，判断早晚按并决定如何切换到空档期
	if current_phase == CyclePhase.WAITING:
		# 第一次WAITING→IDLE切换，延迟到beat END执行
		pending_switch_to_idle = true
		pending_time_since_beat = time_since_beat  # 保存，用于后续判断早晚按
		# 不设置just_switched_to_idle，让下一个beat正常执行IDLE block
		just_switched_to_idle = false
		print("🎵 首次命令识别（time=%.2fs），等待beat结束切换到空档期！" % time_since_beat)

func _execute_command(command: CharacterCommand) -> void:
	# 查找玩家角色并执行命令
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.execute_command(command)

func _switch_to_idle() -> void:
	print("🔧 _switch_to_idle()执行: beats_in_current_phase=%d" % beats_in_current_phase)
	current_phase = CyclePhase.IDLE
	beats_in_current_phase = 0  # 重置为0，让下一个beat成为idle beat 1
	has_input_this_beat = false
	had_input_in_phase = false
	command_recognized_in_phase = false
	print("🔄 命令完成，切换到空档期 (4拍)")
	phase_changed.emit(false)
	# 不在这里emit，让下一个beat handler的IDLE block emit
	# 这样可以确保空档期从下一个beat开始，而不是从当前beat开始

func _start_cycle() -> void:
	current_phase = CyclePhase.INPUT
	beats_in_current_phase = 0
	# 用户刚敲完第4拍，立即进入输入期，所以第1拍算有输入
	has_input_this_beat = true
	had_input_in_phase = false  # 重置输入期输入标记
	command_recognized_in_phase = false  # 重置命令识别标记
	phase_changed.emit(true)
	print("🔄 循环开始！进入输入期")

func _on_beat(beat: int) -> void:
	if not is_enabled:
		return

	# 调试日志
	print("🥁 ===== BEAT触发: beat=%d, phase=%s, waiting_for_idle=%s, beats_in_phase=%d" % [beat, get_phase_name(), waiting_for_idle, beats_in_current_phase])

	# 大招模式下跳过正常循环
	if is_ult_mode:
		ult_beats_remaining -= 1
		if ult_beats_remaining <= 0:
			end_ult_mode()
		return

	# 等待阶段
	if current_phase == CyclePhase.WAITING:
		if pending_switch_to_idle:
			# 判断是否需要跳过当前beat来对齐
			# 如果第4拍输入发生在beat handler之后（早按），需要跳过
			# 如果第4拍输入发生在beat handler之前（晚按），不需要跳过
			var should_skip: bool = false
			if rhythm_detector:
				should_skip = pending_time_since_beat >= (rhythm_detector.beat_interval * 0.5)
			if should_skip:
				# 早按：切换并设置just_switched_to_idle=true跳过下一个beat
				_switch_to_idle()
				pending_switch_to_idle = false
				just_switched_to_idle = true
				print("🔍 START检测到pending（早按），切换并跳过下一个beat")
			else:
				# 晚按：切换并让当前beat成为idle beat 1
				_switch_to_idle()
				pending_switch_to_idle = false
				# 不设置just_switched_to_idle，当前beat会成为idle beat 1
				just_switched_to_idle = false
				print("🔍 START检测到pending（晚按），立即切换")
		else:
			print("📝 节拍: %d, 阶段: 等待中" % beat)
			return

	# 刚从WAITING切换过来时，跳过IDLE块的第一次执行
	if just_switched_to_idle:
		print("🔍 just_switched_to_idle=true, 跳过本beat")
		just_switched_to_idle = false
		return

	var idle_block_ran: bool = false  # 标记本beat是否执行了IDLE block

	# INPUT阶段：正常计数
	if current_phase == CyclePhase.INPUT:
		beats_in_current_phase += 1
		beat_in_phase.emit(beats_in_current_phase - 1)
	# IDLE阶段：正常计数
	elif current_phase == CyclePhase.IDLE:
		beats_in_current_phase += 1
		beat_in_phase.emit(beats_in_current_phase - 1)
		idle_block_ran = true  # 标记IDLE block已执行
		# 第1拍时发出移动信号
		if beats_in_current_phase == 1:
			print("🎵 空档期第1拍，移动开始")
			idle_phase_started.emit()

	print("📝 节拍: %d, 阶段: %s, beats: %d" % [beat, get_phase_name(), beats_in_current_phase])

	# ===== 时间轴1：半拍时执行漏拍检测和阶段切换 =====
	if rhythm_detector:
		var delay_time = rhythm_detector.beat_interval * 0.5
		await get_tree().create_timer(delay_time).timeout

		# ===== 延迟处理pending_switch_to_idle =====
		# 如果本beat的IDLE block没有执行，且pending_switch_to_idle为true
		if pending_switch_to_idle and not idle_block_ran:
			print("🔍 END检测到pending，调用_switch_to_idle()")
			_switch_to_idle()
			pending_switch_to_idle = false
			# 不设置just_switched_to_idle，让当前beat成为idle beat 0
			just_switched_to_idle = false
			# 返回，避免后续逻辑干扰
			print("🔍 END: 切换完成，当前phase=%s, beats=%d" % [get_phase_name(), beats_in_current_phase])
			return

		# 输入期才进行漏拍检测
		if current_phase == CyclePhase.INPUT:
			# 漏拍检测：半拍后检查 has_input_this_beat（包含本拍判定窗口内的输入）
			if not has_input_this_beat:
				print("🔴 漏拍！")
				missed_beat.emit()
				_reset_to_waiting()
				return

			# 漏拍检测完成后，再切换阶段（第4拍检测完后才切换）
			if beats_in_current_phase >= beats_per_phase:
				_switch_phase()
		# 空档期4拍结束后也切换到输入期
		elif current_phase == CyclePhase.IDLE and beats_in_current_phase >= beats_per_phase:
			_switch_phase()

		# 重置输入标记
		has_input_this_beat = false

func _on_rhythm_judged(rating: RhythmDetector.RhythmRating, drum: RhythmDetector.DrumType) -> void:
	if not is_enabled or is_ult_mode:
		return

	# 只要有输入就标记（无论什么判定）
	if current_phase == CyclePhase.INPUT:
		has_input_this_beat = true
		had_input_in_phase = true  # 记录当前输入期有输入
	# 空档期按键检测
	elif current_phase == CyclePhase.IDLE:
		idle_input.emit(drum)

func _switch_phase() -> void:
	beats_in_current_phase = 0

	# 输入期4拍结束后，检查是否识别到有效命令
	if current_phase == CyclePhase.INPUT:
		if not command_recognized_in_phase:
			# 没有识别到有效命令，断拍
			print("🔴 未识别到有效命令！断拍！")
			missed_beat.emit()
			_reset_to_waiting()
			return

		# 识别到有效命令，切换到空档期
		print("🔧 _switch_phase()调用_switch_to_idle: beats=%d" % beats_in_current_phase)
		_switch_to_idle()
	else:
		# 空档期 → 输入期
		current_phase = CyclePhase.INPUT
		has_input_this_beat = false
		had_input_in_phase = false
		command_recognized_in_phase = false
		# 重置RhythmDetector的重复检测，防止空档期输入影响输入期
		var rhythm_detector = get_tree().get_first_node_in_group("rhythm_detector")
		if rhythm_detector and rhythm_detector.has_method("reset_judgment_beat"):
			rhythm_detector.reset_judgment_beat()
		print("🔄 切换到输入期 (4拍)")
		phase_changed.emit(true)

func _reset_to_waiting() -> void:
	# Miss后回到等待状态，等下次命令重新开始
	current_phase = CyclePhase.WAITING
	beats_in_current_phase = 0
	waiting_for_idle = false
	# 触发Miss冷却期，阻止断拍后立即输入被识别
	_start_miss_cooldown()
	_clear_command_queue()
	print("🔴 Miss！回到等待状态")

func _clear_command_queue() -> void:
	var recognizer = get_tree().get_first_node_in_group("command_recognizer")
	if recognizer:
		recognizer.clear_queue()

## 判断当前是否在输入期
func is_in_input_phase() -> bool:
	return current_phase == CyclePhase.INPUT

## 判断当前是否在空档期
func is_in_idle_phase() -> bool:
	return current_phase == CyclePhase.IDLE

## 判断当前是否在等待阶段（游戏刚开始）
func is_in_waiting_phase() -> bool:
	return current_phase == CyclePhase.WAITING

## 启动Miss冷却期
func _start_miss_cooldown() -> void:
	miss_cooldown = true
	print("⏳ Miss冷却期开始 (%.1f秒)" % miss_cooldown_duration)
	get_tree().create_timer(miss_cooldown_duration).timeout.connect(_end_miss_cooldown)

## 结束Miss冷却期
func _end_miss_cooldown() -> void:
	miss_cooldown = false
	print("✅ Miss冷却期结束，可以重新输入")

## 判断当前是否允许输入（不在冷却期）
func is_input_allowed() -> bool:
	return not miss_cooldown

## 获取当前阶段名称
func get_phase_name() -> String:
	match current_phase:
		CyclePhase.WAITING: return "等待开始"
		CyclePhase.INPUT: return "输入期"
		CyclePhase.IDLE: return "空档期"
	if is_ult_mode:
		return "大招模式"
	return "未知"

## 启动大招模式
## duration_beats: 大招持续节拍数（必须是4的倍数）
func start_ult_mode(duration_beats: int) -> void:
	is_ult_mode = true
	ult_beats_remaining = duration_beats
	print("🌟 大招模式开始！持续 %d 拍" % duration_beats)

## 结束大招模式
func end_ult_mode() -> void:
	is_ult_mode = false
	# 回到输入期
	current_phase = CyclePhase.INPUT
	beats_in_current_phase = 0
	has_input_this_beat = false
	print("🔄 大招模式结束，回到输入期")
	phase_changed.emit(true)

## 设置每个阶段的节拍数（默认4）
func set_beats_per_phase(beats: int) -> void:
	beats_per_phase = beats
	print("🔄 每阶段节拍数设为: %d" % beats)
