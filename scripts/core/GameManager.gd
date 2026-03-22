extends Node
class_name GameManager

## 游戏管理器 - 核心状态控制

const CharacterCommand = preload("res://resources/character/CharacterCommand.gd")

signal game_started()
signal game_over()
signal command_executed(command: CharacterCommand)

static var instance: GameManager

var is_game_running: bool = false

func _ready() -> void:
	# 单例模式
	if instance == null:
		instance = self
	else:
		queue_free()
		return

	print("🎮 游戏管理器已就绪")

func _process(delta: float) -> void:
	pass

## 开始游戏
func start_game() -> void:
	is_game_running = true
	game_started.emit()
	print("🚀 游戏开始!")

## 结束游戏
func end_game() -> void:
	is_game_running = false
	game_over.emit()
	print("💀 游戏结束!")

## 执行命令
func execute_command(command: CharacterCommand) -> void:
	command_executed.emit(command)

	# 基于 input_string 打印日志
	var input_str = command.input_string if command else ""
	if input_str.begins_with("ADAD"):
		print("⚔️ 执行命令: 攻击")
	elif input_str.begins_with("DDDD"):
		print("⬆️ 执行命令: 前进")
	elif input_str.begins_with("AAAA"):
		print("⬇️ 执行命令: 后退")
	elif input_str.begins_with("DADA"):
		print("🛡️ 执行命令: 防御")
	elif input_str.begins_with("WWWW"):
		print("⬆️ 执行命令: 跳跃")
	elif input_str.begins_with("WWSS"):
		print("✨ 执行命令: 净化")
	elif input_str.begins_with("SSSS"):
		print("⚡ 执行命令: 蓄力")
	elif input_str.begins_with("WASD"):
		print("🌟 执行命令: 终极大招")
	else:
		print("❓ 执行命令: %s" % input_str)
