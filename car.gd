extends CharacterBody3D
@export var path: Path3D
@onready var label = $Billboard/Label3D

const INPUT_SIZE = 7
const HIDDEN_SIZE = 6

var alive = true
var car_name = ""

var stuck_on_wall = 0
var wall_limit = 0.5
var progress = 0.0
var fitness = 0.0
var last_progress = 0.0
var checkpoint_index = 0
var last_position = Vector3.ZERO
var stuck_timer = 0.0
var stuck_distance = 0.2
var stuck_limit = 2.0
var stuck_multiplier = 0.3

var speed = 70 #48
var acceleration = 120.0 #20.0
var brake = 160.0 #30.0
var turn_speed = 4
var throttle = 1.0
var steering = 0.0

var velocitytarget = 0.0
var current_speed = 0.0
var ray_length = 20.0
var current_brake = 0.0
var current_rank = 11
var previous_rank = 11

var weight_front = -1.0 #basicamente "parede na frente = ruim"
var weight_left = 1.0
var weight_right = 1.0
var front_input = 1.0
var left_input = 1.0
var right_input = 1.0
var front_left_input = 1.0
var front_right_input = 1.0
var real_left_input = 1.0
var real_right_input = 1.0

var default_material
var best_material

var hidden_neurons = []
var steering_output = {
	"weights": [],
	"bias": 0.0
}

var throttle_output = {
	"weights": [],
	"bias": 0.0
}

var brake_output = {
	"weights": [],
	"bias": 0.0
}

var distance_travelled = 0.0

# sigmoid / tanh
func activate(x):
	return tanh(x)


func random_weights(count):
	var arr = []

	for i in range(count):
		arr.append(randf_range(-1.0, 1.0))

	return arr

# output = (input1 * peso1) + (input2 * peso2) + (input3 * peso3) + bias
func neuron(inputs, weights, bias):
	var output = 0.0
	for i in range(inputs.size()):
		output += inputs[i] * weights[i] # é a conta de cima porem feita com um loop (porem escalavel)
	output += bias # e no final soma o bias
	return activate(output)
	

func crash():
	if alive:
		alive = false
		set_physics_process(false)
		fitness -= 50.0


func check_wall_hit(delta):
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		
		if body and body.is_in_group("walls"):
			stuck_on_wall += delta

func check_checkpoint():
	var parent = get_parent()
	if parent == null or parent.checkpoints.is_empty():
		return

	if checkpoint_index >= parent.checkpoints.size():
		return
	var target = parent.checkpoints[checkpoint_index]
	if global_position.distance_to(target) < 2.5:
		checkpoint_index += 1
		fitness += 100.0

func update_progress():
	var curve = path.curve
	if curve == null:
		return
	var closest_point = curve.get_closest_point(global_position)
	var current = curve.get_closest_offset(closest_point)

	var max_len = curve.get_baked_length()

	var delta_progress = current - last_progress

	if delta_progress > max_len * 0.5:
		delta_progress -= max_len
	elif delta_progress < -max_len * 0.5:
		delta_progress += max_len

	delta_progress = clamp(delta_progress, -5.0, 5.0)

	fitness += delta_progress
	last_progress = current

	progress = current

func define_name(new_name):
	car_name = new_name
	label.text = car_name

func reset():
	alive = true
	fitness = 0.0
	last_progress = 0.0
	progress = 0.0
	checkpoint_index = 0
	current_speed = 0.0
	velocity = Vector3.ZERO
	stuck_on_wall = 0
	stuck_timer = 0.0
	last_position = global_position
	set_physics_process(true)

func get_ray_distance(ray: RayCast3D):
	if ray.is_colliding():
		var point = ray.get_collision_point()
		var distance = global_position.distance_to(point)
		var max_distance = ray.target_position.length()
		return distance / max_distance
	return 1.0

