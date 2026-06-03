extends Node3D

@export var Car: PackedScene
@export var CarParent: Node3D
@export var checkpoint_count = 30
@export var Camera: Node3D
@onready var rank_list = $CanvasLayer/Panel/RankList


var checkpoints = []
var population = []
var population_size = 10
var startPosition = Vector3(2.879, 3.047, -58.8)
var startRotation = Vector3(0, 90, 0)
var best = null
var best_neurons = []
var generation_time = 120
var timer = 0
var generation = 0
var current_track_index = 0
var RaceTrack: Path3D

const INPUT_SIZE = 7
const HIDDEN_SIZE = 6


var race_tracks = []
var names = [
	"Bolt",
	"Nova",
	"Rex",
	"Luna",
	"Viper",
	"Echo",
	"Zed",
	"John",
	"Neo",
	"Drift",
	"Axel",
	"Raze",
	"Nyx",
	"Orion",
	"Flux",
	"Jett",
	"Max",
	"Skye",
	"Vex",
	"Rune",
	"Atom",
	"Zero",
	"Apex",
	"Lynx",
	"Sable",
	"Ion",
	"Kiro",
	"Vega",
	"Storm",
	"Pixel",
	"Ross"
]

var available_names = []

func get_random_name():
	return names[randi() % names.size()]

var base_neurons = [
	# "nada em frente": gosta da frente e de diagonais e odeia paredes de todos os lados
	{ "weights": [ 1.0,  0.8, -0.3, -0.3,  0.8, -0.5, -0.5], "bias": 0.0 },

	# "escapa esquerda": esquerda aberta, direita tem parede, raio esquerda confirma
	{ "weights": [-0.5,  0.3,  1.0, -0.5, -0.3,  0.8, -0.8], "bias": 0.0 },

	# "escapa direita": contrario do de cima
	{ "weights": [-0.5, -0.3, -0.5,  1.0,  0.3, -0.8,  0.8], "bias": 0.0 },

	# "parede em frente, checar cantos": frente bloqueada, raios de lado servem para saber o espaço
	{ "weights": [-1.0,  0.4,  0.3,  0.3,  0.4,  0.6,  0.6], "bias": 0.0 },
	
	# "corredor estreito": todos os raios meio bloqueados, carro em lugar estreito
	{ "weights": [-0.8, -0.6, -0.4, -0.4, -0.6, -0.7, -0.7], "bias": 0.5 },

	# "tudo livre": tudo limpo, carro tem liberdade total
	{ "weights": [ 0.6,  0.5,  0.4,  0.4,  0.5,  0.7,  0.7], "bias": -0.3 },
]

var best_brain = {}

func get_sorted_cars():
	var alive = []

	for c in population:
		if c and c.is_inside_tree():
			alive.append(c)

	alive.sort_custom(func(a, b):
		return a.fitness > b.fitness
	)

	return alive

func clear_container(container):
	for child in container.get_children():
		child.queue_free()

func update_ranking_ui():
	clear_container(rank_list)

	var cars = get_sorted_cars()

	for i in range(min(10, cars.size())):
		var c = cars[i]
		c.current_rank = i + 1
		
		#var gained = c.previous_rank - c.current_rank
			#c.fitness += gained * 20
			
		c.previous_rank = c.current_rank
		
		var label = Label.new()
		label.text = str(i + 1) + " - " + c.car_name + " | " + str(int(c.fitness)) + " | " + str(int(c.velocitytarget))
		if i == 0:
			label.modulate = Color(1.0, 0.8, 0.0, 1.0)
		elif i == 1:
			label.modulate = Color(0.819, 0.807, 0.799, 1.0)
		elif i == 2:
			label.modulate = Color(0.57, 0.333, 0.0, 1.0)
		rank_list.add_child(label)

func reset_names():
	available_names = names.duplicate()

func create_checkpoints():
	checkpoints.clear()

	var curve = RaceTrack.curve
	var length = curve.get_baked_length()

	for i in range(checkpoint_count):
		var t = float(i) / (checkpoint_count - 1)

		var pos = curve.sample_baked(length * t)

		checkpoints.append(pos)
		
func all_dead():
	for car in population:
		if car != null and car.is_inside_tree():
			if not car.alive:
				continue
			return false
			
	return true

func mutate(value, rate):
	return value + randf_range(-rate, rate)

func mutate_neuron(neuron_data):
	var new_weights = []
	
	for w in neuron_data["weights"]:
		new_weights.append(mutate(w, 0.1))
	
	var new_bias = mutate(neuron_data["bias"], 0.1)
	
	return {
		"weights": new_weights,
		"bias": new_bias
	}


func get_unique_name():
	if available_names.is_empty():
		return "Unnamed"

	var index = randi() % available_names.size()
	var newName = available_names[index]
	available_names.remove_at(index)

	return newName
	
