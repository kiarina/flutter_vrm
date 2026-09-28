import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:flutter_vrm/src/runtime/gltf_mapping.dart';
import 'package:vector_math/vector_math.dart';

import '../support/import_like.dart';
import '../support/synthetic_vrm.dart';

/// The synthetic humanoid plus a three-node hair chain H0 -> H1 -> H2 that
/// sticks out along model +X from (0, 1.5, 0), 0.1 per segment, under a
/// twisted H0 (so the bone axes are not the model axes).
({Node root, List<Node?> nodes, VrmDocument document}) hairModel(
  Map<String, dynamic> joint, {
  List<Map<String, dynamic>> colliders = const [],
}) {
  final json = syntheticVrmJson();
  final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
  final twist = Quaternion.axisAngle(Vector3(0.2, 1, 0.4).normalized(), 0.9);
  final inverse = twist.asRotationMatrix()..transpose();
  final h0 = nodes.length;
  nodes
    ..add({
      'name': 'H0',
      'translation': [0, 1.5, 0],
      'rotation': [twist.x, twist.y, twist.z, twist.w],
      'children': [h0 + 1],
    })
    ..add({
      'name': 'H1',
      'translation': inverse.transformed(Vector3(0.1, 0, 0)).storage,
      'children': [h0 + 2],
    })
    ..add({'name': 'H2', 'translation': Vector3(0.1, 0, 0).storage});
  (nodes[0]['children'] as List).add(h0);
  (json['extensions'] as Map<String, dynamic>)['VRMC_springBone'] = {
    'specVersion': '1.0',
    'colliders': colliders,
    'colliderGroups': [
      if (colliders.isNotEmpty)
        {
          'name': 'body',
          'colliders': [for (var i = 0; i < colliders.length; i++) i],
        },
    ],
    'springs': [
      {
        'name': 'hair',
        'joints': [
          {'node': h0, ...joint},
          {'node': h0 + 1, ...joint},
          {'node': h0 + 2},
        ],
        'colliderGroups': [if (colliders.isNotEmpty) 0],
      },
    ],
  };
  final document = VrmDocument.fromGltfJson(json);
  final imported = importLike(json);
  final world = Node(name: 'avatar')..add(imported);
  return (root: world, nodes: mapGltfNodes(json, imported), document: document);
}

Vector3 modelPosition(Node modelRoot, Node node) =>
    (Matrix4.inverted(modelRoot.globalTransform) * node.globalTransform
            as Matrix4)
        .getTranslation();

void main() {
  test('parses VRMC_springBone', () {
    final m = hairModel(
      {
        'stiffness': 0.5,
        'gravityPower': 2,
        'dragForce': 0.3,
        'hitRadius': 0.02,
      },
      colliders: [
        {
          'node': 1,
          'shape': {
            'capsule': {
              'offset': [0, 0, 0],
              'radius': 0.1,
              'tail': [0, 0.2, 0],
            },
          },
        },
      ],
    );
    final def = m.document.springBone!;
    expect(def.colliders.single.shape, isA<VrmSpringCapsule>());
    expect(def.colliderGroups.single.colliders, [0]);
    final spring = def.springs.single;
    expect(spring.joints, hasLength(3));
    expect(spring.joints.first.stiffness, 0.5);
    expect(spring.joints.first.gravityDir.y, -1);
    expect(spring.joints.last.dragForce, 0.5); // spec default
  });

  test('gravity makes the chain hang down', () {
    final m = hairModel({'stiffness': 0, 'gravityPower': 1, 'dragForce': 0.4});
    final modelRoot = m.nodes[0]!.parent!;
    final springs = VrmSpringBoneSystem(
      m.document.springBone,
      m.nodes,
      modelRoot,
    );
    expect(springs.chainCount, 1);
    for (var i = 0; i < 600; i++) {
      springs.update(1 / 60);
    }
    final h0 = modelPosition(modelRoot, m.nodes[m.nodes.length - 3]!);
    final h2 = modelPosition(modelRoot, m.nodes.last!);
    expect(h2.x - h0.x, closeTo(0, 0.01));
    expect(h2.y - h0.y, closeTo(-0.2, 0.01));
  });

  test('gravityDir is in model space, through the mirrored root', () {
    final m = hairModel({
      'stiffness': 0,
      'gravityPower': 1,
      'gravityDir': [0, 0, 1],
    });
    final modelRoot = m.nodes[0]!.parent!;
    final springs = VrmSpringBoneSystem(
      m.document.springBone,
      m.nodes,
      modelRoot,
    );
    for (var i = 0; i < 600; i++) {
      springs.update(1 / 60);
    }
    final h0 = modelPosition(modelRoot, m.nodes[m.nodes.length - 3]!);
    final h2 = modelPosition(modelRoot, m.nodes.last!);
    expect(h2.z - h0.z, closeTo(0.2, 0.01));
  });

  test('stiffness alone keeps the rest shape', () {
    final m = hairModel({'stiffness': 1, 'gravityPower': 0});
    final modelRoot = m.nodes[0]!.parent!;
    final rest = modelPosition(modelRoot, m.nodes.last!);
    final springs = VrmSpringBoneSystem(
      m.document.springBone,
      m.nodes,
      modelRoot,
    );
    for (var i = 0; i < 120; i++) {
      springs.update(1 / 60);
    }
    final now = modelPosition(modelRoot, m.nodes.last!);
    expect((now - rest).length, lessThan(1e-4));
  });

  test('moving the avatar swings the chain, which then settles', () {
    final m = hairModel({'stiffness': 1, 'gravityPower': 0, 'dragForce': 0.4});
    final modelRoot = m.nodes[0]!.parent!;
    final rest = modelPosition(modelRoot, m.nodes.last!);
    final springs = VrmSpringBoneSystem(
      m.document.springBone,
      m.nodes,
      modelRoot,
    );
    m.root.localTransform = Matrix4.translation(Vector3(0, 0.3, 0));
    springs.update(1 / 60);
    final swung = modelPosition(modelRoot, m.nodes.last!);
    // The world moved up, so the tail lags below its rest place.
    expect(swung.y, lessThan(rest.y - 0.01));
    for (var i = 0; i < 600; i++) {
      springs.update(1 / 60);
    }
    final settled = modelPosition(modelRoot, m.nodes.last!);
    expect((settled - rest).length, lessThan(1e-3));
  });

  test('colliders push the chain out', () {
    // A sphere 0.15 below H0 on the Root node; the hanging chain would pass
    // through it.
    final m = hairModel(
      {'stiffness': 0, 'gravityPower': 1, 'hitRadius': 0.01},
      colliders: [
        {
          'node': 1, // J_hips, at the model origin
          'shape': {
            'sphere': {
              'offset': [0.02, 1.35, 0],
              'radius': 0.05,
            },
          },
        },
      ],
    );
    final modelRoot = m.nodes[0]!.parent!;
    final springs = VrmSpringBoneSystem(
      m.document.springBone,
      m.nodes,
      modelRoot,
    );
    for (var i = 0; i < 600; i++) {
      springs.update(1 / 60);
    }
    final center = Vector3(0.02, 1.35, 0);
    for (final n in m.nodes.sublist(m.nodes.length - 2)) {
      final p = modelPosition(modelRoot, n!);
      // Pushed out to radius + hitRadius (0.06), then pulled back onto the
      // bone length, which can sink it slightly (as in three-vrm). Without
      // the collider the chain passes 0.02 from the center.
      expect((p - center).length, greaterThan(0.055));
    }
  });
}