func CheckRays():
	front_input = get_ray_distance($FrontRay)
	left_input = get_ray_distance($FrontLeftRay)
	right_input = get_ray_distance($FrontRightRay)
	front_left_input  = get_ray_distance($FrontHalfLeftRay)
	front_right_input = get_ray_distance($FrontHalfRightRay)
	real_left_input  = get_ray_distance($LeftRay)
	real_right_input = get_ray_distance($RightRay)

func _ready():
	default_material = $Body.material_override
	best_material = StandardMaterial3D.new()
	best_material.albedo_color = Color(0, 1, 0)
	last_position = global_position

	if hidden_neurons.is_empty():
		push_error("Hidden neurons missing!")
		return

	for n in hidden_neurons:
		if n["weights"].size() != INPUT_SIZE:
			n["weights"] = random_weights(INPUT_SIZE)

	if steering_output["weights"].size() != HIDDEN_SIZE:
		steering_output["weights"] = random_weights(HIDDEN_SIZE)
	if throttle_output["weights"].size() != HIDDEN_SIZE:
		throttle_output["weights"] = random_weights(HIDDEN_SIZE)
	if brake_output["weights"].size() != HIDDEN_SIZE:
		brake_output["weights"] = random_weights(HIDDEN_SIZE)


func set_best(is_best: bool):
	if is_best:
		$Body.material_override = best_material
		label.modulate = Color(0,1,0) 
	else:
		$Body.material_override = default_material
		label.modulate = Color(1,1,1) 

func check_stuck(delta):
	var moved = global_position.distance_to(last_position)
	if moved < stuck_distance:
		stuck_timer += delta
		fitness -= delta * stuck_multiplier  #carros parados vao ser BEM punidos
	else:
		stuck_timer = 0.0
	last_position = global_position

	if stuck_timer > stuck_limit:
		crash() #e se passar muito tempo, boom

func _physics_process(delta):
	#throttle = 0.0
	CheckRays()
	var inputs = [
		front_input,
		front_left_input,
		left_input,
		right_input,
		front_right_input,
		real_left_input,
		real_right_input
	]
	
	var hidden_outputs = []
	
	for neuron_data in hidden_neurons:
		var output = neuron(
			inputs,
			neuron_data["weights"],
			neuron_data["bias"]
		)
		hidden_outputs.append(output)
	
	var steering_raw = neuron(hidden_outputs, steering_output["weights"], steering_output["bias"])
	var throttle_raw = neuron(hidden_outputs, throttle_output["weights"], throttle_output["bias"])
	var brake_raw = neuron(hidden_outputs, brake_output["weights"], brake_output["bias"])
	steering = clamp(steering_raw, -1.0, 1.0)
	throttle = clamp(throttle_raw, 0, 1.0)
	var brake_strength = clamp(brake_raw, 0.0, 1.0)
	
	
	#current_brake = move_toward(
	#current_brake,
	#brake_strength,
	#delta * 1.5
	#)
	
	#print(steering)
	rotate_y(steering * turn_speed * delta)
	
	
	##var output = (front_input * weight_front) + (left_input * weight_left) + (right_input * weight_right) + bias
	#
	#
	#var output = right_input - left_input
	#rotate_y(-output * turn_speed * delta)
#
	#
	#print(front_input, left_input, right_input)
	##if Input.is_action_pressed("ui_left"):
	##	rotate_y(turn_speed * delta)
#
	##if Input.is_action_pressed("ui_right"):
	##	rotate_y(-turn_speed * delta)
#
	#if Input.is_action_pressed("ui_up"):
	velocitytarget = speed * throttle * (1.0 - brake_strength * 0.5)
	#else:
	#	velocitytarget = 0

	if current_speed < velocitytarget:
		current_speed = move_toward(current_speed, velocitytarget, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, velocitytarget, brake * delta)
	
	velocity = -transform.basis.z * current_speed
	
	fitness += current_speed * delta * (0.2 + abs(steering) * 0.1)
	move_and_slide()
	check_stuck(delta)
	check_wall_hit(delta)
	if stuck_on_wall > wall_limit:
		crash()
	update_progress()
