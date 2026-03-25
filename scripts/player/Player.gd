extends CharacterBody2D
class_name Player

## 玩家角色
## 处理移动、跳跃和攻击动作

const RhythmDetector = preload("res://scripts/rhythm/RhythmDetector.gd")
const CommandRecognizer = preload("res://scripts/rhythm/CommandRecognizer.gd")
const CharacterData = preload("res://resources/character/CharacterData.gd")
const CharacterResource = preload("res://resources/character/CharacterResource.gd")
const CharacterCommand = preload("res://resources/character/CharacterCommand.gd")
const Skill = preload("res://resources/character/Skill.gd")

signal command_executed(command: CharacterCommand)
signal move_started(direction: int)  # 移动开始信号
signal move_ended()  # 移动结束信号
signal health_changed(current: int, max: int)  # 血量变化
signal character_died()  # 角色死亡

# 角色数据资源（可配置）
@export var character_data: CharacterData

# 备用：直接配置可用指令（当没有 character_data 时使用）
@export var move_duration: float = 2.0  # 输入期4拍的持续时间
@export var move_speed: float = 200.0  # 移动速度
@export var jump_height: float = 280.0  # 跳跃高度
@export var jump_force: float = -280.0  # 跳跃力（负值）
@export var gravity: float = 980.0
@export var screen_width: float = 1152.0  # 屏幕宽度
@export var screen_height: float = 648.0  # 屏幕高度

# 可用指令集 - 从 character_data.available_commands 加载
var available_commands: Array[String] = []  # 存储 input_string

# 当前状态
var is_charging: bool = false
var is_floating: bool = false  # 是否悬浮在空中
var floating_start_y: float = 0.0  # 悬浮起始高度
var floating_target_y: float = 0.0  # 悬浮目标高度
var floating_velocity: float = 0.0  # 悬浮恒定速度
var has_rolled_back: bool = false  # 空档期是否已经翻滚过
var defend_start_time: float = 0.0  # 防御按下时间（用于完美防反判定）
var is_perfect_defend: bool = false  # 是否处于完美防反状态
var consecutive_perfect_parries: int = 0  # 连续完美弹反次数
var current_parry_window: float = 0.3  # 当前弹反窗口（秒）
var current_command: CommandRecognizer.CommandType = CommandRecognizer.CommandType.NONE
var move_timer: float = 0.0
var move_direction: int = 0  # 1=右, -1=左, 0=停止
var move_start_x: float = 0.0  # 移动起始位置
var max_move_distance: float = 0.0  # 本次移动的最大距离
var base_move_duration: float = 2.0  # 基础移动时间（4拍）

## 获取鼓点字符串
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

## 初始化角色数据
func _init_character_data() -> void:
	if character_data:
		# 使用角色数据中的属性
		move_speed = character_data.move_speed
		jump_force = -character_data.jump_height
		# 从角色数据获取可用指令（使用 input_string）
		available_commands.clear()
		for cmd in character_data.available_commands:
			if cmd.input_string != "":
				available_commands.append(cmd.input_string)
		print("📦 角色数据已加载: %s, 指令数: %d" % [character_data.character_name, available_commands.size()])
	else:
		# 创建默认角色数据
		character_data = _create_default_character_data()
		print("⚠️ 未配置角色数据，已创建默认值")

## 创建默认角色数据
func _create_default_character_data() -> CharacterData:
	var data = CharacterData.new()
	data.character_name = "Default Hero"
	data.character_id = "default_hero"
	data.max_health = 100
	data.current_health = 100
	data.move_speed = 200.0
	data.jump_height = 280.0

	# 伤害类型默认（100%伤害，0%减免，0%触发）
	data.slash_damage_percent = 100.0
	data.blunt_damage_percent = 100.0
	data.fire_damage_percent = 100.0
	data.ice_damage_percent = 100.0
	data.lightning_damage_percent = 100.0
	data.poison_damage_percent = 100.0
	data.holy_damage_percent = 100.0

	# 暴击
	data.crit_rate = 0.0
	data.crit_damage = 1.5

	# 必杀能量
	data.ult_energy_max = 100

	# 指令从 .tres 文件的 available_commands 加载
	# 不再硬编码

	return data

