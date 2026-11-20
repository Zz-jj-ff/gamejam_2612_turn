extends RefCounted
class_name MeshBuilder
## Tiny indexed mesh accumulator used by every generator in this project.
## Vertices are emitted with explicit normals so smooth shading is fully
## controlled by the math (no auto-normal / tangent weirdness).
##
## Winding: Godot treats clockwise (seen from outside) as front.  We check the
## geometric normal of each triangle against a supplied guide normal and emit
## the opposite order, matching MeshKit's convention in the sibling projects.

var V := PackedVector3Array()
var N := PackedVector3Array()
var UV := PackedVector2Array()
var UV2 := PackedVector2Array()
var C := PackedColorArray()
var T := PackedFloat32Array()   # vec4 tangent per vertex
var BI := PackedInt32Array()    # 4 bone indices per vertex
var BW := PackedFloat32Array()  # 4 bone weights per vertex
var I := PackedInt32Array()


func clear() -> void:
	V.clear()
	N.clear()
	UV.clear()
	UV2.clear()
	C.clear()
	T.clear()
	BI.clear()
	BW.clear()
	I.clear()


func add_vert(p: Vector3, n: Vector3, uv := Vector2.ZERO,
		uv2 := Vector2.ZERO, c := Color.WHITE) -> int:
	V.append(p)
	N.append(n)
	UV.append(uv)
	UV2.append(uv2)
	C.append(c)
	T.append(1.0)
	T.append(0.0)
	T.append(0.0)
	T.append(1.0)
	BI.append(0)
	BI.append(0)
	BI.append(0)
	BI.append(0)
	BW.append(1.0)
	BW.append(0.0)
	BW.append(0.0)
	BW.append(0.0)
	return V.size() - 1


## Assign up to four bones/weights to a vertex (indexed skinning).
func set_skin(i: int, b: Array, w: Array) -> void:
	for k in 4:
		BI[i * 4 + k] = int(b[k]) if k < b.size() else 0
		BW[i * 4 + k] = float(w[k]) if k < w.size() else 0.0


## Sets the strand tangent (must be already perpendicular to the vertex normal).
func set_tangent(i: int, tan: Vector3) -> void:
	var t := tan.normalized()
	T[i * 4 + 0] = t.x
	T[i * 4 + 1] = t.y
	T[i * 4 + 2] = t.z
	T[i * 4 + 3] = 1.0


func add_tri(i0: int, i1: int, i2: int, guide: Vector3) -> void:
	if i0 < 0 or i1 < 0 or i2 < 0:
		return
	var a := V[i0]
	var b := V[i1]
	var c := V[i2]
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-20:
		return
	if g.dot(guide) > 0.0:
		I.append(i0)
		I.append(i2)
		I.append(i1)
	else:
		I.append(i0)
		I.append(i1)
		I.append(i2)


func add_quad(i0: int, i1: int, i2: int, i3: int, guide: Vector3) -> void:
	add_tri(i0, i1, i2, guide)
	add_tri(i0, i2, i3, guide)


## Adds a triangle whose vertices are already ordered; winding is fixed by guide.
func add_tri_pair(i0: int, i1: int, i2: int, i3: int, guide: Vector3) -> void:
	add_quad(i0, i1, i2, i3, guide)


func commit(mesh_name := "") -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if V.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = N
	arrays[Mesh.ARRAY_TEX_UV] = UV
	arrays[Mesh.ARRAY_TEX_UV2] = UV2
	arrays[Mesh.ARRAY_COLOR] = C
	arrays[Mesh.ARRAY_TANGENT] = T
	if not BI.is_empty():
		arrays[Mesh.ARRAY_BONES] = BI
		arrays[Mesh.ARRAY_WEIGHTS] = BW
	arrays[Mesh.ARRAY_INDEX] = I
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = mesh_name
	return mesh


func vertex_count() -> int:
	return V.size()


## Concatenates another builder (positions/normals/uvs carried over).
func append(other: MeshBuilder, xform := Transform3D.IDENTITY) -> void:
	var base := V.size()
	for i in other.V.size():
		V.append(xform * other.V[i])
		N.append((xform.basis * other.N[i]).normalized())
		UV.append(other.UV[i] if i < other.UV.size() else Vector2.ZERO)
		UV2.append(other.UV2[i] if i < other.UV2.size() else Vector2.ZERO)
		C.append(other.C[i] if i < other.C.size() else Color.WHITE)
		var tx := other.T[i * 4 + 0]
		var ty := other.T[i * 4 + 1]
		var tz := other.T[i * 4 + 2]
		var tw := other.T[i * 4 + 3]
		var bt := (xform.basis * Vector3(tx, ty, tz)).normalized()
		for k in 4:
			BI.append(other.BI[i * 4 + k] if i * 4 + k < other.BI.size() else 0)
			BW.append(other.BW[i * 4 + k] if i * 4 + k < other.BW.size() else (1.0 if k == 0 else 0.0))
		T.append(bt.x)
		T.append(bt.y)
		T.append(bt.z)
		T.append(tw)
	for k in other.I.size():
		I.append(base + other.I[k])

## Appends a committed ArrayMesh (used for prefab pieces such as one hair lock).
func append_mesh(m: ArrayMesh, xform := Transform3D.IDENTITY) -> void:
	if m == null or m.get_surface_count() == 0:
		return
	var arr := m.surface_get_arrays(0)
	if arr.size() == 0:
		return
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var tan = arr[Mesh.ARRAY_TANGENT]
	var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var base := V.size()
	for i in v.size():
		V.append(xform * v[i])
		N.append((xform.basis * nr[i]).normalized())
		UV.append(uv[i] if i < uv.size() else Vector2.ZERO)
		UV2.append(uv2[i] if i < uv2.size() else Vector2.ZERO)
		C.append(col[i] if i < col.size() else Color.WHITE)
		var ab = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else null
		var aw = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else null
		for k in 4:
			BI.append(int(ab[i * 4 + k]) if ab != null and (i * 4 + k) < ab.size() else 0)
			BW.append(float(aw[i * 4 + k]) if aw != null and (i * 4 + k) < aw.size() else (1.0 if k == 0 else 0.0))
		if tan != null and tan.size() >= (i + 1) * 4:
			var bt := (xform.basis * Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])).normalized()
			T.append(bt.x)
			T.append(bt.y)
			T.append(bt.z)
			T.append(tan[i * 4 + 3])
		else:
			T.append(1.0)
			T.append(0.0)
			T.append(0.0)
			T.append(1.0)
	for k in ind.size():
		I.append(base + ind[k])
