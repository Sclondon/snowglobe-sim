@tool
class_name GlobeParticleStyle
extends Resource
## Everything that makes a GlobeParticles node look and move like snow, bubbles,
## glitter, confetti... Save variations as .tres files (see res://particles/)
## and swap them on the node.

enum Shape {
	FLAKE,  ## Soft six-pointed flake, always faces the camera.
	BUBBLE, ## Hollow ring with a highlight, shaded like a little sphere.
	GLITTER, ## Flat metallic chip that tumbles and catches the light.
	RAIN, ## Thin streak stretched along the direction of travel.
	MOTE, ## Soft glowing dot (dust, sparks).
	CLOUD, ## Big soft dithered puff (clouds, fog, smoke).
	CUSTOM, ## Uses custom_mesh / custom_material.
}

@export_group("Look")
@export var shape := Shape.FLAKE:
	set(v): shape = v; emit_changed()
## Diameter in globe-local units (a globe is 1 unit in radius by default).
@export_range(0.001, 0.5, 0.001) var size := 0.03:
	set(v): size = v; emit_changed()
## 0 = all the same size, 1 = anywhere from 0% to 200% of size.
@export_range(0.0, 1.0, 0.01) var size_randomness := 0.4:
	set(v): size_randomness = v; emit_changed()
@export var color := Color(1, 1, 1):
	set(v): color = v; emit_changed()
## If set, each particle picks a random colour from this instead of `color`.
@export var color_gradient: Gradient:
	set(v): color_gradient = v; emit_changed()
## Makes particles glow a little so they read even in shadow.
@export_range(0.0, 4.0, 0.01) var emission := 0.15:
	set(v): emission = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var roughness := 0.7:
	set(v): roughness = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var metallic := 0.0:
	set(v): metallic = v; emit_changed()
## Radians/second each particle spins or tumbles at (randomised per particle).
@export_range(0.0, 30.0, 0.1) var tumble_speed := 1.5:
	set(v): tumble_speed = v; emit_changed()
@export var custom_mesh: Mesh:
	set(v): custom_mesh = v; emit_changed()
## Rain: how much streaks stretch with speed.
@export_range(0.0, 1.0, 0.01) var stretch := 0.12:
	set(v): stretch = v; emit_changed()
@export var custom_material: Material:
	set(v): custom_material = v; emit_changed()

@export_group("Motion")
## Acceleration along gravity. Positive sinks (snow), negative rises (bubbles).
@export_range(-10.0, 10.0, 0.01) var gravity := 0.5
## How thick the liquid feels. Terminal speed is roughly gravity / drag.
@export_range(0.0, 20.0, 0.01) var drag := 2.5
## How strongly moving the globe flings the particles around.
@export_range(0.0, 2.0, 0.001) var shake_response := 0.12
## How much the particles get carried by the liquid swirling after the globe
## is turned.
@export_range(0.0, 2.0, 0.01) var swirl_response := 1.0
## Random wandering, always present.
@export_range(0.0, 2.0, 0.001) var turbulence := 0.04
## Extra wandering right after a shake.
@export_range(0.0, 5.0, 0.01) var shake_turbulence := 0.6
## Wind: how fast the fill circles around the globe's axis (globe radii / s).
@export_range(-3.0, 3.0, 0.01) var wind := 0.0
## Wind: steady upward draught.
@export_range(-2.0, 2.0, 0.01) var lift := 0.0
## Bounciness off the glass and floor.
@export_range(0.0, 1.0, 0.01) var restitution := 0.1
## How quickly particles come to rest once they touch a surface.
@export_range(0.0, 50.0, 0.1) var stickiness := 8.0

@export_group("Lifetime")
## Respawn particles that have been resting for pop_delay seconds on the
## far side of the globe (e.g. bubbles pop at the top and reappear below).
@export var pop_at_rest := false
@export_range(0.0, 30.0, 0.1) var pop_delay := 1.5