func _ready() -> void:
	# 添加到组，方便其他系统查找
	add_to_group("player")

	# 初始化角色数据
	_init_character_data()

	# 注册当前角色的指令集到命令识别器
	_register_commands()

	# 计算每次移动的距离（屏幕宽度的1/4）
	max_move_distance = screen_width / 4.0
	# 根据BPM计算移动时长（4拍 = 4 * 60/bpm 秒）
	var rhythm_detector = get_tree().get_first_node_in_group("rhythm_detector")
	if rhythm_detector:
		base_move_duration = rhythm_detector.beat_interval * 4.0
		move_duration = base_move_duration
		rhythm_detector.rhythm_judged.connect(_on_rhythm_judged)

	# 监听空档期信号
	var cycle_manager = get_tree().get_first_node_in_group("rhythm_cycle_manager")
	if cycle_manager:
		cycle_manager.idle_phase_started.connect(_on_idle_phase_started)
		cycle_manager.input_phase_ended.connect(_on_input_phase_ended)
		cycle_manager.idle_input.connect(_on_idle_input)
		cycle_manager.beat_in_phase.connect(_on_beat_in_phase)
		cycle_manager.long_press_input.connect(_on_long_press_input)
		cycle_manager.skill_triggered.connect(_on_skill_triggered)

	# 监听命令识别信号以应用资源获得
	var command_recognizer = get_tree().get_first_node_in_group("command_recognizer")
	if command_recognizer:
		command_recognizer.command_recognized.connect(_on_command_recognized)

func _on_idle_phase_started() -> void:
	# 重置翻滚状态
	has_rolled_back = false

	# 重置空档期输入序列
	idle_input_keys.clear()

	# 初始化多段伤害
	_init_damage_stages()

	# 空档期开始，执行上一个命令（基于 input_string）
	var input_str = current_command_resource.input_string if current_command_resource else ""

	if input_str.begins_with("DDDD"):
		start_move(1)
	elif input_str.begins_with("AAAA"):
		start_move(-1)
	elif input_str.begins_with("WWWW"):
		# 跳跃：固定向上400px
		is_floating = true
		floating_start_y = position.y
		floating_target_y = position.y - 400.0  # 固定400px
		# 恒定速度：一拍时间到达
		var float_duration = base_move_duration / 4.0
		floating_velocity = -400.0 / float_duration  # 向上为负
		print("🦘 跳跃（目标: %s, 速度: %s）" % [floating_target_y, floating_velocity])

## 初始化多段伤害
func _init_damage_stages() -> void:
	current_damage_stages.clear()
	current_damage_stage_index = 0
	damage_stage_timers.clear()

	if current_command_resource == null:
		return

	var stages = current_command_resource.damage_stages
	if stages.is_empty():
		return

	# 根据 timing_percent 计算每个阶段的触发时间
	var total_duration = base_move_duration  # 默认4拍的总时长

	for stage in stages:
		current_damage_stages.append(stage)
		# timing_percent: 0%=开始, 100%=结束
		var trigger_time = total_duration * (stage.timing_percent / 100.0)
		damage_stage_timers.append(trigger_time)
		print("📋 伤害阶段: %.0f%% @ %.2fs" % [stage.timing_percent, trigger_time])

func _on_input_phase_ended() -> void:
	stop_move()
	# 空档期结束，角色落地
	if is_floating:
		land_from_floating()
	# 清除完美防反状态
	is_perfect_defend = false
	defend_start_time = 0.0
	# 清空调条序列
	current_command_resource = null
	idle_input_keys.clear()

func land_from_floating() -> void:
	# 从悬浮状态落地
	is_floating = false
	floating_target_y = 0
	velocity.y = 0
	print("🦘 落地")

