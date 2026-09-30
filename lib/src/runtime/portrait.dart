import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../schema/vrm_document.dart';
import 'vrm_avatar.dart';

/// Camera placements for portraits of an avatar (avatar pickers, thumbnails).
class VrmPortrait {
  const VrmPortrait._();

  /// A bust-up from the front: from the top of the head down to a little
  /// below the shoulders, the head centered, filling a square view with the
  /// vertical field of view [fovYRadians].
  ///
  /// Call after [VrmAvatar.update] so the bones are posed. The top of the
  /// head comes from the head hit capsule, which reaches the top of the
  /// model's meshes, so big-headed models fit too. The camera looks along
  /// the avatar's facing (its model +Z in the scene) and assumes the avatar
  /// stands upright.
  static ({Vector3 position, Vector3 target}) bust(
    VrmAvatar avatar, {
    required double fovYRadians,
  }) {
    final h = avatar.humanoid;
    final head = h.worldPosition(VrmHumanBone.head);
    if (head == null) throw StateError('the model has no head bone');
    final neck = h.worldPosition(VrmHumanBone.neck);
    final shoulders = [
      h.worldPosition(VrmHumanBone.leftUpperArm),
      h.worldPosition(VrmHumanBone.rightUpperArm),
    ].nonNulls.toList();

    var top = head.y + 0.2;
    final scale = avatar.root.globalTransform.getMaxScaleOnAxis();
    for (final c in avatar.hitShapes.capsules) {
      if (c.bone != VrmHumanBone.head) continue;
      final ends = c.worldSegment();
      if (ends != null) {
        top = math.max(ends.$1.y, ends.$2.y) + c.radius * scale;
      }
    }
    final shoulderY = shoulders.isEmpty
        ? (neck ?? head).y - 0.1
        : shoulders.map((p) => p.y).reduce((a, b) => a + b) / shoulders.length;
    final bottom = shoulderY - (top - shoulderY) * 0.35;
    final span = (top - bottom) * 1.08;
    final target = Vector3(head.x, (top + bottom) / 2, head.z);
    final distance = span / 2 / math.tan(fovYRadians / 2);
    final forward = avatar.modelRoot.globalTransform.rotated3(Vector3(0, 0, 1))
      ..y = 0;
    if (forward.length2 < 1e-8) forward.setValues(0, 0, -1);
    forward.normalize();
    return (position: target + forward * distance, target: target);
  }
}
