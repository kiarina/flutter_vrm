import 'package:vector_math/vector_math.dart';

/// A `VRMC_springBone` collider shape, in the collider node's local space.
sealed class VrmSpringColliderShape {
  const VrmSpringColliderShape(this.offset, this.radius);

  final Vector3 offset;
  final double radius;
}

class VrmSpringSphere extends VrmSpringColliderShape {
  const VrmSpringSphere(super.offset, super.radius);
}

/// A capsule from [offset] to [tail].
class VrmSpringCapsule extends VrmSpringColliderShape {
  const VrmSpringCapsule(super.offset, super.radius, this.tail);

  final Vector3 tail;
}

class VrmSpringCollider {
  const VrmSpringCollider(this.node, this.shape);

  /// glTF node index the shape is attached to.
  final int node;
  final VrmSpringColliderShape shape;
}

class VrmSpringColliderGroup {
  const VrmSpringColliderGroup(this.name, this.colliders);

  final String name;

  /// Indices into [VrmSpringBoneDefinition.colliders].
  final List<int> colliders;
}

/// One joint of a spring chain. Its settings drive the segment from this
/// joint to the next one; the last joint is only the chain's tail.
class VrmSpringJoint {
  const VrmSpringJoint({
    required this.node,
    this.hitRadius = 0,
    this.stiffness = 1,
    this.gravityPower = 0,
    Vector3? gravityDir,
    this.dragForce = 0.5,
  }) : _gravityDir = gravityDir;

  /// glTF node index.
  final int node;
  final double hitRadius;
  final double stiffness;
  final double gravityPower;
  final Vector3? _gravityDir;
  final double dragForce;

  /// Unit gravity direction (default straight down).
  Vector3 get gravityDir => _gravityDir?.clone() ?? Vector3(0, -1, 0);
}

class VrmSpring {
  const VrmSpring({
    required this.name,
    required this.joints,
    required this.colliderGroups,
    this.center,
  });

  final String name;
  final List<VrmSpringJoint> joints;

  /// Indices into [VrmSpringBoneDefinition.colliderGroups].
  final List<int> colliderGroups;

  /// glTF node index whose space the chain simulates in (so that moving it
  /// does not swing the chain), or null for world space.
  final int? center;
}

/// `VRMC_springBone`: the swaying chains (hair, clothes) and their colliders.
class VrmSpringBoneDefinition {
  const VrmSpringBoneDefinition({
    required this.colliders,
    required this.colliderGroups,
    required this.springs,
  });

  final List<VrmSpringCollider> colliders;
  final List<VrmSpringColliderGroup> colliderGroups;
  final List<VrmSpring> springs;

  /// Parses the extension object; nodes outside [nodeCount] and chains with
  /// fewer than two joints are dropped.
  static VrmSpringBoneDefinition? parse(
    Map<String, dynamic>? j,
    int nodeCount,
  ) {
    if (j == null) return null;
    bool validNode(Object? n) => n is int && n >= 0 && n < nodeCount;
    List<Map<String, dynamic>> list(Object? o) =>
        (o as List? ?? const []).cast<Map<String, dynamic>>();

    final colliders = <VrmSpringCollider>[];
    final colliderIndex = <int, int>{}; // source index -> kept index
    final sourceColliders = list(j['colliders']);
    for (var i = 0; i < sourceColliders.length; i++) {
      final c = sourceColliders[i];
      final shape = _shape(c['shape'] as Map<String, dynamic>?);
      if (!validNode(c['node']) || shape == null) continue;
      colliderIndex[i] = colliders.length;
      colliders.add(VrmSpringCollider(c['node'] as int, shape));
    }

    final groups = [
      for (final g in list(j['colliderGroups']))
        VrmSpringColliderGroup(g['name'] as String? ?? '', [
          for (final i in (g['colliders'] as List? ?? const []).cast<int>())
            ?colliderIndex[i],
        ]),
    ];

    final springs = <VrmSpring>[];
    for (final s in list(j['springs'])) {
      final joints = [
        for (final jt in list(s['joints']))
          if (validNode(jt['node']))
            VrmSpringJoint(
              node: jt['node'] as int,
              hitRadius: _num(jt['hitRadius'], 0),
              stiffness: _num(jt['stiffness'], 1),
              gravityPower: _num(jt['gravityPower'], 0),
              gravityDir: _direction(jt['gravityDir']),
              dragForce: _num(jt['dragForce'], 0.5),
            ),
      ];
      if (joints.length < 2) continue;
      springs.add(
        VrmSpring(
          name: s['name'] as String? ?? '',
          joints: joints,
          colliderGroups: [
            for (final g
                in (s['colliderGroups'] as List? ?? const []).cast<int>())
              if (g >= 0 && g < groups.length) g,
          ],
          center: validNode(s['center']) ? s['center'] as int : null,
        ),
      );
    }
    return VrmSpringBoneDefinition(
      colliders: colliders,
      colliderGroups: groups,
      springs: springs,
    );
  }

  static VrmSpringColliderShape? _shape(Map<String, dynamic>? j) {
    final sphere = j?['sphere'] as Map<String, dynamic>?;
    if (sphere != null) {
      return VrmSpringSphere(
        _vec3(sphere['offset']) ?? Vector3.zero(),
        _num(sphere['radius'], 0),
      );
    }
    final capsule = j?['capsule'] as Map<String, dynamic>?;
    if (capsule != null) {
      return VrmSpringCapsule(
        _vec3(capsule['offset']) ?? Vector3.zero(),
        _num(capsule['radius'], 0),
        _vec3(capsule['tail']) ?? Vector3.zero(),
      );
    }
    return null;
  }

  static Vector3? _direction(Object? v) {
    final d = _vec3(v);
    return d == null || d.length2 == 0 ? null : d.normalized();
  }

  static double _num(Object? v, double d) => (v as num?)?.toDouble() ?? d;

  static Vector3? _vec3(Object? v) {
    final l = (v as List?)?.cast<num>();
    if (l == null || l.length < 3) return null;
    return Vector3(l[0].toDouble(), l[1].toDouble(), l[2].toDouble());
  }
}