func _on_beat_in_phase(beat: int) -> void:
	# 空档期第4拍时，强制回落地面
	if beat == 3:  # beats从0开始，第4拍是3
		is_floating = true
		# 恒定速度回落：一拍时间回到地面
		var float_duration = base_move_duration / 4.0
		floating_velocity = 400.0 / float_duration  # 向下400px的速度
		floating_target_y = position.y + 400.0  # 目标是向下400px
		print("🦘 开始回落，速度: %s, 目标: %s" % [floating_velocity, floating_target_y])

func _on_idle_input(drum: RhythmDetector.DrumType) -> void:
	# 空档期按键处理
	# 跳跃悬浮时按S = 提前下落
	print("空档期按键: %s, is_floating: %s, has_rolled_back: %s" % [drum, is_floating, has_rolled_back])
	if is_floating:
		if drum == RhythmDetector.DrumType.DOWN:
			# 设置向下恒定速度和目标
			var float_duration = base_move_duration / 4.0
			floating_velocity = 400.0 / float_duration  # 向下400px
			floating_target_y = position.y + 400.0  # 目标是向下400px
			print("🦘 提前下落")
			return

	# 翻滚只生效一次
	if has_rolled_back:
		print("🚫 翻滚已生效，无法再次翻滚")
		return

	# 尝试扩展空档期序列
	if _try_extend_idle_sequence(drum):
		return  # 序列已扩展，不再处理其他逻辑

	# 基于 input_string 判断并处理空档期按键
	var input_str = current_command_resource.input_string if current_command_resource else ""

	# 前进指令 + 按反方向(A/←) = 翻滚回原位
	if input_str.begins_with("DDDD"):
		if drum == RhythmDetector.DrumType.LEFT:
			start_roll_back()
	# 后退指令 + 按反方向(D/→) = 翻滚回原位
	elif input_str.begins_with("AAAA"):
		if drum == RhythmDetector.DrumType.RIGHT:
			start_roll_back()
	# 防御指令 + 按W = 防反
	elif input_str.begins_with("DADA"):
		if drum == RhythmDetector.DrumType.UP:
			# 按W触发防反 - 额外获得1剑势（普通防反）
			_add_attack_resource(1)
			print("🛡️ 防反触发！获得额外剑势")

## 尝试扩展空档期序列
func _try_extend_idle_sequence(drum: RhythmDetector.DrumType) -> bool:
	if current_command_resource == null:
		return false

	# 添加按键到空档期序列
	idle_input_keys.append(drum)

	# 构建当前序列字符串
	var input_part = current_command_resource.input_string
	var idle_part = "_"
	for key in idle_input_keys:
		idle_part += _drum_type_to_char(key)

	var full_sequence = input_part + idle_part
	print("🔄 尝试匹配序列: %s" % full_sequence)

	# 在 CharacterCommand 资源中查找匹配的扩展序列
	var all_commands = character_data.available_commands if character_data else []
	for cmd in all_commands:
		var cmd_full = cmd.input_string + cmd.idle_string
		if cmd_full == full_sequence:
			print("✅ 匹配到扩展序列: %s" % full_sequence)
			# 执行扩展序列
			current_command_resource = cmd
			execute_command(cmd.command_type)
			# 重新初始化多段伤害
			_init_damage_stages()
			return true

	# 检查是否超过最大空档期按键数（4个）
	if idle_input_keys.size() >= 4:
		idle_input_keys.clear()
		print("🛑 达到最大空档期按键数，重置")

	return false

## DrumType 转字符
func _drum_type_to_char(drum: int) -> String:
	match drum:
		0: return "W"  # UP
		1: return "A"  # LEFT
		2: return "S"  # DOWN
		3: return "D"  # RIGHT
		_: return ""

