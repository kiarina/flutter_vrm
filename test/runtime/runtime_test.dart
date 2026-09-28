import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:flutter_vrm/src/runtime/gltf_mapping.dart';
import 'package:vector_math/vector_math.dart';

import '../support/synthetic_vrm.dart';

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

/// A chain hips -> leftUpperLeg -> leftLowerLeg -> leftFoot with odd rest
/// rotations (like a Tripo or Blender rig whose bone axes are not aligned),
/// plus head / eyes, and the remaining required bones flat under Root.
Map<String, dynamic> chainVrm() {
  final twist = Quaternion.axisAngle(Vector3(0.3, 1, -0.2).normalized(), 1.1);
  final twist2 = Quaternion.axisAngle(Vector3(1, 0.4, 0.5).normalized(), -0.7);
  List<double> q(Quaternion x) => [x.x, x.y, x.z, x.w];
  // Place each child so that, in model space, the leg hangs straight down
  // (VRM rest pose), whatever the local rotations are.
  final hipsRot = twist.asRotationMatrix();
  final legRot = hipsRot * twist2.asRotationMatrix() as Matrix3;
  Vector3 local(Matrix3 parentModelRotation, Vector3 modelOffset) =>
      (Matrix3.copy(parentModelRotation)..transpose()).transformed(modelOffset);

  final names = [
    'Root', 'J_hips', 'J_leftUpperLeg', 'J_leftLowerLeg', 'J_leftFoot', //
    'J_head', 'J_leftEye', 'J_rightEye',
  ];
  final nodes = <Map<String, dynamic>>[
    {
      'name': 'Root',
      'children': [1, 5],
    },
    {
      'name': 'J_hips',
      'translation': [0, 0.9, 0],
      'rotation': q(twist),
      'children': [2],
    },
    {
      'name': 'J_leftUpperLeg',
      'translation': local(hipsRot, Vector3(0.1, 0, 0)).storage.toList(),
      'rotation': q(twist2),
      'children': [3],
    },
    {
      'name': 'J_leftLowerLeg',
      'translation': local(legRot, Vector3(0, -0.4, 0)).storage.toList(),
      'children': [4],
    },
    {
      'name': 'J_leftFoot',
      'translation': local(legRot, Vector3(0, -0.4, 0)).storage.toList(),
    },
    {
      'name': 'J_head',
      'translation': [0, 1.5, 0],
      'children': [6, 7],
    },
    {
      'name': 'J_leftEye',
      'translation': [0.03, 0.05, 0.05],
    },
    {
      'name': 'J_rightEye',
      'translation': [-0.03, 0.05, 0.05],
    },
  ];
  // Remaining required bones as extra flat nodes under Root.
  final extra = [
    'spine', 'rightUpperLeg', 'rightLowerLeg', 'rightFoot', 'leftUpperArm', //
    'leftLowerArm', 'leftHand', 'rightUpperArm', 'rightLowerArm', 'rightHand',
  ];
  final bones = <String, dynamic>{
    'hips': {'node': 1},
    'leftUpperLeg': {'node': 2},
    'leftLowerLeg': {'node': 3},
    'leftFoot': {'node': 4},
    'head': {'node': 5},
    'leftEye': {'node': 6},
    'rightEye': {'node': 7},
  };
  for (final e in extra) {
    bones[e] = {'node': nodes.length};
    (nodes[0]['children'] as List).add(nodes.length);
    nodes.add({'name': 'J_$e'});
  }
  assert(names.length == 8);
  final json = syntheticVrmJson(
    humanBones: bones,
    vrmOverrides: {
      'lookAt': {
        'type': 'bone',
        'offsetFromHeadBone': [0, 0.05, 0.05],
        'rangeMapHorizontalOuter': {'inputMaxValue': 90, 'outputScale': 10},
        'rangeMapHorizontalInner': {'inputMaxValue': 90, 'outputScale': 8},
        'rangeMapVerticalUp': {'inputMaxValue': 90, 'outputScale': 6},
        'rangeMapVerticalDown': {'inputMaxValue': 90, 'outputScale': 6},
      },
    },
  );
  json['nodes'] = nodes;
  return json;
}

void expectVector(Vector3 actual, Vector3 expected, {double tol = 1e-4}) {
  expect(
    (actual - expected).length,
    lessThan(tol),
    reason: 'got $actual, expected $expected',
  );
}

