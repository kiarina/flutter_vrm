import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

/// Maps glTF node indices to the [Node]s flutter_scene's runtime importer
/// created, by walking the glTF scene tree and the imported tree together.
///
/// The importer builds one engine node per glTF node and adds children in
/// glTF order, naming each after the glTF node (or `node_<index>`). Names are
/// compared on the way down, so a layout change in the importer fails loudly
/// instead of silently posing the wrong bone.
List<Node?> mapGltfNodes(Map<String, dynamic> gltf, Node importedRoot) {
  final nodes = (gltf['nodes'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final result = List<Node?>.filled(nodes.length, null);
  final scenes = (gltf['scenes'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  if (scenes.isEmpty) return result;
  final sceneIndex = gltf['scene'] as int? ?? 0;
  final roots = (scenes[sceneIndex]['nodes'] as List? ?? const []).cast<int>();

  void walk(int index, Node engine) {
    final name = nodes[index]['name'] as String?;
    final expected = name != null && name.isNotEmpty ? name : 'node_$index';
    if (engine.name != expected) {
      throw StateError(
        'glTF node $index is "$expected" but the imported node is '
        '"${engine.name}"; the importer layout changed',
      );
    }
    result[index] = engine;
    final children = (nodes[index]['children'] as List? ?? const [])
        .cast<int>();
    if (engine.children.length < children.length) {
      throw StateError(
        'glTF node $index has ${children.length} children but the imported '
        'node has ${engine.children.length}',
      );
    }
    for (var i = 0; i < children.length; i++) {
      walk(children[i], engine.children[i]);
    }
  }

  if (importedRoot.children.length < roots.length) {
    throw StateError('imported root lacks the glTF scene roots');
  }
  for (var i = 0; i < roots.length; i++) {
    walk(roots[i], importedRoot.children[i]);
  }
  return result;
}

/// glTF material index -> the engine materials created for it, found through
/// each mesh node's primitives (which the importer keeps in glTF order).
Map<int, Set<Material>> mapGltfMaterials(
  Map<String, dynamic> gltf,
  List<Node?> gltfNodes,
) {
  final nodes = (gltf['nodes'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final meshes = (gltf['meshes'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final out = <int, Set<Material>>{};
  for (var i = 0; i < nodes.length; i++) {
    final meshIndex = nodes[i]['mesh'] as int?;
    final mesh = gltfNodes[i]?.mesh;
    if (meshIndex == null || mesh == null) continue;
    final prims = (meshes[meshIndex]['primitives'] as List)
        .cast<Map<String, dynamic>>();
    if (prims.length != mesh.primitives.length) {
      debugPrint(
        'flutter_vrm: node $i has ${prims.length} glTF primitives but '
        '${mesh.primitives.length} imported ones; its materials are unmapped',
      );
      continue;
    }
    for (var p = 0; p < prims.length; p++) {
      final m = prims[p]['material'] as int?;
      if (m == null) continue;
      (out[m] ??= {}).add(mesh.primitives[p].material);
    }
  }
  return out;
}