## 处理空档期长按释放
func _on_long_press_input(drum: RhythmDetector.DrumType, duration: float) -> void:
	print("⚡ 长按触发: %s, 时长: %.2fs" % [_get_drum_str(drum), duration])

	# 检查是否有角色数据
	if not character_data:
		return

	# 获取共享资源池
	var resource = character_data.get_resource("sword_shield")

	# 战士专属长按指令
	# 长按A（←）+ 剑势≥3 = 强力剑技
	if drum == RhythmDetector.DrumType.LEFT:
		if resource and resource.get_count(CharacterResource.ResourceType.SWORD) >= 3:
			_execute_sword_skill(resource.get_count(CharacterResource.ResourceType.SWORD))
	# 长按D（→）+ 盾势≥3 = 强力盾击
	elif drum == RhythmDetector.DrumType.RIGHT:
		if resource and resource.get_count(CharacterResource.ResourceType.SHIELD) >= 3:
			_execute_shield_skill(resource.get_count(CharacterResource.ResourceType.SHIELD))
	# 长按S（↓）+ 剑势=2 且 盾势=2 = 剑盾连击
	elif drum == RhythmDetector.DrumType.DOWN:
		if resource:
			if resource.get_count(CharacterResource.ResourceType.SWORD) == 2 and resource.get_count(CharacterResource.ResourceType.SHIELD) == 2:
				_execute_dual_skill()

## 处理技能触发（基于配置的技能系统）
func _on_skill_triggered(drum: RhythmDetector.DrumType, held_beats: int, duration: float) -> void:
	print("🎯 技能触发检测: %s, 按住 %d 拍, 时长 %.2fs" % [_get_drum_str(drum), held_beats, duration])

	if not character_data:
		return

	# 从角色数据获取对应技能
	var skill = character_data.get_skill_by_input(drum, held_beats)

	if skill:
		# 检查资源消耗
		if skill.cost_resource_id != "" and skill.cost_amount > 0:
			var res = character_data.get_resource(skill.cost_resource_id)
			if not res or res.get_total() < skill.cost_amount:
				print("❌ 资源不足，无法使用技能: %s" % skill.skill_name)
				return
			res.remove(skill.cost_amount)

		# 使用技能
		_execute_skill(skill)
	else:
		# 没有找到对应技能，执行默认行为
		print("⚪ 无对应技能，执行默认动作")

## 执行技能
func _execute_skill(skill: Skill) -> void:
	print("✨ 执行技能: %s (倍率: %.0f%%, 动画: %s)" % [
		skill.skill_name, skill.power_multiplier * 100, skill.animation_name])

	# 标记技能使用
	skill.use()

	# 根据技能类型执行不同逻辑
	match skill.trigger_type:
		Skill.TriggerType.HOLD_RELEASE:
			# 长按释放技能 - 执行攻击
			_perform_skill_attack(skill)
		Skill.TriggerType.COMBO:
			# 连击技能
			pass
		Skill.TriggerType.PASSIVE:
			# 被动技能
			pass

	# 播放动画（如果有）
	if skill.animation_name != "" and has_node("AnimationPlayer"):
		# $AnimationPlayer.play(skill.animation_name)
		pass

## 执行技能攻击
func _perform_skill_attack(skill: Skill) -> void:
	# 这里可以实现具体的攻击逻辑
	# 比如创建攻击区域、造成伤害等
	print("⚔️ 技能攻击! 伤害倍率: %.0f%%" % [skill.power_multiplier * 100])

## 强力剑技
func _execute_sword_skill(sword_count: int) -> void:
	print("⚔️ 强力剑技！剑势: %d, 倍率: 600%%" % sword_count)
	# 消耗所有剑势
	var resource = character_data.get_resource("sword_shield")  # 共享资源池
	if resource:
		resource.remove_type(CharacterResource.ResourceType.SWORD, sword_count)

## 强力盾击
func _execute_shield_skill(shield_count: int) -> void:
	print("🛡️ 强力盾击！盾势: %d, 倍率: 800%%" % shield_count)
	# 消耗所有盾势
	var resource = character_data.get_resource("sword_shield")
	if resource:
		resource.remove_type(CharacterResource.ResourceType.SHIELD, shield_count)

