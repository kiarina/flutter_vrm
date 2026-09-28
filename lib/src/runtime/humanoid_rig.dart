import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../schema/vrm_document.dart';

class _BoneRest {
  _BoneRest({
    required this.node,
    required this.translation,
    required this.rotation,
    required this.scale,
    required this.parentModelRotation,
    required this.parentModelInverse,
    required this.modelPosition,
  });

  final Node node;
  final Vector3 translation;
  final Matrix3 rotation;
  final Vector3 scale;

  /// Rest rotation of the bone's parent node, in model space.
  final Matrix3 parentModelRotation;

  /// Inverse of the parent node's rest transform in model space.
  final Matrix4 parentModelInverse;

  /// Rest position of the bone in model space.
  final Vector3 modelPosition;

  late final Matrix3 parentModelRotationInverse = Matrix3.copy(
    parentModelRotation,
  )..invert();

  /// Rest rotation of the bone itself, in model space.
  late final Matrix3 modelRotation = parentModelRotation * rotation as Matrix3;
}

/// Poses a VRM humanoid through *normalized* bone rotations.
///
/// A normalized rotation is expressed in VRM model space (+X is the model's
/// left, +Y up, +Z forward) relative to the VRM 1.0 rest pose (T-pose), and
/// is local to the parent humanoid bone. Because every model's rest pose is
/// the same T-pose in this space, one pose works on any VRM 1.0 model,
/// whatever its bones' own axes (the same idea as three-vrm's normalized
/// humanoid bones).
///
/// Examples, in model space:
/// * thigh raised forward to sit: `leftUpperLeg` about +X by -90 degrees
/// * shin hanging down again: `leftLowerLeg` about +X by +90 degrees
/// * left arm lowered from the T-pose: `leftUpperArm` about +Z by -75 degrees
///
/// Set rotations, then call [apply] (the avatar's `update` does).
class VrmHumanoidRig {
  VrmHumanoidRig(
    Map<VrmHumanBone, int> humanBones,
    List<Node?> gltfNodes,
    this.modelRoot,
  ) {
    final rootInverse = Matrix4.inverted(modelRoot.globalTransform);
    Matrix4 modelTransformOf(Node? node) =>
        node == null || identical(node, modelRoot)
        ? Matrix4.identity()
        : rootInverse * node.globalTransform as Matrix4;

    for (final entry in humanBones.entries) {
      final node = gltfNodes[entry.value];
      if (node == null) continue;
      final t = Vector3.zero();
      final q = Quaternion.identity();
      final s = Vector3.zero();
      node.localTransform.decompose(t, q, s);
      _rest[entry.key] = _BoneRest(
        node: node,
        translation: t,
        rotation: q.asRotationMatrix(),
        scale: s,
        parentModelRotation: _rotationOf(modelTransformOf(node.parent)),
        parentModelInverse: Matrix4.inverted(modelTransformOf(node.parent)),
        modelPosition: modelTransformOf(node).getTranslation(),
      );
    }
  }

  /// The node whose child space is the VRM model space (the importer's root,
  /// which carries the glTF-to-engine handedness flip).
  final Node modelRoot;

  final Map<VrmHumanBone, _BoneRest> _rest = {};
  final Map<VrmHumanBone, Matrix3> _normalized = {};
  Vector3? _hipsPosition;

  /// The bones this model maps.
  Iterable<VrmHumanBone> get bones => _rest.keys;

  /// The imported node of [bone], or null when the model does not map it.
  Node? node(VrmHumanBone bone) => _rest[bone]?.node;

  /// Sets [bone]'s normalized rotation (see the class documentation).
  void setNormalizedRotation(VrmHumanBone bone, Quaternion rotation) {
    _normalized[bone] = rotation.asRotationMatrix();
  }

  /// The normalized rotation set on [bone], or null for the rest pose.
  Quaternion? normalizedRotation(VrmHumanBone bone) {
    final m = _normalized[bone];
    return m == null ? null : Quaternion.fromRotation(m);
  }

  /// Moves the hips to [modelPosition] (model space), or back to their rest
  /// place with null. Animations use this for walking, sitting down, and the
  /// like; the rest of the body follows.
  void setHipsPosition(Vector3? modelPosition) =>
      _hipsPosition = modelPosition?.clone();

  /// The hips position set with [setHipsPosition], or null for rest.
  Vector3? get hipsPosition => _hipsPosition?.clone();

  /// [bone]'s rest (T-pose) position in model space, or null when unmapped.
  Vector3? restModelPosition(VrmHumanBone bone) =>
      _rest[bone]?.modelPosition.clone();

  /// Clears [bone] back to its rest rotation.
  void clearNormalizedRotation(VrmHumanBone bone) => _normalized.remove(bone);

  /// Returns every bone to the rest pose (and the hips to their rest place).
  void resetPose() {
    _normalized.clear();
    _hipsPosition = null;
  }

  /// Writes the normalized pose into the imported nodes.
  ///
  /// Every mapped humanoid bone is rewritten from its rest transform, so a
  /// bone without a normalized rotation returns to rest. Non-humanoid nodes
  /// (hair, clothes) are left alone.
  void apply() {
    for (final entry in _rest.entries) {
      final rest = entry.value;
      final n = _normalized[entry.key];
      final Matrix3 rotation;
      if (n == null) {
        rotation = rest.rotation;
      } else {
        // raw = P^-1 * N * P * restLocal, where P is the parent's rest
        // rotation in model space.
        rotation =
            rest.parentModelRotationInverse *
                    n *
                    rest.parentModelRotation *
                    rest.rotation
                as Matrix3;
      }
      final hips = _hipsPosition;
      rest.node.localTransform = Matrix4.compose(
        entry.key == VrmHumanBone.hips && hips != null
            ? rest.parentModelInverse.transform3(hips.clone())
            : rest.translation,
        Quaternion.fromRotation(rotation),
        rest.scale,
      );
    }
  }

  /// [node]'s current transform in model space.
  Matrix4 modelTransformOf(Node node) =>
      Matrix4.inverted(modelRoot.globalTransform) * node.globalTransform
          as Matrix4;

  /// [bone]'s current position in model space, or null when unmapped.
  Vector3? modelPosition(VrmHumanBone bone) {
    final n = node(bone);
    return n == null ? null : modelTransformOf(n).getTranslation();
  }

  /// [bone]'s current position in world space, or null when unmapped.
  Vector3? worldPosition(VrmHumanBone bone) =>
      node(bone)?.globalTransform.getTranslation();

  /// How far [bone] is currently rotated from its rest orientation, in model
  /// space (the accumulated normalized rotation of the chain above it).
  Matrix3? normalizedModelRotation(VrmHumanBone bone) {
    final rest = _rest[bone];
    if (rest == null) return null;
    final current = _rotationOf(modelTransformOf(rest.node));
    final restInverse = Matrix3.copy(rest.modelRotation)..invert();
    return current * restInverse as Matrix3;
  }

  static Matrix3 _rotationOf(Matrix4 m) {
    final t = Vector3.zero();
    final q = Quaternion.identity();
    final s = Vector3.zero();
    m.decompose(t, q, s);
    return q.asRotationMatrix();
  }
}
