import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Imported-model stand-in: what flutter_scene's runtime importer builds
/// (a mirrored root, one node per glTF node, children in glTF order).
Node importLike(Map<String, dynamic> gltf) {
  final nodes = (gltf['nodes'] as List).cast<Map<String, dynamic>>();
  final engine = [for (final n in nodes) Node(name: n['name'] as String)];
  for (var i = 0; i < nodes.length; i++) {
    final t = (nodes[i]['translation'] as List?)?.cast<num>();
    final r = (nodes[i]['rotation'] as List?)?.cast<num>();
    engine[i].localTransform = Matrix4.compose(
      t == null
          ? Vector3.zero()
          : Vector3(t[0].toDouble(), t[1].toDouble(), t[2].toDouble()),
      r == null
          ? Quaternion.identity()
          : Quaternion(
              r[0].toDouble(),
              r[1].toDouble(),
              r[2].toDouble(),
              r[3].toDouble(),
            ),
      Vector3.all(1),
    );
    for (final c in (nodes[i]['children'] as List? ?? const []).cast<int>()) {
      engine[i].add(engine[c]);
    }
  }
  final root = Node(
    name: 'root',
    localTransform: Matrix4.identity()..setEntry(2, 2, -1.0),
  );
  root.add(engine[0]);
  return root;
}