## 剑盾连击
func _execute_dual_skill() -> void:
	print("⚔️🛡️ 剑盾连击！倍率: 250%%锋刃+250%%钝击")
	# 消耗所有资源
	var resource = character_data.get_resource("sword_shield")
	if resource:
		resource.reset()  # 清空整个资源池

## 攻击时增加剑势资源
func _add_attack_resource(amount: int) -> void:
	if not character_data:
		return
	var resource = character_data.get_resource("sword_shield")
	if resource:
		var gained = resource.add_resource(CharacterResource.ResourceType.SWORD, amount)
		if gained > 0:
			print("⚔️ 获得剑势: +%d (当前: %d/%d, 剑:%d 盾:%d)" % [
				gained, resource.get_total(), resource.max_total,
				resource.sword_count, resource.shield_count])

## 防御时增加盾势资源
func _add_defend_resource(amount: int) -> void:
	if not character_data:
		return
	var resource = character_data.get_resource("sword_shield")
	if resource:
		var gained = resource.add_resource(CharacterResource.ResourceType.SHIELD, amount)
		if gained > 0:
			print("🛡️ 获得盾势: +%d (当前: %d/%d, 剑:%d 盾:%d)" % [
				gained, resource.get_total(), resource.max_total,
				resource.sword_count, resource.shield_count])

## 获取当前弹反窗口（秒）
func get_current_parry_window() -> float:
	if character_data:
		return character_data.get_parry_window(consecutive_perfect_parries > 0)
	return 0.3  # 默认

## 检查是否在完美防反窗口
func is_in_perfect_defend_window() -> bool:
	if not is_perfect_defend:
		return false
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed = current_time - defend_start_time
	return elapsed <= get_current_parry_window()

## 获取防御减伤率（考虑装备加成）
func get_defense_reduction() -> float:
	if is_in_perfect_defend_window():
		print("⭐ 完美防反！100%% 减伤")
		return 1.0  # 完美防反 100%
	# 普通防御从角色数据获取，使用 input_string="DADA"
	var defend_cmd = character_data.get_command("DADA")
	if defend_cmd and defend_cmd.defense_multiplier > 0:
		# 应用装备防御加成（乘法公式）
		return character_data.calc_defense(defend_cmd.defense_multiplier)
	return 0.6  # 默认60%

## 处理弹反结果（由战斗系统调用）
## 返回是否成功弹反
func on_parry_result(is_perfect: bool) -> void:
	if character_data:
		var gains = character_data.get_parry_resource_gain(is_perfect)
		_grant_resources_from_dict(gains)

	if is_perfect:
		consecutive_perfect_parries += 1
		print("✨ 连续完美弹反: %d 次" % consecutive_perfect_parries)
	else:
		consecutive_perfect_parries = 0
		print("⚠️ 弹反失败，降级窗口")

## 应用防御（受到伤害时调用）
func apply_defense(damage: int) -> int:
	var reduction = get_defense_reduction()
	var actual_damage = int(damage * (1.0 - reduction))
	var was_perfect = is_in_perfect_defend_window()
	print("🛡️ 防御减伤: %d -> %d (%.0f%%)" % [damage, actual_damage, reduction * 100])
	# 清除完美防反状态（只能触发一次）
	is_perfect_defend = false
	# 通知弹反结果
	on_parry_result(was_perfect)
	return actual_damage

func start_roll_back() -> void:
	# 翻滚回原位
	print("💨 翻滚回原位")
	# 标记已翻滚
	has_rolled_back = true
	# 停止当前移动
	stop_move()
	# 目标是回到移动的起点
	var target_x = move_start_x
	var roll_distance = target_x - position.x
	if abs(roll_distance) > 1.0:  # 如果当前位置和起点有距离
		# 向起点方向翻滚
		move_direction = sign(roll_distance)
		move_timer = 0.0
		move_start_x = position.x
		# 翻滚距离 = 剩余距离
		max_move_distance = abs(roll_distance)
		# 翻滚时间 = 剩余距离所需时间的一半（速度两倍）
		# 正常前进剩余距离的时间 = base_move_duration * (剩余距离 / 完整距离)
		var normal_time = base_move_duration * (abs(roll_distance) / (screen_width / 4.0))
		move_duration = normal_time / 2.0

