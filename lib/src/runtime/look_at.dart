import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../schema/vrm_document.dart';
import 'expression_manager.dart';
import 'humanoid_rig.dart';

/// Points the eyes at a target, the way the model's `VRMC_vrm.lookAt` says:
/// by rotating the eye bones (`bone`) or by driving the lookUp / lookDown /
/// lookLeft / lookRight expressions (`expression`), through its range maps.
class VrmLookAt {
  VrmLookAt(this.definition, this._rig, this._expressions);

  /// The model's look-at settings, or null when it has none (then this does
  /// nothing).
  final VrmLookAtDefinition? definition;
  final VrmHumanoidRig _rig;
  final VrmExpressionManager _expressions;

  /// A world-space point to look at. When null, [yaw] and [pitch] are used
  /// as set.
  Vector3? target;

  /// Horizontal angle in degrees; positive looks to the model's left.
  double yaw = 0;

  /// Vertical angle in degrees; positive looks up.
  double pitch = 0;

  /// When false, the eyes rest and the look expressions stay at 0.
  bool enabled = true;

  /// The eye position (head bone plus `offsetFromHeadBone`) in world space.
  Vector3? eyeWorldPosition() {
    final head = _rig.node(VrmHumanBone.head);
    final def = definition;
    if (head == null || def == null) return null;
    return head.globalTransform.transformed3(def.offsetFromHeadBone.clone());
  }

  /// Computes [yaw] / [pitch] from [target] and writes them to the eyes or the
  /// look expressions. Call after the body pose is applied, before the
  /// expressions are.
  void update() {
    final def = definition;
    final head = _rig.node(VrmHumanBone.head);
    if (def == null || head == null) return;

    final t = target;
    if (t != null) {
      final modelInverse = Matrix4.inverted(_rig.modelRoot.globalTransform);
      final eye = modelInverse.transformed3(eyeWorldPosition()!);
      final dir = modelInverse.transformed3(t.clone()) - eye;
      // Into the head's frame: undo how far the head is turned from rest.
      final headTurn = _rig.normalizedModelRotation(VrmHumanBone.head);
      final local = headTurn == null
          ? dir
          : (Matrix3.copy(headTurn)..transpose()).transformed(dir);
      if (local.length2 > 1e-12) {
        yaw = math.atan2(local.x, local.z) * radians2Degrees;
        pitch =
            math.atan2(
              local.y,
              math.sqrt(local.x * local.x + local.z * local.z),
            ) *
            radians2Degrees;
      }
    }

    final y = enabled ? yaw : 0.0;
    final p = enabled ? pitch : 0.0;
    if (def.type == 'expression') {
      _expressions.setPreset(
        VrmExpressionPreset.lookLeft,
        y > 0 ? def.rangeMapHorizontalOuter.map(y) : 0,
      );
      _expressions.setPreset(
        VrmExpressionPreset.lookRight,
        y < 0 ? def.rangeMapHorizontalOuter.map(-y) : 0,
      );
      _expressions.setPreset(
        VrmExpressionPreset.lookUp,
        p > 0 ? def.rangeMapVerticalUp.map(p) : 0,
      );
      _expressions.setPreset(
        VrmExpressionPreset.lookDown,
        p < 0 ? def.rangeMapVerticalDown.map(-p) : 0,
      );
      return;
    }

    // Bone type: the left eye turns outward when looking left, inward when
    // looking right, and the right eye the other way round.
    final double leftYaw, rightYaw;
    if (y < 0) {
      leftYaw = -def.rangeMapHorizontalInner.map(-y);
      rightYaw = -def.rangeMapHorizontalOuter.map(-y);
    } else {
      leftYaw = def.rangeMapHorizontalOuter.map(y);
      rightYaw = def.rangeMapHorizontalInner.map(y);
    }
    final eyePitch = p < 0
        ? -def.rangeMapVerticalDown.map(-p)
        : def.rangeMapVerticalUp.map(p);

    Quaternion eyeRotation(double yawDeg) {
      // Yaw about +Y turns +Z toward +X (the model's left); a positive pitch
      // turns +Z toward +Y, which is a negative rotation about +X.
      final m =
          Matrix3.rotationY(yawDeg * degrees2Radians) *
                  Matrix3.rotationX(-eyePitch * degrees2Radians)
              as Matrix3;
      return Quaternion.fromRotation(m);
    }

    if (_rig.node(VrmHumanBone.leftEye) != null) {
      _rig.setNormalizedRotation(VrmHumanBone.leftEye, eyeRotation(leftYaw));
    }
    if (_rig.node(VrmHumanBone.rightEye) != null) {
      _rig.setNormalizedRotation(VrmHumanBone.rightEye, eyeRotation(rightYaw));
    }
  }
}
