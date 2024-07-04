extends PTMesh


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()

	var mesh = $Armature/Skeleton3D/Grimm.mesh

	var mesh_tool = MeshDataTool.new()

	mesh_tool.create_from_surface(mesh, 0)

	var mesh_arrays : Array = mesh.surface_get_arrays(0)
	#print(mesh_arrays)

	var mesh_array : ArrayMesh = ArrayMesh.new()
	mesh_array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	#print(mesh_array._surfaces)
	mesh_array.surface_set_name(0, "my surfACE")
	#print(mesh_array.surface_get_name(0))
	#print(mesh_array.surface_get_arrays(0))
	#mesh.

	var unique_vertices = PackedVector3Array([])

	for vertex in mesh_arrays[0]:
		if not vertex in unique_vertices:
			unique_vertices.append(vertex)


	# Goal: Group vertices and all vertex data by

	print("Vertices in mesh")
	print(unique_vertices.size())

	print("\nTriangles in mesh:")
	print(mesh_arrays[-1].size() / 3)

	print()
	#print(mesh_arrays[ArrayMesh.ARRAY_BONES].slice(0, 128))
	#print(mesh_arrays[ArrayMesh.ARRAY_WEIGHTS].slice(0, 128))
	#print(ArrayMesh.ARRAY_FORMAT_BONES)
	#print(ArrayMesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	#print(mesh.surface_get)

	print_boens_and_weigths(mesh_arrays)


	print()
	for sub_array in mesh_arrays:
		#if [] is Array:
			#print("true")
		if sub_array != null:
			print(len(sub_array), ", ", type_string(typeof(sub_array)))
		else:
			print("null")

	mesh_tool

	#get_tree().quit()


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass


## Remove duplicate vertex data in surface array. Returns new array without duplicates.
## Surface sub-arrays this function supports
## - vertex
## - normal
## - tangent/binormal # maybe not
## - UV
## - bones
## - weights
## - indices
func compress_surface_array(surface : Array) -> Array[Array]:

	var new_surface : Array[Array] = []
	new_surface.resize(ArrayMesh.ARRAY_MAX)


	# PackedVector**Arrays for mesh construction.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array() # Can also be float 32 according to docs

	var indices := PackedInt32Array()

	# Assign arrays to surface array.
	new_surface[Mesh.ARRAY_VERTEX] = verts
	new_surface[Mesh.ARRAY_TEX_UV] = uvs
	new_surface[Mesh.ARRAY_NORMAL] = normals
	new_surface[Mesh.ARRAY_INDEX] = indices

	#######################################
	## Insert code here to generate mesh ##
	#######################################





	for vertex in surface[ArrayMesh.ARRAY_VERTEX]:
		pass




	return [[]]


func print_boens_and_weigths(surface : Array) -> void:

	#print(mesh_arrays[ArrayMesh.ARRAY_BONES].slice(0, 128))
	#print(mesh_arrays[ArrayMesh.ARRAY_WEIGHTS].slice(0, 128))
	var unique_bone_weights := {}

	for i in range(surface[ArrayMesh.ARRAY_VERTEX].size()):
		#print(surface[ArrayMesh.ARRAY_BONES].slice(i * 8, i * 8 + 8),
			#surface[ArrayMesh.ARRAY_WEIGHTS].slice(i * 8, i * 8 + 8))

		var temp := (str(surface[ArrayMesh.ARRAY_BONES].slice(i * 8, i * 8 + 8)) +
			str(surface[ArrayMesh.ARRAY_WEIGHTS].slice(i * 8, i * 8 + 8)))

		if unique_bone_weights.has(temp):
			unique_bone_weights[temp] += 1
		else:
			unique_bone_weights[temp] = 1


	var temp_array =unique_bone_weights.values()
	temp_array.sort()
	temp_array.reverse()
	print(temp_array)