## 注册当前角色的指令集到命令识别器
func _register_commands() -> void:
	var command_recognizer = get_tree().get_first_node_in_group("command_recognizer")
	if command_recognizer:
		# 使用 CharacterCommand 资源注册
		if command_recognizer.has_method("register_commands_from_resources"):
			var cmd_resources = character_data.available_commands if character_data else available_commands
			command_recognizer.register_commands_from_resources(cmd_resources)
			print("⚔️ 已从资源注册角色指令集: %d 个命令" % cmd_resources.size())
		elif command_recognizer.has_method("set_active_commands"):
			command_recognizer.set_active_commands(available_commands)
			print("⚔️ 已注册角色指令集: %d 个命令" % available_commands.size())

		# 连接资源信号
		if command_recognizer.has_signal("command_recognized_from_resource"):
			command_recognizer.command_recognized_from_resource.connect(_on_command_from_resource)

func _on_rhythm_judged(rating, drum) -> void:
	# 这里可以添加输入反馈，比如按键特效
	pass

func _physics_process(delta: float) -> void:
	# 悬浮时用恒定速度移动
	if is_floating:
		velocity.y = floating_velocity
		move_and_slide()

		# 检查是否到达目标（但不停止悬浮，保持可按S下落的状态）
		if floating_velocity < 0:  # 向上飞
			if position.y <= floating_target_y:
				position.y = floating_target_y
				velocity.y = 0
				# 不设置 is_floating = false，保持可下落状态
				print("🦘 已到达目标高度（可提前下落）")
		else:  # 向下落
			if position.y >= floating_target_y:
				position.y = floating_target_y
				velocity.y = 0
				# 不设置 is_floating = false，保持可下落状态
				print("🦘 已落地")
	else:
		# 应用重力
		if not is_on_floor():
			velocity.y += gravity * delta

	# 处理移动（持续整个输入期）
	if move_direction != 0:
		move_timer += delta
		# 计算当前位置：起点 + 进度 * 方向 * 距离
		var progress = clamp(move_timer / move_duration, 0.0, 1.0)
		var target_x = move_start_x + (progress * max_move_distance * move_direction)
		velocity.x = (target_x - position.x) / delta  # 平滑移动到目标位置
		move_and_slide()

		# 移动结束
		if progress >= 1.0:
			stop_move()

## 处理多段伤害的时间触发
func _process(delta: float) -> void:
	if current_damage_stages.is_empty():
		return

	# 更新计时器
	for i in range(damage_stage_timers.size()):
		damage_stage_timers[i] -= delta

	# 检查是否可以触发下一段伤害
	while current_damage_stage_index < current_damage_stages.size():
		if damage_stage_timers[current_damage_stage_index] <= 0:
			# 触发伤害
			_apply_damage_stage(current_damage_stage_index)
			current_damage_stage_index += 1
		else:
			break

	# 清除已完成的所有阶段
	if current_damage_stage_index >= current_damage_stages.size():
		current_damage_stages.clear()
		current_damage_stage_index = 0
		damage_stage_timers.clear()

