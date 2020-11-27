extends EditorSpatialGizmoPlugin


const RiverManager = preload("res://addons/river_tool/river_manager.gd")
const HANDLES_PER_POINT = 5

var editor_plugin : EditorPlugin

var _path_mat
var _handle_lines_mat

func _init() -> void:
	create_handle_material("handles")
	#create_material("path", Color(1.0, 1.0, 0.0))
	#create_material("handle_lines", Color(1.0, 1.0, 0.0))
	var mat = SpatialMaterial.new()
	mat.set_flag(SpatialMaterial.FLAG_UNSHADED, true)
	mat.set_flag(SpatialMaterial.FLAG_DISABLE_DEPTH_TEST, true)
	mat.set_albedo(Color(1.0, 1.0, 0.0))
	add_material("path", mat)
	add_material("handle_lines", mat)


func get_name() -> String:
	return "RiverInput"


func has_gizmo(spatial) -> bool:
	return spatial is RiverManager


func get_handle_name(gizmo: EditorSpatialGizmo, index: int) -> String:
	return "Handle " + String(index)


func get_handle_value(gizmo: EditorSpatialGizmo, index: int):
	var p_index = index / HANDLES_PER_POINT
	var river : RiverManager = gizmo.get_spatial_node()
	if index % HANDLES_PER_POINT == 0:
		return river.curve.get_point_position(p_index)
	if index % HANDLES_PER_POINT == 1:
		return river.curve.get_point_in(p_index)
	if index % HANDLES_PER_POINT == 2:
		return river.curve.get_point_out(p_index)
	if index % HANDLES_PER_POINT == 3 or  index % HANDLES_PER_POINT == 4:
		return river.widths[p_index] 


# Called when handle is moved
func set_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	var river : RiverManager = gizmo.get_spatial_node()

	var global_transform : Transform = river.transform
	if river.is_inside_tree():
		global_transform = river.get_global_transform()
	var global_inverse: Transform = global_transform.affine_inverse()

	var ray_from = camera.project_ray_origin(point)
	var ray_dir = camera.project_ray_normal(point)

	var old_pos : Vector3
	var p_index = int(index / HANDLES_PER_POINT)
	var base = river.curve.get_point_position(p_index)
	
	# Logic to move handles
	if index % HANDLES_PER_POINT == 0:
		old_pos = base
	if index % HANDLES_PER_POINT == 1:
		old_pos = river.curve.get_point_in(p_index) + base
	if index % HANDLES_PER_POINT == 2:
		old_pos = river.curve.get_point_out(p_index) + base
	if index % HANDLES_PER_POINT == 3:
		old_pos = base + river.curve.get_point_out(p_index).cross(Vector3.UP).normalized() * river.widths[p_index]
		print("(3) old pos is: ", old_pos)
	if index % HANDLES_PER_POINT == 4:
		old_pos = base + river.curve.get_point_out(p_index).cross(Vector3.DOWN).normalized() * river.widths[p_index]
		print("(4) old pos is: ", old_pos)
	
	# Point, in and out handles
	if index % HANDLES_PER_POINT <= 2:
		var old_pos_global := river.to_global(old_pos)
		var new_pos
		if editor_plugin.snap_to_colliders:
			# TODO - make in / out handles snap to a plane based on the normal of
			# the raycast hit instead.
			var space_state := river.get_world().direct_space_state
			var result = space_state.intersect_ray(ray_from, ray_from + ray_dir * 4096)
			if result:
				new_pos = result.position
			else:
				return
		else:
			var plane := Plane(old_pos_global, old_pos_global + camera.transform.basis.x, old_pos_global + camera.transform.basis.y)
			new_pos = plane.intersects_ray(ray_from, ray_from + ray_dir * 4096)
			if not new_pos:
				return
		var new_pos_local := river.to_local(new_pos)

		if index % HANDLES_PER_POINT == 0:
			river.set_curve_point_position(p_index, new_pos_local)
		if index % HANDLES_PER_POINT == 1:
			river.set_curve_point_in(p_index, new_pos_local - base)
			river.set_curve_point_out(p_index, -(new_pos_local - base))
		if index % HANDLES_PER_POINT == 2:
			river.set_curve_point_out(p_index, new_pos_local - base)
			river.set_curve_point_in(p_index, -(new_pos_local - base))
	
	# Widths handles
	if index % HANDLES_PER_POINT >= 3:
		var p1 = base
		var p2
		if index % HANDLES_PER_POINT == 3:
			p2 = river.curve.get_point_out(p_index).cross(Vector3.UP).normalized() * 4096
		if index % HANDLES_PER_POINT == 4:
			p2 = river.curve.get_point_out(p_index).cross(Vector3.DOWN).normalized() * 4096
		var g1 = global_inverse.xform(ray_from)
		var g2 = global_inverse.xform(ray_from + ray_dir * 4096)
		
		var geo_points = Geometry.get_closest_points_between_segments(p1, p2, g1, g2)
		var dir = geo_points[0].distance_to(base) - old_pos.distance_to(base)
		
		river.widths[p_index] += dir
	
	redraw(gizmo)

