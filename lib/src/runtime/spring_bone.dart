import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../schema/spring_bone.dart';

class _Collider {
  _Collider(this.node, this.shape);

  final Node node;
  final VrmSpringColliderShape shape;

  // Model-space shape for the current frame.
  final Vector3 a = Vector3.zero();
  final Vector3 b = Vector3.zero();
}

class _Joint {
  _Joint({
    required this.node,
    required this.child,
    required this.settings,
    required this.restTranslation,
    required this.restRotation,
    required this.restScale,
    required this.boneAxis,
    required this.length,
  });

  final Node node;

  /// The next joint's node (the tail).
  final Node child;
  final VrmSpringJoint settings;
  final Vector3 restTranslation;
  final Matrix3 restRotation;
  final Vector3 restScale;

  /// Direction to the next joint in this node's rest local frame.
  final Vector3 boneAxis;

  /// Distance to the next joint, in model space.
  final double length;

  /// Tail positions in the chain's simulation space (world or center).
  Vector3 currentTail = Vector3.zero();
  Vector3 previousTail = Vector3.zero();
}

class _Chain {
  _Chain(this.joints, this.colliders, this.center);

  final List<_Joint> joints;
  final List<_Collider> colliders;
  final Node? center;
}

/// Simulates `VRMC_springBone`: hair, skirts, and other chains that sway
/// with the body and collide with its colliders.
///
/// Positions are integrated in the VRM model space (below the importer's
/// mirrored root), so rotations stay proper, while the tails are remembered
/// in world space (or in the spring's `center` node's space), so moving or
/// turning the avatar swings them. Gravity points down in the world, also
/// when the avatar lies down.
///
/// [VrmAvatar.update] steps it after the pose and look-at.
class VrmSpringBoneSystem {
  VrmSpringBoneSystem(
    VrmSpringBoneDefinition? definition,
    List<Node?> gltfNodes,
    this.modelRoot,
  ) {
    if (definition == null) return;
    final rootInverse = Matrix4.inverted(modelRoot.globalTransform);
    final colliders = [
      for (final c in definition.colliders)
        gltfNodes[c.node] == null
            ? null
            : _Collider(gltfNodes[c.node]!, c.shape),
    ];
    for (final spring in definition.springs) {
      final joints = <_Joint>[];
      for (var i = 0; i + 1 < spring.joints.length; i++) {
        final node = gltfNodes[spring.joints[i].node];
        final child = gltfNodes[spring.joints[i + 1].node];
        if (node == null || child == null) break;
        final nodeModel = rootInverse * node.globalTransform as Matrix4;
        final delta =
            (rootInverse * child.globalTransform as Matrix4).getTranslation() -
            nodeModel.getTranslation();
        final length = delta.length;
        if (length < 1e-6) break;
        final t = Vector3.zero();
        final q = Quaternion.identity();
        final s = Vector3.zero();
        node.localTransform.decompose(t, q, s);
        final modelRotation = _rotationOf(nodeModel);
        joints.add(
          _Joint(
            node: node,
            child: child,
            settings: spring.joints[i],
            restTranslation: t,
            restRotation: q.asRotationMatrix(),
            restScale: s,
            boneAxis: (modelRotation..transpose()).transformed(delta)
              ..normalize(),
            length: length,
          ),
        );
      }
      if (joints.isEmpty) continue;
      final center = spring.center == null ? null : gltfNodes[spring.center!];
      _chains.add(
        _Chain(joints, [
          for (final g in spring.colliderGroups)
            for (final c in definition.colliderGroups[g].colliders)
              ?colliders[c],
        ], center),
      );
    }
    reset();
  }

  /// The importer's root, whose child space is the VRM model space.
  final Node modelRoot;

  final List<_Chain> _chains = [];

  /// When false, [update] leaves the chains where they are.
  bool enabled = true;

  /// Longest step [update] integrates at once; a longer frame (a hitch
  /// while loading, a backgrounded app) is shortened to this.
  double maxStep = 1 / 30;

  /// How many chains the model has.
  int get chainCount => _chains.length;

  /// Puts every chain back at its rest shape relative to the current pose,
  /// with no velocity (after teleporting the avatar, for example).
  void reset() {
    for (final chain in _chains) {
      final toStorage = _storageInverse(chain);
      for (final j in chain.joints) {
        j.node.localTransform = Matrix4.compose(
          j.restTranslation,
          Quaternion.fromRotation(j.restRotation),
          j.restScale,
        );
      }
      for (final j in chain.joints) {
        j.currentTail = toStorage.transform3(
          j.child.globalTransform.getTranslation(),
        );
        j.previousTail = j.currentTail.clone();
      }
    }
  }

