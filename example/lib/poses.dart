import 'dart:math' as math;

import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart';

/// Normalized humanoid rotations (VRM model space: +X is the model's left,
/// +Y up, +Z forward), relative to the VRM T-pose.
Quaternion _about(double x, double y, double z, double degrees) =>
    Quaternion.axisAngle(Vector3(x, y, z), degrees * math.pi / 180);

/// Arms lowered from the T-pose, elbows slightly bent.
final Map<VrmHumanBone, Quaternion> _relaxedArms = {
  VrmHumanBone.leftUpperArm: _about(0, 0, 1, -72),
  VrmHumanBone.rightUpperArm: _about(0, 0, 1, 72),
  VrmHumanBone.leftLowerArm: _about(0, 1, 0, -10),
  VrmHumanBone.rightLowerArm: _about(0, 1, 0, 10),
};

final Map<String, Map<VrmHumanBone, Quaternion>> kPoses = {
  'rest': const {},
  'idle': _relaxedArms,
  // The hips turn back and forth in main.dart, to watch spring bones swing.
  'turn': _relaxedArms,
  'sit': {
    ..._relaxedArms,
    VrmHumanBone.leftUpperLeg: _about(1, 0, 0, -90),
    VrmHumanBone.rightUpperLeg: _about(1, 0, 0, -90),
    VrmHumanBone.leftLowerLeg: _about(1, 0, 0, 90),
    VrmHumanBone.rightLowerLeg: _about(1, 0, 0, 90),
    // Hands resting on the thighs.
    VrmHumanBone.leftLowerArm: _about(1, 0, 0, -60),
    VrmHumanBone.rightLowerArm: _about(1, 0, 0, -60),
  },
  'wave': {
    ..._relaxedArms,
    VrmHumanBone.rightUpperArm: _about(0, 0, 1, -20),
    VrmHumanBone.rightLowerArm: _about(0, 0, 1, -100),
    VrmHumanBone.head: _about(0, 0, 1, 6),
  },
};
