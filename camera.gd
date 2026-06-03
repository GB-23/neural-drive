extends Node3D

@export var cars_parent: Node3D
@export var best_car: Node3D

@onready var camera = $Camera3D

enum CameraMode { AUTO, DEBUG, BEST }

var mode = CameraMode.AUTO
var debug_target = null
var move_speed = 20.0

var height = 25.0
var distance = 25.0


func set_debug_target(cars):
	for c in cars:
		if c and c.alive:
			debug_target = c
			break


func debug_control(delta):
	var input_dir = Vector3.ZERO

	if Input.is_action_pressed("ui_up"):
		input_dir.z -= 1
	if Input.is_action_pressed("ui_down"):
		input_dir.z += 1
	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1

	global_position += input_dir * move_speed * delta


func follow_target_pos(target_pos: Vector3, forward_dir: Vector3, spread: float):
	var forward = -forward_dir.normalized()
	var offset = Vector3.UP * height + forward * (distance + spread)

	var desired = target_pos + offset

	global_position = global_position.lerp(desired, 0.1)
	look_at(target_pos, Vector3.UP)


func follow_debug_target():
	if debug_target:
		follow_target_pos(
			debug_target.global_position,
			debug_target.global_transform.basis.z,
			0.0
		)


func follow_best():
	if best_car == null or not best_car.alive:
		return

	follow_target_pos(
		best_car.global_position,
		best_car.global_transform.basis.z,
		0.0
	)


func auto_follow():
	var cars = cars_parent.get_children()

	var center = Vector3.ZERO
	var count = 0

	for c in cars:
		if c and c.is_inside_tree() and c.alive:
			center += c.global_position
			count += 1

	if count == 0:
		return

	center /= count

	var max_dist = 0.0
	for c in cars:
		if c and c.alive:
			var d = c.global_position.distance_to(center)
			max_dist = max(max_dist, d)

	max_dist = clamp(max_dist, 10.0, 60.0)

	follow_target_pos(
		center,
		Vector3.FORWARD,
		max_dist
	)


func _input(event):
	if event.is_action_pressed("SwitchCamera"):
		mode = (mode + 1) % 3


func _process(delta):
	if mode == CameraMode.AUTO:
		auto_follow()

	elif mode == CameraMode.DEBUG:
		debug_control(delta)
		follow_debug_target()

	elif mode == CameraMode.BEST:
		follow_best()