## 应用单段伤害（带条件检查）
func _apply_damage_stage(stage_index: int) -> void:
	var stage = current_damage_stages[stage_index]

	# 构建条件上下文
	var context = _build_damage_context()

	# 条件检查
	if not stage.check_conditions(context):
		return  # 条件不满足，跳过

	# 触发率判定
	if randf() > stage.trigger_rate:
		print("⚔️ 伤害阶段 %d: 未触发 (%s)" % [stage_index + 1, _get_damage_type_name(stage.damage_type)])
		return

	# 计算最终伤害（使用乘法公式）
	# final = base * (1 + equip%) * weapon_multiplier
	var base_damage = stage.damage_multiplier * 100  # 转为百分比
	var weapon_multiplier = 1.0  # 武器倍率（未来从武器配置获取）
	var final_damage = character_data.calc_damage(base_damage, weapon_multiplier) if character_data else base_damage

	# 播放动画
	if stage.animation_event != "":
		print("🎬 播放动画: %s" % stage.animation_event)

	print("⚔️ 伤害阶段 %d: %.0f%% %s (触发率: %.0f%%) → 最终伤害: %.0f" % [
		stage_index + 1,
		stage.damage_multiplier * 100,
		_get_damage_type_name(stage.damage_type),
		stage.trigger_rate * 100,
		final_damage
	])

	# TODO: 实际应用伤害（结合动画和判定）

## 构建伤害条件上下文
func _build_damage_context() -> Dictionary:
	var context = {}

	# 弹反结果（由 set_parry_result_for_damage 设置）
	context["parry_result"] = current_parry_result

	# 目标距离（TODO: 需要结合敌人系统）
	context["target_in_range"] = true  # 默认在范围内

	# 资源信息
	if character_data:
		var sword_shield = character_data.get_resource("sword_shield")
		if sword_shield:
			context["resource_sword_shield"] = sword_shield

	return context

## 设置弹反结果（由战斗系统调用）
func set_parry_result_for_damage(is_perfect: bool) -> void:
	# 这个值会被 _build_damage_context 使用
	current_parry_result = "perfect" if is_perfect else "normal"

## 获取伤害类型名称
func _get_damage_type_name(damage_type: int) -> String:
	match damage_type:
		0: return "SLASHING"
		1: return "BLUNT"
		2: return "FIRE"
		3: return "ICE"
		4: return "LIGHTNING"
		5: return "POISON"
		6: return "HOLY"
		_: return "NONE"

func start_move(direction: int) -> void:
	if direction == 0:
		stop_move()
		return

	# 恢复基础移动时间，确保每次移动速度一致
	move_duration = base_move_duration
	move_direction = direction
	move_timer = 0.0
	move_start_x = position.x
	max_move_distance = screen_width / 4.0  # 恢复默认移动距离
	move_started.emit(direction)

	if direction > 0:
		print("🚶 开始前进")
	else:
		print("🚶 开始后退")

func stop_move() -> void:
	if move_direction != 0:
		move_direction = 0
		velocity.x = 0
		move_ended.emit()
		print("🛑 移动停止")

# 执行命令（基于 CharacterCommand 配置）
func execute_command(command: CharacterCommand) -> void:
	current_command_resource = command
	current_command = CommandRecognizer.CommandType.NONE  # 兼容旧代码
	command_executed.emit(CommandRecognizer.CommandType.NONE)

	# 处理资源消耗（如果有）
	if command and not command.resource_cost.is_empty():
		for resource_id in command.resource_cost:
			var cost = command.resource_cost[resource_id]
			var char_resource = character_data.get_resource(resource_id)
			if char_resource:
				char_resource.remove(cost)
				print("💸 消耗资源 %s -%d (剩余: %d/%d)" % [resource_id, cost, char_resource.get_total(), char_resource.max_total])

	# 根据 input_string 判断命令类型并执行
	var input_str = command.input_string if command else ""
	var is_move = input_str.begins_with("AAAA") or input_str.begins_with("DDDD")
	var is_defend = input_str.begins_with("DADA")
	var is_attack = input_str.begins_with("ADAD")
	var is_jump = input_str.begins_with("WWWW")
	var is_charge = input_str.begins_with("SSSS")
	var is_purify = input_str.begins_with("WWSS")
	var is_ultimate = input_str.begins_with("WASD")

	match true:
		is_move:
			# 移动命令不立即执行，留到空档期执行
			print("📝 移动命令已存储，等待空档期执行")

		is_defend:
			print("🛡️ 防御")
			# 记录防御开始时间（用于完美防反判定）
			defend_start_time = Time.get_ticks_msec() / 1000.0
			is_perfect_defend = true  # 进入完美防反窗口
			# 防御增加盾势（基础2点，由空档期操作决定额外获得）
			_add_defend_resource(2)

		is_attack:
			print("⚔️ 攻击")
			# 攻击增加剑势（基础2点）
			_add_attack_resource(2)

		is_jump:
			# 跳跃命令不立即执行，留到空档期执行
			print("📝 跳跃命令已记录，等待空档期执行")

		is_charge:
			print("⚡ 蓄力")
			is_charging = true

		is_purify:
			print("✨ 净化")

		is_ultimate:
			print("🌟 大招！")

		_:
			print("❓ 未知命令: %s" % input_str)

