import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart';

import 'hit_test_test.dart' show load;

void main() {
  test('the bust faces the avatar and spans head to shoulders', () async {
    final avatar = await load();
    avatar.update(0);
    const fov = 20 * math.pi / 180;
    final (:position, :target) = VrmPortrait.bust(avatar, fovYRadians: fov);
    // Shoulders at 1.3 m, the head bone at 1.5 m and its top above it.
    expect(target.y, greaterThan(1.3));
    expect(target.y, lessThan(1.6));
    expect(target.x, closeTo(0, 1e-6));
    // The model faces +Z in its space, which the importer maps to -Z.
    expect(position.z, lessThan(-1));
    expect(position.y, closeTo(target.y, 1e-6));
    // Turning the avatar around turns the camera with it.
    avatar.root.localTransform = Matrix4.rotationY(math.pi);
    avatar.update(0);
    expect(
      VrmPortrait.bust(avatar, fovYRadians: fov).position.z,
      greaterThan(1),
    );
  });
}
