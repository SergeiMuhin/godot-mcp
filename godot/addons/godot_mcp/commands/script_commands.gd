@tool
extends MCPBaseCommand
class_name MCPScriptCommands


func get_commands() -> Dictionary:
	return {
		"get_current_script": get_current_script,
		"attach_script": attach_script,
		"detach_script": detach_script,
		"create_csharp_script": create_csharp_script,
	}


func get_current_script(_params: Dictionary) -> Dictionary:
	var script_editor := EditorInterface.get_script_editor()
	if not script_editor:
		return _success({"path": null, "content": null})

	var current_script := script_editor.get_current_script()
	if not current_script:
		return _success({"path": null, "content": null})

	var path := current_script.resource_path
	var content := current_script.source_code

	# C# scripts are external files — source_code is empty, read from disk instead
	if content.is_empty() and path.ends_with(".cs"):
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var f := FileAccess.open(abs_path, FileAccess.READ)
			if f:
				content = f.get_as_text()
				f.close()

	return _success({"path": path, "content": content})


func attach_script(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var script_path: String = params.get("script_path", "")

	if node_path.is_empty():
		return _error("INVALID_PARAMS", "node_path is required")
	if script_path.is_empty():
		return _error("INVALID_PARAMS", "script_path is required")

	var node := _get_node(node_path)
	if not node:
		return _error("NODE_NOT_FOUND", "Node not found: %s" % node_path)

	if not FileAccess.file_exists(script_path):
		return _error("FILE_NOT_FOUND", "Script file not found: %s" % script_path)

	var script := load(script_path) as Script
	if not script:
		return _error("LOAD_FAILED", "Failed to load script: %s" % script_path)

	node.set_script(script)

	EditorInterface.get_resource_filesystem().scan()
	script.reload()

	if node.get_script() != script:
		return _error("ATTACH_FAILED", "Script attachment did not persist")

	var scene_root := EditorInterface.get_edited_scene_root()
	return _success({"node_path": str(scene_root.get_path_to(node)), "script_path": script_path})


func detach_script(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")

	if node_path.is_empty():
		return _error("INVALID_PARAMS", "node_path is required")

	var node := _get_node(node_path)
	if not node:
		return _error("NODE_NOT_FOUND", "Node not found: %s" % node_path)

	node.set_script(null)

	return _success({})


func create_csharp_script(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var script_path: String = params.get("script_path", "")
	var class_name_param: String = params.get("class_name", "")
	var base_class: String = params.get("base_class", "")

	if script_path.is_empty():
		return _error("INVALID_PARAMS", "script_path is required (e.g. res://Player.cs)")
	if not script_path.ends_with(".cs"):
		return _error("INVALID_PARAMS", "script_path must end with .cs")
	if class_name_param.is_empty():
		# Derive class name from file name
		class_name_param = script_path.get_file().get_basename()

	# Infer base class from the node if not provided
	if base_class.is_empty() and not node_path.is_empty():
		var node := _get_node(node_path)
		if node:
			base_class = node.get_class()

	if base_class.is_empty():
		base_class = "Node"

	var abs_path := ProjectSettings.globalize_path(script_path)

	if FileAccess.file_exists(abs_path):
		return _error("FILE_EXISTS", "Script already exists: %s" % script_path)

	# Ensure directory exists
	var dir := abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return _error("DIR_CREATE_FAILED", "Could not create directory: %s" % dir)

	var content := "using Godot;\n\npublic partial class %s : %s\n{\n}\n" % [class_name_param, base_class]

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if not f:
		return _error("WRITE_FAILED", "Could not write file: %s" % script_path)
	f.store_string(content)
	f.close()

	EditorInterface.get_resource_filesystem().scan()

	if not node_path.is_empty():
		var node := _get_node(node_path)
		if not node:
			return _error("NODE_NOT_FOUND", "Script created but node not found: %s" % node_path)

		# Wait for the filesystem scan to register the new file
		await Engine.get_main_loop().process_frame
		await Engine.get_main_loop().process_frame

		var script := load(script_path) as Script
		if not script:
			return _error("LOAD_FAILED", "Script created but could not load: %s" % script_path)

		node.set_script(script)

		var scene_root := EditorInterface.get_edited_scene_root()
		return _success({
			"script_path": script_path,
			"class_name": class_name_param,
			"base_class": base_class,
			"node_path": str(scene_root.get_path_to(node)) if scene_root else node_path,
			"attached": true,
		})

	return _success({
		"script_path": script_path,
		"class_name": class_name_param,
		"base_class": base_class,
		"attached": false,
	})
