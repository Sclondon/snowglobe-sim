@tool
class_name CreatureSpecies
extends Resource
## What a GlobeCreatures layer looks like and how it behaves. Presets live in
## res://creatures/.

enum Body {
	SEA_MONKEY, ## Little swimmer with a waggling tail.
	BUTTERFLY, ## Flapping wings.
	ANT, ## Three body segments and scuttling legs.
	PERSON, ## Tiny figure that walks with swinging arms and legs.
}
enum Movement {
	SWIM, ## Schools through the fill; stranded and flopping in air.
	FLY, ## Flutters through air; sluggish in water.
	WALK, ## Wanders over the floor; knocked over by shaking or tilting.
}

@export_group("Look")
@export var body := Body.SEA_MONKEY:
	set(v): body = v; emit_changed()
## Length (or height, for people) in globe-local units.
@export_range(0.01, 0.4, 0.001) var size := 0.07:
	set(v): size = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var size_randomness := 0.2:
	set(v): size_randomness = v; emit_changed()
## Main body colour (varies per creature by color_variation).
@export var color := Color(1.0, 0.72, 0.6):
	set(v): color = v; emit_changed()
## Hue / brightness spread between individuals.
@export_range(0.0, 1.0, 0.01) var color_variation := 0.15:
	set(v): color_variation = v; emit_changed()
## Fins, lower wings, heads.
@export var accent_color := Color(1.0, 0.55, 0.45):
	set(v): accent_color = v; emit_changed()
## Eyes, legs, bodies of butterflies.
@export var detail_color := Color(0.08, 0.06, 0.06):
	set(v): detail_color = v; emit_changed()
@export_range(0.0, 3.0, 0.01) var emission := 0.1:
	set(v): emission = v; emit_changed()
@export_range(0.1, 4.0, 0.01) var anim_speed := 1.0:
	set(v): anim_speed = v; emit_changed()

@export_group("Behaviour")
@export var movement := Movement.SWIM:
	set(v): movement = v; emit_changed()
## Cruising speed in globe radii per second.
@export_range(0.0, 2.0, 0.01) var speed := 0.3
## How quickly they can change direction.
@export_range(0.1, 10.0, 0.1) var agility := 3.0
## Random wandering.
@export_range(0.0, 3.0, 0.01) var wander := 1.0
## Keep their distance from neighbours.
@export_range(0.0, 3.0, 0.01) var separation := 1.2
## Swim / fly the same way as neighbours.
@export_range(0.0, 3.0, 0.01) var alignment := 0.6
## Stay together as a group.
@export_range(0.0, 3.0, 0.01) var cohesion := 0.4
## How far they notice neighbours, in body lengths.
@export_range(1.0, 10.0, 0.1) var neighbor_radius := 4.0
## How much shaking frightens them.
@export_range(0.0, 3.0, 0.01) var panic := 1.0
## Speed multiplier while panicking.
@export_range(1.0, 6.0, 0.1) var panic_speed := 2.5
## Reaction to a finger on the glass: + comes closer, − flees.
@export_range(-2.0, 2.0, 0.01) var touch_response := 1.0
## Chance per second to stop for a while (butterflies land, people pause).
@export_range(0.0, 1.0, 0.01) var rest_chance := 0.0
@export_range(0.2, 20.0, 0.1) var rest_time := 3.0
## Walkers: how hard they are to knock over.
@export_range(0.1, 5.0, 0.01) var grip := 1.0
## Walkers: tendency to follow the one in front (ant trails).
@export_range(0.0, 1.0, 0.01) var follow_leader := 0.0
