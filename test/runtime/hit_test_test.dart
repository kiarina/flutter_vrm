import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart';

import '../support/import_like.dart';
import '../support/synthetic_vrm.dart';

/// A 1.6 m humanoid in the T-pose with a real hierarchy (hips at 0.85 m).
/// Model space: +X is the model's left, +Z forward.
Map<String, dynamic> bodyVrm() {
  final nodes = <Map<String, dynamic>>[];
  final bones = <String, dynamic>{};
  int add(String bone, List<double> t, [int? parent]) {
    final i = nodes.length;
    nodes.add({'name': 'J_$bone', 'translation': t});
    bones[bone] = {'node': i};
    if (parent != null) {
      ((nodes[parent]['children'] ??= <int>[]) as List<int>).add(i);
    }
    return i;
  }

  final hips = add('hips', [0, 0.85, 0]);
  final spine = add('spine', [0, 0.1, 0], hips);
  final head = add('head', [0, 0.55, 0], spine);
  add('leftEye', [0.03, 0.06, 0.08], head);
  add('rightEye', [-0.03, 0.06, 0.08], head);
  for (final (side, x) in [('left', 1.0), ('right', -1.0)]) {
    final upperLeg = add('${side}UpperLeg', [0.1 * x, -0.05, 0], hips);
    final lowerLeg = add('${side}LowerLeg', [0, -0.4, 0], upperLeg);
    add('${side}Foot', [0, -0.38, 0], lowerLeg);
    final upperArm = add('${side}UpperArm', [0.18 * x, 0.35, 0], spine);
    final lowerArm = add('${side}LowerArm', [0.25 * x, 0, 0], upperArm);
    add('${side}Hand', [0.24 * x, 0, 0], lowerArm);
  }
  final json = syntheticVrmJson(humanBones: bones);
  json['nodes'] = [
    {
      'name': 'Root',
      'children': [hips + 1],
    },
    for (final n in nodes)
      {
        ...n,
        if (n['children'] != null)
          'children': [for (final c in n['children'] as List<int>) c + 1],
      },
  ];
  for (final b in bones.values) {
    (b as Map<String, dynamic>)['node'] = (b['node'] as int) + 1;
  }
  return json;
}

Future<VrmAvatar> load() {
  final json = bodyVrm();
  return VrmAvatar.fromImported(
    VrmDocument.fromGltfJson(json),
    importLike(json),
    mtoon: false,
  );
}

/// A ray from the avatar's front (model +Z is scene -Z) toward it.
Ray fromFront(double y, {double x = 0}) =>
    Ray.originDirection(Vector3(x, y, -3), Vector3(0, 0, 1));

void main() {
  test('hits the torso and the head from the front', () async {
    final a = await load();
    final torso = a.hitTest(fromFront(1.1))!;
    expect(torso.bone, anyOf(VrmHumanBone.hips, VrmHumanBone.spine));
    expect(torso.distance, closeTo(3 - 0.13, 0.01));
    expect(a.hitTest(fromFront(1.6))!.bone, VrmHumanBone.head);
    expect(a.hitTest(fromFront(1.1, x: 1.5)), isNull);
  });

  test('capsules follow the pose (a sitting thigh)', () async {
    final a = await load();
    // Straight down onto where the left thigh (scene +X, mirrored Z only)
    // reaches forward (scene -Z) when sitting.
    final down = Ray.originDirection(Vector3(0.1, 3, -0.3), Vector3(0, -1, 0));
    expect(a.hitTest(down)?.bone, isNot(VrmHumanBone.leftUpperLeg));
    a.humanoid.setNormalizedRotation(
      VrmHumanBone.leftUpperLeg,
      Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
    );
    a.update(0);
    final hit = a.hitTest(down)!;
    expect(hit.bone, VrmHumanBone.leftUpperLeg);
    expect(hit.point.y, closeTo(0.8 + 0.08, 0.01));
  });

  test('arms and hands are separate parts', () async {
    final a = await load();
    // The model's left arm is on scene +X in the T-pose (mirrored Z only).
    expect(a.hitTest(fromFront(1.3, x: 0.35))!.bone, VrmHumanBone.leftUpperArm);
    expect(a.hitTest(fromFront(1.3, x: 0.72))!.bone, VrmHumanBone.leftHand);
    a.hitShapes.capsules
            .firstWhere((c) => c.bone == VrmHumanBone.leftHand)
            .enabled =
        false;
    expect(
      a.hitTest(fromFront(1.3, x: 0.72))?.bone,
      isNot(VrmHumanBone.leftHand),
    );
  });

  test('the head capsule reaches the top of the meshes (big heads)', () async {
    // A mesh whose POSITION accessor reaches 2.0 m: a head 0.5 m tall.
    final json = bodyVrm();
    json['meshes'] = [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0},
          },
        ],
      },
    ];
    json['accessors'] = [
      {
        'componentType': 5126,
        'count': 1,
        'type': 'VEC3',
        'min': [-0.3, 0, -0.2],
        'max': [0.3, 2.0, 0.2],
      },
    ];
    final nodes = json['nodes'] as List;
    nodes.add({'name': 'Body', 'mesh': 0});
    ((nodes[0] as Map<String, dynamic>)['children'] as List).add(
      nodes.length - 1,
    );
    final big = await VrmAvatar.fromImported(
      VrmDocument.fromGltfJson(json),
      importLike(json),
      mtoon: false,
    );
    expect(big.hitTest(fromFront(1.9))?.bone, VrmHumanBone.head);
    // Without the mesh, an average head does not reach that high.
    expect((await load()).hitTest(fromFront(1.9)), isNull);
  });

  test(
    'hitTestAll picks the nearest avatar; scaling scales the capsules',
    () async {
      final near = await load();
      final far = await load();
      far.root.localTransform = Matrix4.translation(Vector3(0, 0, 2));
      final picked = VrmAvatar.hitTestAll([far, near], fromFront(1.1))!;
      expect(identical(picked.$1, near), isTrue);

      final big = await load();
      big.root.localTransform = Matrix4.diagonal3Values(2, 2, 2);
      final hit = big.hitTest(fromFront(2.2))!;
      expect(hit.distance, closeTo(3 - 0.26, 0.02));
    },
  );
}
