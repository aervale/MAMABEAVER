extends Node

# Written with Claude, please take with a grain of salt. Looks good but wanted to disclose this speific file as AI generated.

# --- Variables -------------------------------------------------------------

var untyped = 4              # Variant, holds anything (Python default)
var inferred := 4            # int, type inferred. NOT the walrus operator.
var explicit: int = 4        # int, spelled out
var nothing = null           # null, not None
var flag := true             # true / false, not True / False

const MAX_HP := 100          # constant
enum State { IDLE, WALK }    # State.IDLE == 0


# --- Types -----------------------------------------------------------------

var s: String = "text"
var f: float = 2.5
var arr: Array[int] = [1, 2, 3]
var dict: Dictionary = {"hp": 10}
var vec := Vector3(1, 2, 3)


# --- Functions -------------------------------------------------------------

# `-> void` means returns nothing. Types are optional but expected here.
func add(a: int, b: int = 0) -> int:
	return a + b

# No *args, no **kwargs, and NO keyword arguments at the call site.
# add(1, b = 2) is invalid; defaults fill left to right only.


func _ready() -> void:
	print(add(1, 2))
	numbers()
	strings()
	collections()
	control_flow()


# --- Numbers ---------------------------------------------------------------

func numbers() -> void:
	print(7 / 2)            # 3, not 3.5 - int/int truncates. There is no //
	print(7.0 / 2)          # 3.5
	print(7 % 2)            # ints only; floats use fmod(7.5, 2.0)
	print(2 ** 10)          # 1024
	print(int("42"), str(42))
	print(round(2.6), abs(-3), min(1, 2), max(1, 2))
	# ints are 64-bit and overflow. No arbitrary precision.


# --- Strings ---------------------------------------------------------------

func strings() -> void:
	var text := "Hello, Godot"
	print(text.length())         # not len(text)
	print(text.to_upper())
	print(text.split(", "))
	print(", ".join(["a", "b"]))
	print(text.substr(0, 5))     # no text[0:5] slicing
	print("Go" in text)          # substring test works

	# No f-strings:
	print("%s has %d hp" % ["Player", 87])
	print("{name} wins".format({"name": "Player"}))

	print("a", "b")              # prints "ab" - no space, unlike Python
	prints("a", "b")             # prints "a b"


# --- Collections -----------------------------------------------------------

func collections() -> void:
	# Array == Python list, same reference semantics.
	var xs := [3, 1, 2]
	xs.append(4)
	xs.erase(1)              # remove by VALUE
	xs.remove_at(0)          # remove by INDEX
	print(xs.size(), xs.has(2), xs[-1])
	print(xs.slice(0, 2))    # instead of xs[0:2]
	xs.sort()
	print(xs.duplicate())    # explicit copy

	# Dictionary == Python dict, insertion-ordered.
	var d := {"hp": 10, "mp": 5}
	d["gold"] = 7
	print(d.has("hp"), d.get("miss", 0), d.keys(), d.values())
	for key in d:            # iterates keys; there is no d.items()
		print(key, d[key])

	# No tuples, no sets, no list comprehensions.
	print([1, 2, 3, 4].filter(func(x): return x % 2 == 0))
	print([1, 2, 3].map(func(x): return x * x))


# --- Control flow ----------------------------------------------------------

func control_flow() -> void:
	var n := 5

	if n > 10:
		pass
	elif n > 3:
		print("mid")
	else:
		pass

	print(n if n > 0 else -n)     # ternary, same as Python
	print(n > 0 and n < 10)       # and / or / not all work

	for i in 3:                   # a bare int means range(3)
		print(i)
	for i in range(0, 10, 2):
		print(i)
	for x in [10, 20]:
		print(x)

	while n > 0:
		n -= 1
		if n == 2:
			continue
		if n == 1:
			break
	# No for/else or while/else.

	# match replaces if-chains and is stronger than Python's:
	match n:
		0:
			print("zero")
		1, 2:
			print("one or two")     # comma means alternatives
		_:
			print("anything else")  # _ is the wildcard

	# NO exceptions: no try/except/raise/finally.
	assert(n >= 0, "n must not be negative")
	if n < 0:
		push_error("Tutorial|FATAL: n out of range")


# --- Lambdas ---------------------------------------------------------------

func lambdas() -> void:
	var double := func(x: int) -> int:
		return x * 2        # lambdas take a full body, not one expression
	print(double.call(21))  # call with .call(), not ()


# --- Classes ---------------------------------------------------------------

# Every .gd file is already a class. `extends` at the top sets its base class.
# `class_name Foo` would register it globally (GDScript has no `import`).

class Animal:
	var display_name: String

	func _init(p_name: String) -> void:     # __init__
		display_name = p_name

	func speak() -> String:
		return "..."


class Dog extends Animal:
	func speak() -> String:
		return "woof"


func classes() -> void:
	var d := Dog.new("Rex")     # .new(), not Dog()
	print(d.display_name, d.speak())
	print(d is Animal)          # `is` means isinstance(), not identity
	# `self` is implicit - methods never declare it as a parameter.


# --- Godot-specific --------------------------------------------------------

# The engine calls these for you:
#   _init()                  object created
#   _ready()                 node and its children are in the scene tree
#   _process(delta)          every rendered frame
#   _physics_process(delta)  fixed rate, for movement
#   _input(event)            input handling

@export var speed := 5.0                # editable in the inspector
@onready var _tree := get_tree()        # runs at _ready, not at _init

signal health_changed(new_hp: int)      # built-in observer pattern

func godot_bits() -> void:
	health_changed.connect(_on_health_changed)
	health_changed.emit(90)

	var child := $Label                  # sugar for get_node("Label")
	child.queue_free()                   # free nodes; do not let them leak

	await get_tree().create_timer(1.0).timeout   # coroutine, no asyncio needed


func _on_health_changed(new_hp: int) -> void:
	print("hp is now %d" % new_hp)


# --- What Python has that GDScript does not --------------------------------
# walrus operator, comprehensions, generators/yield, with-statement,
# exceptions, *args/**kwargs, keyword arguments, tuples, sets, slice syntax,
# operator overloading, multiple inheritance, decorators, del, global.