# Handle Undo / Redo of handle movements
func commit_handle(gizmo: EditorSpatialGizmo, index: int, restore, cancel: bool = false) -> void:
	var river : RiverManager = gizmo.get_spatial_node()
	
	var ur = editor_plugin.get_undo_redo()
	ur.create_action("Change River Shape")
	
	var p_index = index / HANDLES_PER_POINT
	if index % HANDLES_PER_POINT == 0:
		ur.add_do_method(river, "set_curve_point_position", p_index, river.curve.get_point_position(p_index))
		ur.add_undo_method(river, "set_curve_point_position", p_index, restore)
	if index % HANDLES_PER_POINT == 1:
		ur.add_do_method(river, "set_curve_point_in", p_index, river.curve.get_point_in(p_index))
		ur.add_undo_method(river, "set_curve_point_in", p_index, restore)
		ur.add_do_method(river, "set_curve_point_out", p_index, river.curve.get_point_out(p_index))
		ur.add_undo_method(river, "set_curve_point_out", p_index, -restore)
	if index % HANDLES_PER_POINT == 2:
		ur.add_do_method(river, "set_curve_point_out", p_index, river.curve.get_point_out(p_index))
		ur.add_undo_method(river, "set_curve_point_out", p_index, restore)
		ur.add_do_method(river, "set_curve_point_in", p_index, river.curve.get_point_in(p_index))
		ur.add_undo_method(river, "set_curve_point_in", p_index, -restore)
	if index % HANDLES_PER_POINT == 3 or index % HANDLES_PER_POINT == 4:
		var river_widths_undo := river.widths.duplicate(true)
		river_widths_undo[p_index] = restore
		ur.add_do_property(river, "widths", river.widths)
		ur.add_undo_property(river, "widths", river_widths_undo)
	
	ur.add_do_method(river, "properties_changed")
	ur.add_undo_method(river, "properties_changed")
	ur.commit_action()
	
	redraw(gizmo)

func redraw(gizmo: EditorSpatialGizmo) -> void:
	# Work around for issue where using "get_material" doesn't return a
	# material when redraw is being called manually from _set_handle()
	# so I'm caching the materials instead
	if not _path_mat:
		_path_mat = get_material("path", gizmo)
	if not _handle_lines_mat:
		_handle_lines_mat = get_material("handle_lines", gizmo)
	gizmo.clear()
	
	var river := gizmo.get_spatial_node() as RiverManager
	
	if not river.is_connected("river_changed", self, "redraw"):
		river.connect("river_changed", self, "redraw", [gizmo])
	
	_draw_path(gizmo, river.curve)
	_draw_handles(gizmo, river)

func _draw_path(gizmo: EditorSpatialGizmo, curve : Curve3D) -> void:
	var path = PoolVector3Array()
	var baked_points = curve.get_baked_points()
	
	for i in baked_points.size() - 1:
		path.append(baked_points[i])
		path.append(baked_points[i + 1])
	
	gizmo.add_lines(path, _path_mat)

func _draw_handles(gizmo: EditorSpatialGizmo, river : RiverManager) -> void:
	var handles = PoolVector3Array()
	var lines = PoolVector3Array()
	for i in river.curve.get_point_count():
		var point_pos = river.curve.get_point_position(i)
		var point_pos_in = river.curve.get_point_in(i) + point_pos
		var point_pos_out = river.curve.get_point_out(i) + point_pos
		var point_width_pos_right = river.curve.get_point_position(i) + river.curve.get_point_out(i).cross(Vector3.UP).normalized() * river.widths[i]
		var point_width_pos_left = river.curve.get_point_position(i) + river.curve.get_point_out(i).cross(Vector3.DOWN).normalized() * river.widths[i]
		
		handles.push_back(point_pos)
		handles.push_back(point_pos_in)
		handles.push_back(point_pos_out)
		handles.push_back(point_width_pos_right)
		handles.push_back(point_width_pos_left)
		
		lines.push_back(point_pos)
		lines.push_back(point_pos_in)
		lines.push_back(point_pos)
		lines.push_back(point_pos_out)
		lines.push_back(point_pos)
		lines.push_back(point_width_pos_right)
		lines.push_back(point_pos)
		lines.push_back(point_width_pos_left)
		
	gizmo.add_lines(lines, _handle_lines_mat)
	gizmo.add_handles(handles, get_material("handles", gizmo))