  /// Advances the simulation by [deltaSeconds].
  void update(double deltaSeconds) {
    if (!enabled || deltaSeconds <= 0 || _chains.isEmpty) return;
    final dt = math.min(deltaSeconds, maxStep);
    final root = modelRoot.globalTransform.clone();
    final rootInverse = Matrix4.inverted(root);
    for (final chain in _chains) {
      final storage =
          chain.center?.globalTransform.clone() ?? Matrix4.identity();
      final toModel = rootInverse * storage as Matrix4;
      final fromModel = Matrix4.inverted(storage) * root as Matrix4;

      for (final c in chain.colliders) {
        final m = rootInverse * c.node.globalTransform as Matrix4;
        c.a.setFrom(m.transform3(c.shape.offset.clone()));
        final shape = c.shape;
        if (shape is VrmSpringCapsule) {
          c.b.setFrom(m.transform3(shape.tail.clone()));
        }
      }

      for (final j in chain.joints) {
        final s = j.settings;
        final nodeModel = rootInverse * j.node.globalTransform as Matrix4;
        final position = nodeModel.getTranslation();
        final parent = j.node.parent;
        final parentRotation = parent == null || identical(parent, modelRoot)
            ? Matrix3.identity()
            : _rotationOf(rootInverse * parent.globalTransform as Matrix4);
        final restFrame = parentRotation * j.restRotation as Matrix3;

        final current = toModel.transform3(j.currentTail.clone());
        final previous = toModel.transform3(j.previousTail.clone());
        // Gravity is authored for the model standing upright in the world:
        // glTF's -Z mirror maps it to the scene, the root back to the model.
        final authored = s.gravityDir;
        final gravity = rootInverse.rotated3(
          Vector3(authored.x, authored.y, -authored.z),
        )..normalize();

        var next =
            current +
            (current - previous) * (1 - s.dragForce) +
            restFrame.transformed(j.boneAxis.clone()) * (s.stiffness * dt) +
            gravity * (s.gravityPower * dt);
        next = _constrain(position, next, j.length);

        for (final c in chain.colliders) {
          final shape = c.shape;
          final nearest = shape is VrmSpringCapsule
              ? _closestOnSegment(c.a, c.b, next)
              : c.a;
          final away = next - nearest;
          final distance = away.length;
          final limit = shape.radius + s.hitRadius;
          if (distance < limit && distance > 1e-9) {
            next = _constrain(
              position,
              nearest + away * (limit / distance),
              j.length,
            );
          }
        }

        j.previousTail = j.currentTail;
        j.currentTail = fromModel.transform3(next.clone());

        // Rotate the joint so its bone axis points at the new tail.
        final to = (Matrix3.copy(
          restFrame,
        )..transpose()).transformed(next - position)..normalize();
        j.node.localTransform = Matrix4.compose(
          j.restTranslation,
          Quaternion.fromRotation(
            j.restRotation * _fromTo(j.boneAxis, to) as Matrix3,
          ),
          j.restScale,
        );
      }
    }
  }

  /// The chain's storage space from the model space's world: world, or the
  /// center node's space.
  Matrix4 _storageInverse(_Chain chain) {
    final center = chain.center;
    return center == null
        ? Matrix4.identity()
        : Matrix4.inverted(center.globalTransform);
  }

  static Vector3 _constrain(Vector3 origin, Vector3 point, double length) {
    final d = point - origin;
    final l = d.length;
    if (l < 1e-9) return point;
    return origin + d * (length / l);
  }

  static Vector3 _closestOnSegment(Vector3 a, Vector3 b, Vector3 p) {
    final ab = b - a;
    final l2 = ab.length2;
    if (l2 < 1e-12) return a.clone();
    final t = ((p - a).dot(ab) / l2).clamp(0.0, 1.0);
    return a + ab * t;
  }

  /// The rotation turning unit vector [from] onto unit vector [to].
  static Matrix3 _fromTo(Vector3 from, Vector3 to) {
    final d = from.dot(to).clamp(-1.0, 1.0);
    final axis = from.cross(to);
    if (axis.length2 < 1e-12) {
      if (d > 0) return Matrix3.identity();
      // Opposite: turn half way round any perpendicular axis.
      final perpendicular = from.cross(
        from.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0),
      )..normalize();
      return Quaternion.axisAngle(perpendicular, math.pi).asRotationMatrix();
    }
    return Quaternion.axisAngle(
      axis..normalize(),
      math.acos(d),
    ).asRotationMatrix();
  }

  static Matrix3 _rotationOf(Matrix4 m) {
    final t = Vector3.zero();
    final q = Quaternion.identity();
    final s = Vector3.zero();
    m.decompose(t, q, s);
    return q.asRotationMatrix();
  }
}
