import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../schema/vrm_document.dart';
import 'humanoid_rig.dart';

/// Where a ray hit an avatar (see `VrmAvatar.hitTest`).
class VrmHit {
  const VrmHit({
    required this.distance,
    required this.point,
    this.bone,
    this.node,
  });

  /// Distance from the ray origin along its (normalized) direction.
  final double distance;

  /// The hit point, world space.
  final Vector3 point;

  /// The body part: the humanoid bone of the capsule that was hit, or null
  /// for a spring bone collider.
  final VrmHumanBone? bone;

  /// The node the hit shape follows (the bone's node, or the collider's).
  final Node? node;
}

/// One body part's hit capsule: a segment that follows the posed humanoid
/// bones, with a radius. Radii are in the model's own units (meters for a
/// VRM), before any scaling of the avatar.
class VrmHitCapsule {
  VrmHitCapsule._(this.bone, this.radius, this._ends);

  /// The body part this capsule stands for.
  final VrmHumanBone bone;

  /// The capsule's radius in model units; change it to fit a model.
  double radius;

  /// When false, the capsule is ignored (for example, to leave out hands).
  bool enabled = true;

  final (Vector3, Vector3)? Function() _ends;

  /// The capsule's segment in world space for the current pose, or null when
  /// its bones are not available.
  (Vector3, Vector3)? worldSegment() => _ends();
}