void main() {
  test('maps glTF nodes to imported nodes and checks names', () {
    final gltf = syntheticVrmJson();
    final root = importLike(gltf);
    final mapped = mapGltfNodes(gltf, root);
    expect(mapped[1]!.name, 'J_hips');
    root.children.first.children.first.name = 'renamed';
    expect(() => mapGltfNodes(gltf, root), throwsStateError);
  });

  group('normalized humanoid pose', () {
    late VrmAvatar avatar;
    setUp(() async {
      final gltf = chainVrm();
      avatar = await VrmAvatar.fromImported(
        VrmDocument.fromGltfJson(gltf),
        importLike(gltf),
      );
      avatar.autoBlink.enabled = false;
    });

    Vector3 legDirection() {
      final upper = avatar.humanoid.modelPosition(VrmHumanBone.leftUpperLeg)!;
      final lower = avatar.humanoid.modelPosition(VrmHumanBone.leftLowerLeg)!;
      return (lower - upper).normalized();
    }

    test('the rest pose hangs the leg down in model space', () {
      avatar.update(0);
      expectVector(legDirection(), Vector3(0, -1, 0));
    });

    test(
      'a model-space rotation raises the thigh forward on any bone axes',
      () {
        avatar.humanoid.setNormalizedRotation(
          VrmHumanBone.leftUpperLeg,
          Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
        );
        avatar.update(0);
        // Model forward is +Z.
        expectVector(legDirection(), Vector3(0, 0, 1));
        // The shin follows its parent and keeps pointing along the thigh.
        final lower = avatar.humanoid.modelPosition(VrmHumanBone.leftLowerLeg)!;
        final foot = avatar.humanoid.modelPosition(VrmHumanBone.leftFoot)!;
        expectVector((foot - lower).normalized(), Vector3(0, 0, 1));
      },
    );

    test('a child rotation is local to its parent humanoid bone', () {
      avatar.humanoid
        ..setNormalizedRotation(
          VrmHumanBone.leftUpperLeg,
          Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
        )
        ..setNormalizedRotation(
          VrmHumanBone.leftLowerLeg,
          Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
        );
      avatar.update(0);
      final lower = avatar.humanoid.modelPosition(VrmHumanBone.leftLowerLeg)!;
      final foot = avatar.humanoid.modelPosition(VrmHumanBone.leftFoot)!;
      expectVector((foot - lower).normalized(), Vector3(0, -1, 0)); // sitting
    });

    test('resetPose returns to rest', () {
      avatar.humanoid.setNormalizedRotation(
        VrmHumanBone.leftUpperLeg,
        Quaternion.axisAngle(Vector3(1, 0, 0), -1),
      );
      avatar.update(0);
      avatar.humanoid.resetPose();
      avatar.update(0);
      expectVector(legDirection(), Vector3(0, -1, 0));
    });

    test(
      'bone look-at turns the eyes toward a target on the model\'s left',
      () {
        // The importer mirrors Z, so scene (1, 0, -1) is model (1, 0, 1):
        // the model's left (+X) and forward (+Z).
        final eye = avatar.lookAt.eyeWorldPosition()!;
        avatar.lookAt.target = eye + Vector3(1, 0, -1); // 45 deg left, level
        avatar.update(0);
        expect(avatar.lookAt.yaw, closeTo(45, 1e-3));
        expect(avatar.lookAt.pitch, closeTo(0, 1e-3));
        // Left eye (outer when looking left): 45/90 * 10 = 5 degrees.
        final left = avatar.humanoid.normalizedRotation(VrmHumanBone.leftEye)!;
        final right = avatar.humanoid.normalizedRotation(
          VrmHumanBone.rightEye,
        )!;
        final fwd = Vector3(0, 0, 1);
        final l = left.asRotationMatrix().transformed(fwd);
        final r = right.asRotationMatrix().transformed(fwd);
        expect(math.atan2(l.x, l.z) * radians2Degrees, closeTo(5, 1e-3));
        expect(math.atan2(r.x, r.z) * radians2Degrees, closeTo(4, 1e-3));
      },
    );

    test('bone look-at pitches up for a target above', () {
      final eye = avatar.lookAt.eyeWorldPosition()!;
      avatar.lookAt.target = eye + Vector3(0, 1, -1); // 45 deg up, ahead
      avatar.update(0);
      expect(avatar.lookAt.pitch, closeTo(45, 1e-3));
      final l = avatar.humanoid
          .normalizedRotation(VrmHumanBone.leftEye)!
          .asRotationMatrix()
          .transformed(Vector3(0, 0, 1));
      expect(
        math.atan2(l.y, math.sqrt(l.x * l.x + l.z * l.z)) * radians2Degrees,
        closeTo(3, 1e-3),
      );
    });
  });

  group('expression weights', () {
    VrmExpressionManager manager(Map<String, dynamic> presets) {
      final doc = VrmDocument.fromGltfJson(
        syntheticVrmJson(
          vrmOverrides: {
            'expressions': {'preset': presets},
          },
        ),
      );
      return VrmExpressionManager(doc.expressions, const [], const {});
    }

    test('isBinary snaps at 0.5', () {
      final m = manager({
        'happy': {'isBinary': true},
      });
      m.setValue('happy', 0.4);
      expect(m.effectiveWeights()['happy'], isNull);
      m.setValue('happy', 0.6);
      expect(m.effectiveWeights()['happy'], 1);
    });

    test('block silences a group and blend scales it', () {
      final m = manager({
        'surprised': {'overrideBlink': 'block', 'overrideMouth': 'blend'},
        'blink': <String, dynamic>{},
        'aa': <String, dynamic>{},
      });
      m
        ..setValue('blink', 1)
        ..setValue('aa', 1)
        ..setValue('surprised', 0.25);
      final w = m.effectiveWeights();
      expect(w['blink'], isNull);
      expect(w['aa'], closeTo(0.75, 1e-9));
      expect(w['surprised'], 0.25);
    });

    test('unknown expressions are ignored', () {
      final m = manager(const {});
      m.setValue('happy', 1);
      expect(m.effectiveWeights(), isEmpty);
    });
  });
}
