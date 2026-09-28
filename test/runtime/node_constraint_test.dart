import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:flutter_vrm/src/runtime/gltf_mapping.dart';
import 'package:vector_math/vector_math.dart';

import '../support/import_like.dart';
import '../support/synthetic_vrm.dart';

/// The synthetic humanoid plus extra nodes (name -> glTF node JSON without
/// the name) under Root.
({
  List<Node?> nodes,
  Node modelRoot,
  VrmDocument document,
  Map<String, int> ids,
})
constrained(Map<String, Map<String, dynamic>> extra) {
  final json = syntheticVrmJson();
  final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
  final ids = <String, int>{};
  for (final e in extra.entries) {
    ids[e.key] = nodes.length;
    nodes.add({'name': e.key, ...e.value});
    (nodes[0]['children'] as List).add(ids[e.key]);
  }
  // Resolve "@name" sources to indices.
  for (final n in nodes) {
    final c =
        (n['extensions'] as Map<String, dynamic>?)?['VRMC_node_constraint']
            as Map<String, dynamic>?;
    for (final kind
        in (c?['constraint'] as Map<String, dynamic>? ?? const {}).values) {
      final k = kind as Map<String, dynamic>;
      if (k['source'] case final String name) {
        k['source'] = ids[name.substring(1)];
      }
    }
  }
  final imported = importLike(json);
  return (
    nodes: mapGltfNodes(json, imported),
    modelRoot: imported,
    document: VrmDocument.fromGltfJson(json),
    ids: ids,
  );
}

Map<String, dynamic> constraint(String kind, Map<String, dynamic> body) => {
  'extensions': {
    'VRMC_node_constraint': {
      'specVersion': '1.0',
      'constraint': {kind: body},
    },
  },
};

List<double> q(Quaternion x) => [x.x, x.y, x.z, x.w];

Quaternion about(Vector3 axis, double degrees) =>
    Quaternion.axisAngle(axis.normalized(), degrees * math.pi / 180);

Matrix3 localRotation(Node n) {
  final t = Vector3.zero();
  final r = Quaternion.identity();
  final s = Vector3.zero();
  n.localTransform.decompose(t, r, s);
  return r.asRotationMatrix();
}

void setLocalRotation(Node n, Matrix3 r) {
  final t = n.localTransform.getTranslation();
  n.localTransform = Matrix4.compose(
    t,
    Quaternion.fromRotation(r),
    Vector3.all(1),
  );
}

void expectRotation(Matrix3 actual, Matrix3 expected) {
  for (var i = 0; i < 9; i++) {
    expect(actual.storage[i], closeTo(expected.storage[i], 1e-4));
  }
}

void main() {
  final twist = about(Vector3(0.3, 1, -0.4), 50);
  final twist2 = about(Vector3(1, 0.2, 0.5), -35);

  test('parses the three kinds and drops bad sources', () {
    final m = constrained({
      'S': {},
      'R': constraint('roll', {'source': '@S', 'rollAxis': 'Y', 'weight': 0.5}),
      'A': constraint('aim', {'source': '@S', 'aimAxis': 'NegativeZ'}),
      'T': constraint('rotation', {'source': '@S'}),
      'Bad': constraint('rotation', {'source': 9999}),
    });
    final c = m.document.nodeConstraints;
    expect(c, hasLength(3));
    expect((c[0] as VrmRollConstraint).rollAxis, Vector3(0, 1, 0));
    expect(c[0].weight, 0.5);
    expect((c[1] as VrmAimConstraint).aimAxis, Vector3(0, 0, -1));
    expect(c[2], isA<VrmRotationConstraint>());
    expect(c[2].weight, 1);
  });

  test('rotation copies the source delta, scaled by weight', () {
    final m = constrained({
      'S': {'rotation': q(twist)},
      'D': {
        'rotation': q(twist2),
        ...constraint('rotation', {'source': '@S', 'weight': 0.5}),
      },
    });
    final c = VrmNodeConstraints(
      m.document.nodeConstraints,
      m.nodes,
      m.modelRoot,
    );
    final s = m.nodes[m.ids['S']!]!;
    final d = m.nodes[m.ids['D']!]!;
    setLocalRotation(
      s,
      twist.asRotationMatrix() * about(Vector3(0, 1, 0), 60).asRotationMatrix()
          as Matrix3,
    );
    c.update();
    expectRotation(
      localRotation(d),
      twist2.asRotationMatrix() * about(Vector3(0, 1, 0), 30).asRotationMatrix()
          as Matrix3,
    );
  });

  test('roll keeps only the twist about the axis', () {
    final m = constrained({
      'S': {'rotation': q(twist)},
      'D': {
        'rotation': q(twist),
        ...constraint('roll', {'source': '@S', 'rollAxis': 'X'}),
      },
    });
    final c = VrmNodeConstraints(
      m.document.nodeConstraints,
      m.nodes,
      m.modelRoot,
    );
    final s = m.nodes[m.ids['S']!]!;
    final d = m.nodes[m.ids['D']!]!;
    final rest = twist.asRotationMatrix();
    // Twist about the source's own X: passed on.
    setLocalRotation(
      s,
      rest * about(Vector3(1, 0, 0), 40).asRotationMatrix() as Matrix3,
    );
    c.update();
    expectRotation(
      localRotation(d),
      rest * about(Vector3(1, 0, 0), 40).asRotationMatrix() as Matrix3,
    );
    // Swing about Z: dropped.
    setLocalRotation(
      s,
      rest * about(Vector3(0, 0, 1), 30).asRotationMatrix() as Matrix3,
    );
    c.update();
    expectRotation(localRotation(d), rest);
  });

  test('aim points the axis at the source, through the mirrored root', () {
    final m = constrained({
      'S': {
        'translation': [0, 1, 1],
      },
      'D': {
        'translation': [0, 1, 0],
        'rotation': q(twist),
        ...constraint('aim', {'source': '@S', 'aimAxis': 'PositiveY'}),
      },
    });
    final c = VrmNodeConstraints(
      m.document.nodeConstraints,
      m.nodes,
      m.modelRoot,
    );
    c.update();
    final d = m.nodes[m.ids['D']!]!;
    final model =
        Matrix4.inverted(m.modelRoot.globalTransform) * d.globalTransform
            as Matrix4;
    final aimed = model.getRotation().transformed(Vector3(0, 1, 0))
      ..normalize();
    expect(aimed.x, closeTo(0, 1e-4));
    expect(aimed.y, closeTo(0, 1e-4));
    expect(aimed.z, closeTo(1, 1e-4));
  });

  test('a constraint reading another constraint runs after it', () {
    // B follows A's result, but is listed first.
    final m = constrained({
      'S': {},
      'B': constraint('rotation', {'source': '@A'}),
      'A': constraint('rotation', {'source': '@S'}),
    });
    final c = VrmNodeConstraints(
      m.document.nodeConstraints,
      m.nodes,
      m.modelRoot,
    );
    final turn = about(Vector3(0, 0, 1), 25).asRotationMatrix();
    setLocalRotation(m.nodes[m.ids['S']!]!, turn);
    c.update();
    expectRotation(localRotation(m.nodes[m.ids['B']!]!), turn);
  });
}