/// Builds the hit capsules of a humanoid and intersects rays with them.
class VrmHitShapes {
  VrmHitShapes(
    this._humanoid,
    this._modelRoot, {
    VrmSpringBoneDefinition? springBone,
    List<Node?> gltfNodes = const [],
    Map<String, dynamic>? gltf,
  }) {
    final hips = _humanoid.restModelPosition(VrmHumanBone.hips);
    // Proportions of an average adult with the hips at 0.85 m.
    final s = hips == null || hips.y <= 0 ? 1.0 : hips.y / 0.85;

    Vector3? at(VrmHumanBone b) => _humanoid.worldPosition(b);
    Vector3? first(List<VrmHumanBone> bones) {
      for (final b in bones) {
        final p = at(b);
        if (p != null) return p;
      }
      return null;
    }

    void add(
      VrmHumanBone bone,
      double radius,
      (Vector3, Vector3)? Function() ends,
    ) {
      if (_humanoid.node(bone) == null) return;
      capsules.add(VrmHitCapsule._(bone, radius * s, ends));
    }

    // Two bones; the capsule runs between them.
    (Vector3, Vector3)? between(VrmHumanBone a, List<VrmHumanBone> b) {
      final pa = at(a);
      final pb = first(b);
      return pa == null || pb == null ? null : (pa, pb);
    }

    // From [a], continuing the direction [from] -> [a] for [length] (hands,
    // feet: the bone past them is optional or short).
    (Vector3, Vector3)? beyond(
      VrmHumanBone from,
      VrmHumanBone a,
      double length, {
      List<VrmHumanBone> tip = const [],
    }) {
      final pa = at(a);
      if (pa == null) return null;
      final pt = first(tip);
      if (pt != null) return (pa, pt);
      final pf = at(from);
      if (pf == null) return null;
      final d = pa - pf;
      if (d.length2 < 1e-12) return null;
      return (pa, pa + d.normalized() * (length * _worldScale()));
    }

    // Torso: hips (a little below, for the seat) up to the chest, then the
    // chest up to the neck.
    add(VrmHumanBone.hips, 0.13, () {
      final hipsAt = at(VrmHumanBone.hips);
      final top = first([VrmHumanBone.spine, VrmHumanBone.chest]);
      if (hipsAt == null || top == null) return null;
      final up = top - hipsAt;
      final lowered = up.length2 < 1e-12
          ? hipsAt
          : hipsAt - up.normalized() * (0.05 * s * _worldScale());
      return (lowered, top);
    });
    add(
      VrmHumanBone.spine,
      0.13,
      () => between(VrmHumanBone.spine, [VrmHumanBone.neck, VrmHumanBone.head]),
    );
    // Head: from the head bone up to the top of the model (its meshes'
    // rest bounds), so big-headed and chibi models are covered too. Without
    // bounds, an average adult head.
    final headRest = _humanoid.restModelPosition(VrmHumanBone.head);
    final top = _modelTop(gltf, gltfNodes);
    final measured = headRest == null || top == null ? 0.0 : top - headRest.y;
    final headSize = measured > 0.05 && measured < 2 * (headRest?.y ?? 1)
        ? measured
        : 0.22 * s;
    final headRadius = headSize * 0.45;
    if (_humanoid.node(VrmHumanBone.head) != null) {
      capsules.add(
        VrmHitCapsule._(VrmHumanBone.head, headRadius, () {
          final node = _humanoid.node(VrmHumanBone.head)!;
          final base = node.globalTransform.getTranslation();
          // The head's model +Y in world space: follow the head's rotation.
          final rotation = _humanoid.normalizedModelRotation(VrmHumanBone.head);
          final upModel = (rotation ?? Matrix3.identity()).transformed(
            Vector3(0, 1, 0),
          );
          final up = _modelRoot.globalTransform.rotated3(upModel)..normalize();
          final k = _worldScale();
          final low = headRadius * 0.9;
          final high = math.max(low, headSize - headRadius * 0.9);
          return (base + up * (low * k), base + up * (high * k));
        }),
      );
    }
    for (final (upper, lower, hand, middle) in const [
      (
        VrmHumanBone.leftUpperArm,
        VrmHumanBone.leftLowerArm,
        VrmHumanBone.leftHand,
        VrmHumanBone.leftMiddleDistal,
      ),
      (
        VrmHumanBone.rightUpperArm,
        VrmHumanBone.rightLowerArm,
        VrmHumanBone.rightHand,
        VrmHumanBone.rightMiddleDistal,
      ),
    ]) {
      add(upper, 0.05, () => between(upper, [lower]));
      add(lower, 0.045, () => between(lower, [hand]));
      add(hand, 0.045, () => beyond(lower, hand, 0.16, tip: [middle]));
    }
    for (final (upper, lower, foot, toes) in const [
      (
        VrmHumanBone.leftUpperLeg,
        VrmHumanBone.leftLowerLeg,
        VrmHumanBone.leftFoot,
        VrmHumanBone.leftToes,
      ),
      (
        VrmHumanBone.rightUpperLeg,
        VrmHumanBone.rightLowerLeg,
        VrmHumanBone.rightFoot,
        VrmHumanBone.rightToes,
      ),
    ]) {
      add(upper, 0.08, () => between(upper, [lower]));
      add(lower, 0.06, () => between(lower, [foot]));
      add(foot, 0.05, () => beyond(lower, foot, 0.08, tip: [toes]));
    }

    if (springBone != null) {
      for (final c in springBone.colliders) {
        final node = c.node < gltfNodes.length ? gltfNodes[c.node] : null;
        if (node != null) _colliders.add((node, c.shape));
      }
    }
  }

  final VrmHumanoidRig _humanoid;
  final Node _modelRoot;

  /// The body-part capsules, built from the humanoid bones the model maps.
  final List<VrmHitCapsule> capsules = [];

  final List<(Node, VrmSpringColliderShape)> _colliders = [];

  /// How many spring bone colliders the model has (see [hitTest]).
  int get springColliderCount => _colliders.length;