func spawn_population():
	var car_scene = preload("res://Car.tscn")

	var base_steering = { "weights": [ 1.0, -1.0,  0.5,  0.2, -0.3,  0.3], "bias": 0.0 }
	var base_throttle = { "weights": [ 0.2,  0.5, -0.3,  1.0,  0.6,  0.4], "bias": 0.0 }
	var base_brake    = { "weights": [-0.6,  1.0,  1.0, -0.2, -0.5, -0.5], "bias": 0.0 }

	for i in range(population_size):
		var car = car_scene.instantiate()

		var new_hidden = []

		for neuron in base_neurons:
			new_hidden.append(mutate_neuron(neuron))

		car.hidden_neurons = new_hidden
		car.steering_output = mutate_neuron(base_steering)
		car.throttle_output = mutate_neuron(base_throttle)
		car.brake_output = mutate_neuron(base_brake)

		CarParent.add_child(car)

		car.global_position = startPosition
		car.rotation_degrees = startRotation
		car.velocity = Vector3.ZERO

		car.path = RaceTrack
		car.define_name(get_unique_name())

		population.append(car)


func next_generation():
	if best_brain == null:
		print("Not yet")
		return

	for car in population:
		var new_hidden = []

		for n in best_brain["hidden"]:
			new_hidden.append(mutate_neuron(n))

		car.hidden_neurons = new_hidden
		car.steering_output = mutate_neuron(best_brain["steering"])
		car.throttle_output = mutate_neuron(best_brain["throttle"])
		car.brake_output = mutate_neuron(best_brain["brake"])

		car.global_position = startPosition
		car.rotation_degrees = startRotation
		car.velocity = Vector3.ZERO
		
		car.reset()
		car.define_name(get_unique_name())



func end_generation():
	if population.is_empty():
		return

	population.sort_custom(func(a, b):
		return a.fitness > b.fitness
	)
	best_neurons = population[0].hidden_neurons.duplicate(true)
	best_brain = {
	"hidden": population[0].hidden_neurons.duplicate(true),
	"steering": population[0].steering_output.duplicate(true),
	"throttle": population[0].throttle_output.duplicate(true),
	"brake": population[0].brake_output.duplicate(true)
	}

func new_generation():
	reset_names()
	end_generation()
	next_generation()
	timer = 0
	generation += 1
	print("Generation:", generation)

func highlight_best():
	var best_car = null
	var best_fitness = -INF

	for car in population:
		if car.fitness > best_fitness:
			best_fitness = car.fitness
			best_car = car
	
	for car in population:
		car.set_best(false)
	
	if best_car != null:
		best_car.set_best(true)
		Camera.best_car = best_car


func load_track(index):
	current_track_index = wrapi(index, 0, race_tracks.size())

	var track_data = race_tracks[current_track_index]

	RaceTrack = track_data["path"]
	startPosition = track_data["start_position"]
	print(startPosition)
	startRotation = track_data["start_rotation"]

	create_checkpoints()

	for car in population:
		car.path = RaceTrack
		car.global_position = startPosition
		car.rotation_degrees = startRotation
		car.reset()

func _ready():
	race_tracks = [
	{
		"path": $RaceTrack,
		"start_position": Vector3(2.879, 3.047, -58.8),
		"start_rotation": Vector3(0, 90, 0)
	},
	{
		"path": $RaceTrack2,
		"start_position": Vector3(615.074, 3.047, 152.871),
		"start_rotation": Vector3(0, 0, 0)
	},
		]
	load_track(0)

	spawn_population()

func save_brain(brain_data, file_name = "brain.json"):
	var file = FileAccess.open("user://" + file_name, FileAccess.WRITE)

	if file == null:
		print("Failed to save brain")
		return

	var json = JSON.stringify(brain_data)

	file.store_string(json)
	file.close()

	print("Brain saved:", file_name)


func load_brain(file_name = "brain.json"):
	if not FileAccess.file_exists("user://" + file_name):
		print("Brain file not found")
		return null

	var file = FileAccess.open("user://" + file_name, FileAccess.READ)

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var result = json.parse(content)

	if result != OK:
		print("Failed to parse brain")
		return null

	return json.data


func _process(delta):
	timer += delta
	
	highlight_best()
	if timer >= generation_time or all_dead():
		new_generation()
	
	update_ranking_ui()
	
	if Input.is_action_just_pressed("NextTrack"):
		load_track(current_track_index + 1)

	if Input.is_action_just_pressed("PreviousTrack"):
		load_track(current_track_index - 1)
	#for i in range(population.size()):
		#var c = population[i]
		#if c.alive:
			#c.fitness += (population.size() - i) * delta