func _on_command_recognized(command: CharacterCommand, sequence: Array, time_since_beat: float) -> void:
	# 注意：execute_command已由RhythmCycleManager调用
	# 这里只处理资源获得
	_apply_resource_gain(command)

## 从 CharacterCommand 资源识别到命令
func _on_command_from_resource(command: CharacterCommand) -> void:
	print("📋 识别到资源命令: %s (倍率: %.1f)" % [command.input_string, command.power_multiplier])

	# 存储当前命令资源
	current_command_resource = command

	# 检查资源消耗
	if not _check_resource_cost(command):
		print("❌ 资源不足，无法执行命令")
		return

	# 执行命令
	execute_command(command)

	# 资源获得（输入期结束后执行）
	_apply_resource_gain(command)

## 检查资源消耗
func _check_resource_cost(command: CharacterCommand) -> bool:
	if command.resource_cost.is_empty():
		return true

	for resource_id in command.resource_cost:
		var cost = command.resource_cost[resource_id]
		var char_resource = character_data.get_resource(resource_id)
		if char_resource and char_resource.get_total() < cost:
			return false
	return true

## 应用资源获得（从指令配置）
func _apply_resource_gain(command: CharacterCommand) -> void:
	if command.resource_gain.is_empty():
		return

	for resource_id in command.resource_gain:
		var sub_types_dict = command.resource_gain[resource_id]
		var char_resource = character_data.get_resource(resource_id)
		if char_resource:
			# 新格式: {resource_id: {sub_type: amount}}
			if sub_types_dict is Dictionary:
				for sub_type in sub_types_dict:
					var amount = sub_types_dict[sub_type]
					char_resource.add_sub_type(sub_type, amount)
					print("💰 获得资源 %s(%s) +%d (当前: %d/%d)" % [resource_id, sub_type, amount, char_resource.get_total(), char_resource.max_total])
			else:
				# 旧格式: {resource_id: amount} (整数)
				char_resource.add(sub_types_dict)
				print("💰 获得资源 %s +%d (当前: %d/%d)" % [resource_id, sub_types_dict, char_resource.get_total(), char_resource.max_total])

## 应用资源获得（从字典配置）
## 格式: {resource_id: {sub_type: amount}}
func _grant_resources_from_dict(gains: Dictionary) -> void:
	if gains.is_empty():
		return

	for resource_id in gains:
		var sub_types_dict = gains[resource_id]
		var char_resource = character_data.get_resource(resource_id)
		if char_resource:
			if sub_types_dict is Dictionary:
				for sub_type in sub_types_dict:
					var amount = sub_types_dict[sub_type]
					char_resource.add_sub_type(sub_type, amount)
					print("💰 获得资源 %s(%s) +%d (当前: %d/%d)" % [resource_id, sub_type, amount, char_resource.get_total(), char_resource.max_total])

# 当前执行的命令资源
var current_command_resource: CharacterCommand = null

# 多段伤害相关
var current_damage_stages: Array = []
var current_damage_stage_index: int = 0
var damage_stage_timers: Array = []
var current_parry_result: String = "none"  # 当前弹反结果：none/perfect/normal

# 空档期序列相关
var idle_input_keys: Array = []  # 空档期已输入的按键
