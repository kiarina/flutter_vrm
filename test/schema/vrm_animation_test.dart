import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart';

import '../support/import_like.dart';
import '../support/synthetic_vrm.dart';
import '../support/synthetic_vrma.dart';

Quaternion about(Vector3 axis, double degrees) =>
    Quaternion.axisAngle(axis.normalized(), degrees * math.pi / 180);

List<double> q(Quaternion x) => [x.x, x.y, x.z, x.w];

void expectRotation(Matrix3 actual, Matrix3 expected) {
  for (var i = 0; i < 9; i++) {
    expect(actual.storage[i], closeTo(expected.storage[i], 1e-4));
  }
}

Matrix3 sampleRotation(VrmAnimationTrack t, double time) {
  final out = List.filled(4, 0.0);
  t.sample(time, out);
  return Quaternion(out[0], out[1], out[2], out[3]).asRotationMatrix();
}

void main() {
  // A T-pose whose nodes carry arbitrary rest rotations (allowed by the
  // spec): Root -> hips (twisted) -> spine (twisted) -> head.
  final hipsRest = about(Vector3(0.2, 1, 0.1), 40);
  final spineRest = about(Vector3(1, 0.3, -0.2), -25);
  final nodes = [
    {
      'name': 'Root',
      'translation': [0, 0.1, 0],
      'children': [1],
    },
    {
      'name': 'hips',
      'translation': [0, 0.8, 0],
      'rotation': q(hipsRest),
      'children': [2],
    },
    {
      'name': 'spine',
      'rotation': q(spineRest),
      'children': [3],
    },
    {'name': 'head'},
    {'name': 'happy'},
  ];

  test('rotations become normalized (model space, relative to rest)', () {
    // The spine turns 30 degrees about model +Y.
    final turn = about(Vector3(0, 1, 0), 30).asRotationMatrix();
    final restWorld =
        hipsRest.asRotationMatrix() * spineRest.asRotationMatrix() as Matrix3;
    final parentWorld = hipsRest.asRotationMatrix();
    // local = P^-1 * turn * W  (so that the node's world becomes turn * W)
    final local = Quaternion.fromRotation(
      (Matrix3.copy(parentWorld)..transpose()) * turn * restWorld as Matrix3,
    );
    final a = VrmAnimation.fromGlb(
      buildVrma(
        nodes: nodes,
        humanBones: {'hips': 1, 'spine': 2, 'head': 3},
        channels: [
          (
            node: 2,
            path: 'rotation',
            times: [0, 1],
            values: [...q(spineRest), ...q(local)],
            interpolation: 'LINEAR',
          ),
        ],
      ),
    );
    final track = a.rotations[VrmHumanBone.spine]!;
    expectRotation(sampleRotation(track, 0), Matrix3.identity());
    expectRotation(sampleRotation(track, 1), turn);
    // Linear: half way is half the turn.
    expectRotation(
      sampleRotation(track, 0.5),
      about(Vector3(0, 1, 0), 15).asRotationMatrix(),
    );
    expect(a.duration, 1);
    expect(a.restHipsHeight, closeTo(0.9, 1e-6));
  });

  test('hips translation goes to model space; step and cubic sampling', () {
    final a = VrmAnimation.fromGlb(
      buildVrma(
        nodes: nodes,
        humanBones: {'hips': 1, 'spine': 2, 'head': 3},
        expressions: {'happy': 4},
        channels: [
          (
            node: 1,
            path: 'translation',
            times: [0, 2],
            values: [0, 0.8, 0, 0.5, 0.4, 0],
            interpolation: 'STEP',
          ),
          (
            node: 4,
            path: 'translation',
            // in-tangent, value, out-tangent per key (x only matters)
            times: [0, 1],
            values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0],
            interpolation: 'CUBICSPLINE',
          ),
        ],
      ),
    );
    final out = List.filled(3, 0.0);
    a.hipsPosition!.sample(1.9, out);
    expect(out, [0, closeTo(0.9, 1e-6), 0]); // Root's +0.1 added
    a.hipsPosition!.sample(2, out);
    expect(out[0], closeTo(0.5, 1e-6));
    final w = [0.0];
    a.expressions['happy']!.sample(0.5, w);
    expect(w[0], closeTo(0.5, 1e-6)); // flat tangents: smoothstep
    a.expressions['happy']!.sample(0.25, w);
    expect(w[0], closeTo(0.15625, 1e-6));
  });

  test('the player folds bones the model lacks into its children', () async {
    // The synthetic model has no chest; the animation turns chest and head.
    final vrmJson = syntheticVrmJson(
      vrmOverrides: {
        'expressions': {
          'preset': {'happy': <String, dynamic>{}},
        },
      },
    );
    final avatar = await VrmAvatar.fromImported(
      VrmDocument.fromGltfJson(vrmJson),
      importLike(vrmJson),
      mtoon: false,
    );
    final chestTurn = about(Vector3(0, 1, 0), 20);
    final headTurn = about(Vector3(1, 0, 0), 10);
    final flat = [
      {
        'name': 'Root',
        'children': [1],
      },
      {
        'name': 'hips',
        'translation': [0, 1, 0],
        'children': [2],
      },
      {
        'name': 'spine',
        'children': [3],
      },
      {
        'name': 'chest',
        'children': [4],
      },
      {'name': 'head'},
      {'name': 'happy'},
    ];
    final player = VrmAnimationPlayer(
      avatar,
      VrmAnimation.fromGlb(
        buildVrma(
          nodes: flat,
          humanBones: {'hips': 1, 'spine': 2, 'chest': 3, 'head': 4},
          expressions: {'happy': 5},
          channels: [
            (
              node: 3,
              path: 'rotation',
              times: [0],
              values: q(chestTurn),
              interpolation: 'LINEAR',
            ),
            (
              node: 4,
              path: 'rotation',
              times: [0],
              values: q(headTurn),
              interpolation: 'LINEAR',
            ),
            (
              node: 5,
              path: 'translation',
              times: [0],
              values: [1.5, 0, 0],
              interpolation: 'LINEAR',
            ),
          ],
        ),
      ),
    );
    player.update(0);
    expectRotation(
      avatar.humanoid.normalizedRotation(VrmHumanBone.head)!.asRotationMatrix(),
      chestTurn.asRotationMatrix() * headTurn.asRotationMatrix() as Matrix3,
    );
    expect(avatar.expressions.value('happy'), 1); // clamped
  });
}
