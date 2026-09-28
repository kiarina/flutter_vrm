import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../schema/node_constraint.dart';

class _Bound {
  _Bound(this.definition, this.destination, this.source) {
    final t = Vector3.zero();
    final q = Quaternion.identity();
    final s = Vector3.zero();
    destination.localTransform.decompose(t, q, s);
    restTranslation = t;
    restScale = s;
    destinationRest = q.asRotationMatrix();
    sourceRest = VrmNodeConstraints._localRotation(source);
  }

  final VrmNodeConstraint definition;
  final Node destination;
  final Node source;
  late final Vector3 restTranslation;
  late final Vector3 restScale;
  late final Matrix3 destinationRest;
  late final Matrix3 sourceRest;

  void write(Matrix3 rotation) {
    destination.localTransform = Matrix4.compose(
      restTranslation,
      Quaternion.fromRotation(rotation),
      restScale,
    );
  }
}

/// Applies `VRMC_node_constraint`: helper nodes (twist bones, sleeve aims)
/// that follow the rotation or position of other nodes.
///
/// Constraints run in dependency order: one whose source (or an ancestor of
/// it) another constraint moves runs after that one. [VrmAvatar.update] runs
/// them after the pose and look-at, before the spring bones.
class VrmNodeConstraints {
  VrmNodeConstraints(
    List<VrmNodeConstraint> definitions,
    List<Node?> gltfNodes,
    this.modelRoot,
  ) {
    final bound = <_Bound>[
      for (final d in definitions)
        if (gltfNodes[d.destination] case final destination?)
          if (gltfNodes[d.source] case final source?)
            _Bound(d, destination, source),
    ];
    // Topological order: visit what a constraint reads before it.
    final byDestination = {for (final b in bound) b.destination: b};
    final state = <_Bound, bool>{}; // false: visiting, true: done
    void visit(_Bound b) {
      if (state.containsKey(b)) return; // done, or a cycle: keep going
      state[b] = false;
      for (final n in [
        ..._ancestorsAndSelf(b.source),
        ..._ancestors(b.destination),
      ]) {
        final dependency = byDestination[n];
        if (dependency != null && !identical(dependency, b)) visit(dependency);
      }
      state[b] = true;
      _ordered.add(b);
    }

    bound.forEach(visit);
  }

  /// The importer's root, whose child space is the VRM model space.
  final Node modelRoot;

  final List<_Bound> _ordered = [];

  /// When false, [update] leaves the constrained nodes alone.
  bool enabled = true;

  /// How many constraints the model has.
  int get count => _ordered.length;

  /// Writes every constrained node from the current source transforms.
  void update() {
    if (!enabled || _ordered.isEmpty) return;
    final rootInverse = Matrix4.inverted(modelRoot.globalTransform);
    for (final b in _ordered) {
      final d = b.definition;
      final rest = b.destinationRest;
      final Matrix3 target;
      switch (d) {
        case VrmRotationConstraint():
          // rest * (sourceRest^-1 * source)
          target =
              rest *
                      (_transposed(b.sourceRest) * _localRotation(b.source)
                          as Matrix3)
                  as Matrix3;
        case VrmRollConstraint(:final rollAxis):
          // The source's rotation from its rest, seen in the destination's
          // rest frame, reduced to its twist about the roll axis.
          final delta =
              _transposed(rest) *
                      _localRotation(b.source) *
                      _transposed(b.sourceRest) *
                      rest
                  as Matrix3;
          final swung = delta.transformed(rollAxis.clone());
          target = rest * _fromTo(swung, rollAxis) * delta as Matrix3;
        case VrmAimConstraint(:final aimAxis):
          final parent = b.destination.parent;
          final parentRotation = parent == null || identical(parent, modelRoot)
              ? Matrix3.identity()
              : _rotationOf(rootInverse * parent.globalTransform as Matrix4);
          final from = (parentRotation * rest as Matrix3).transformed(
            aimAxis.clone(),
          );
          final to =
              (rootInverse * b.source.globalTransform as Matrix4)
                  .getTranslation() -
              (rootInverse * b.destination.globalTransform as Matrix4)
                  .getTranslation();
          if (to.length2 < 1e-12) continue;
          to.normalize();
          target =
              _transposed(parentRotation) *
                      _fromTo(from, to) *
                      parentRotation *
                      rest
                  as Matrix3;
      }
      b.write(_slerpFrom(rest, target, d.weight));
    }
  }

  static Iterable<Node> _ancestors(Node node) sync* {
    for (var n = node.parent; n != null; n = n.parent) {
      yield n;
    }
  }

  static Iterable<Node> _ancestorsAndSelf(Node node) sync* {
    yield node;
    yield* _ancestors(node);
  }

  static Matrix3 _transposed(Matrix3 m) => Matrix3.copy(m)..transpose();

  static Matrix3 _localRotation(Node node) {
    final t = Vector3.zero();
    final q = Quaternion.identity();
    final s = Vector3.zero();
    node.localTransform.decompose(t, q, s);
    return q.asRotationMatrix();
  }

  static Matrix3 _rotationOf(Matrix4 m) {
    final t = Vector3.zero();
    final q = Quaternion.identity();
    final s = Vector3.zero();
    m.decompose(t, q, s);
    return q.asRotationMatrix();
  }

  /// Rotation part way from [from] to [to]: `from * (from^-1 * to)^weight`.
  static Matrix3 _slerpFrom(Matrix3 from, Matrix3 to, double weight) {
    if (weight >= 1) return to;
    if (weight <= 0) return from;
    final q = Quaternion.fromRotation(_transposed(from) * to as Matrix3);
    if (q.w < 0) {
      q.setValues(-q.x, -q.y, -q.z, -q.w);
    }
    final angle = 2 * math.acos(q.w.clamp(-1.0, 1.0));
    final axis = Vector3(q.x, q.y, q.z);
    if (axis.length2 < 1e-12 || angle.abs() < 1e-9) return from;
    return from *
            Quaternion.axisAngle(
              axis..normalize(),
              angle * weight,
            ).asRotationMatrix()
        as Matrix3;
  }

  /// The rotation turning unit vector [from] onto unit vector [to].
  static Matrix3 _fromTo(Vector3 from, Vector3 to) {
    final a = from.normalized();
    final b = to.normalized();
    final d = a.dot(b).clamp(-1.0, 1.0);
    final axis = a.cross(b);
    if (axis.length2 < 1e-12) {
      if (d > 0) return Matrix3.identity();
      final perpendicular = a.cross(
        a.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0),
      )..normalize();
      return Quaternion.axisAngle(perpendicular, math.pi).asRotationMatrix();
    }
    return Quaternion.axisAngle(
      axis..normalize(),
      math.acos(d),
    ).asRotationMatrix();
  }
}