  /// The highest point of the model's meshes at rest, in model space, from
  /// the POSITION accessors' min / max (which glTF requires) placed by each
  /// mesh node. (The imported geometry of skinned meshes carries no bounds.)
  double? _modelTop(Map<String, dynamic>? gltf, List<Node?> nodes) {
    if (gltf == null) return null;
    final json = (gltf['nodes'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final meshes = (gltf['meshes'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final accessors = (gltf['accessors'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final rootInverse = Matrix4.inverted(_modelRoot.globalTransform);
    double? top;
    for (var i = 0; i < json.length && i < nodes.length; i++) {
      final meshIndex = json[i]['mesh'] as int?;
      final node = nodes[i];
      if (meshIndex == null || node == null || meshIndex >= meshes.length) {
        continue;
      }
      // Skinned meshes ignore their node's transform (glTF); others use it.
      final m = json[i]['skin'] != null
          ? Matrix4.identity()
          : rootInverse * node.globalTransform as Matrix4;
      for (final p
          in (meshes[meshIndex]['primitives'] as List? ?? const [])
              .cast<Map<String, dynamic>>()) {
        final index =
            (p['attributes'] as Map<String, dynamic>?)?['POSITION'] as int?;
        if (index == null || index >= accessors.length) continue;
        final min = (accessors[index]['min'] as List?)?.cast<num>();
        final max = (accessors[index]['max'] as List?)?.cast<num>();
        if (min == null || max == null || min.length < 3 || max.length < 3) {
          continue;
        }
        for (final x in [min[0], max[0]]) {
          for (final y in [min[1], max[1]]) {
            for (final z in [min[2], max[2]]) {
              final v = m.transform3(
                Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
              );
              if (top == null || v.y > top) top = v.y;
            }
          }
        }
      }
    }
    return top;
  }

  double _worldScale() {
    final m = _modelRoot.globalTransform;
    return (Vector3(m.entry(0, 0), m.entry(1, 0), m.entry(2, 0)).length +
            Vector3(m.entry(0, 1), m.entry(1, 1), m.entry(2, 1)).length +
            Vector3(m.entry(0, 2), m.entry(1, 2), m.entry(2, 2)).length) /
        3;
  }

  /// The nearest hit of [ray] on the enabled capsules (and, with
  /// [springColliders], the model's spring bone colliders), or null.
  VrmHit? hitTest(Ray ray, {bool springColliders = false}) {
    final origin = ray.origin;
    final direction = ray.direction.normalized();
    final scale = _worldScale();
    VrmHit? nearest;
    void consider(
      Vector3 a,
      Vector3 b,
      double radius,
      VrmHumanBone? bone,
      Node? node,
    ) {
      final t = _rayCapsule(origin, direction, a, b, radius);
      if (t == null || (nearest != null && t >= nearest!.distance)) return;
      nearest = VrmHit(
        distance: t,
        point: origin + direction * t,
        bone: bone,
        node: node,
      );
    }

    for (final c in capsules) {
      if (!c.enabled) continue;
      final ends = c.worldSegment();
      if (ends == null) continue;
      consider(
        ends.$1,
        ends.$2,
        c.radius * scale,
        c.bone,
        _humanoid.node(c.bone),
      );
    }
    if (springColliders) {
      for (final (node, shape) in _colliders) {
        final m = node.globalTransform;
        final a = m.transform3(shape.offset.clone());
        final b = shape is VrmSpringCapsule
            ? m.transform3(shape.tail.clone())
            : a;
        consider(a, b, shape.radius * scale, null, node);
      }
    }
    return nearest;
  }

  /// Distance along the unit [d] from [o] to the capsule [a]-[b] of radius
  /// [r], or null when missed (or when [o] is inside it).
  static double? _rayCapsule(
    Vector3 o,
    Vector3 d,
    Vector3 a,
    Vector3 b,
    double r,
  ) {
    double? best;
    // The cylinder between the caps (Inigo Quilez's capsule intersection).
    final ba = b - a;
    final baba = ba.dot(ba);
    if (baba > 1e-12) {
      final oa = o - a;
      final bard = ba.dot(d);
      final baoa = ba.dot(oa);
      final qa = baba - bard * bard;
      final qb = baba * d.dot(oa) - baoa * bard;
      final qc = baba * oa.dot(oa) - baoa * baoa - r * r * baba;
      final h = qb * qb - qa * qc;
      if (h >= 0 && qa.abs() > 1e-12) {
        final t = (-qb - math.sqrt(h)) / qa;
        final y = baoa + t * bard;
        if (t >= 0 && y > 0 && y < baba) best = t;
      }
    }
    // The spherical caps at both ends.
    for (final center in [a, b]) {
      final oc = o - center;
      final hb = d.dot(oc);
      final h = hb * hb - (oc.dot(oc) - r * r);
      if (h < 0) continue;
      final t = -hb - math.sqrt(h);
      if (t >= 0 && (best == null || t < best)) best = t;
    }
    return best;
  }
}
