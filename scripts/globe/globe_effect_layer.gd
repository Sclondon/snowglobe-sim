class_name GlobeEffectLayer
extends MeshInstance3D
## Base for glowing effect layers (aurora, sun rays, rainbow): finds the
## globe, rebuilds the mesh when the globe or a setting changes, and feeds the
## globe's shake level to the shader every frame. Subclasses provide
## _shader() and _build_mesh().

var _globe: SnowGlobe
var _mat: ShaderMaterial
var _build_queued := false


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("%s must be inside a SnowGlobe." % get_class())
		return
	_mat = ShaderMaterial.new()
	_mat.shader = _shader()
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_globe.rebuilt.connect(_queue_build)
	_build()


func _queue_build() -> void:
	if _build_queued or _globe == null or not is_inside_tree():
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	if _globe == null:
		return
	mesh = _build_mesh()
	custom_aabb = GlobeParticles.glass_aabb(_globe)
	_mat.set_shader_parameter("size", _globe.globe_radius)
	_apply_params()


func _physics_process(_delta: float) -> void:
	if _mat and _globe:
		_mat.set_shader_parameter("agitation", _globe.agitation)


## Pushes exported settings into the shader (subclasses override).
func _apply_params() -> void:
	pass


func _shader() -> Shader:
	return null


func _build_mesh() -> Mesh:
	return null


## Adds a quad strip vertex with UV.
static func _v(st: SurfaceTool, p: Vector3, uv: Vector2) -> void:
	st.set_uv(uv)
	st.add_vertex(p)
