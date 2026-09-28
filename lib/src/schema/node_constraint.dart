import 'package:vector_math/vector_math.dart';

/// A `VRMC_node_constraint` on one glTF node (the destination), driven by
/// another node (the source).
sealed class VrmNodeConstraint {
  const VrmNodeConstraint({
    required this.destination,
    required this.source,
    required this.weight,
  });

  /// glTF node index the constraint moves.
  final int destination;

  /// glTF node index it follows.
  final int source;

  /// 0 (no effect) to 1 (full effect).
  final double weight;

  /// Parses the constraint on glTF node [index] (its `nodes[index]` JSON),
  /// or returns null when it has none or it is malformed.
  static VrmNodeConstraint? parse(
    int index,
    Map<String, dynamic> node,
    int nodeCount,
  ) {
    final ext =
        (node['extensions'] as Map<String, dynamic>?)?['VRMC_node_constraint']
            as Map<String, dynamic>?;
    final c = ext?['constraint'] as Map<String, dynamic>?;
    if (c == null) return null;
    (int, double)? common(Map<String, dynamic>? j) {
      final source = j?['source'];
      if (source is! int || source < 0 || source >= nodeCount) return null;
      if (source == index) return null;
      return (source, ((j!['weight'] as num?) ?? 1).toDouble().clamp(0, 1));
    }

    final roll = c['roll'] as Map<String, dynamic>?;
    if (common(roll) case (final source, final weight)) {
      final axis = switch (roll!['rollAxis']) {
        'X' => Vector3(1, 0, 0),
        'Y' => Vector3(0, 1, 0),
        'Z' => Vector3(0, 0, 1),
        _ => null,
      };
      if (axis == null) return null;
      return VrmRollConstraint(
        destination: index,
        source: source,
        weight: weight,
        rollAxis: axis,
      );
    }
    final aim = c['aim'] as Map<String, dynamic>?;
    if (common(aim) case (final source, final weight)) {
      final axis = switch (aim!['aimAxis']) {
        'PositiveX' => Vector3(1, 0, 0),
        'NegativeX' => Vector3(-1, 0, 0),
        'PositiveY' => Vector3(0, 1, 0),
        'NegativeY' => Vector3(0, -1, 0),
        'PositiveZ' => Vector3(0, 0, 1),
        'NegativeZ' => Vector3(0, 0, -1),
        _ => null,
      };
      if (axis == null) return null;
      return VrmAimConstraint(
        destination: index,
        source: source,
        weight: weight,
        aimAxis: axis,
      );
    }
    final rotation = c['rotation'] as Map<String, dynamic>?;
    if (common(rotation) case (final source, final weight)) {
      return VrmRotationConstraint(
        destination: index,
        source: source,
        weight: weight,
      );
    }
    return null;
  }
}

/// Turns the destination about [rollAxis] (its own rest axis) by the
/// source's rotation about that axis.
class VrmRollConstraint extends VrmNodeConstraint {
  const VrmRollConstraint({
    required super.destination,
    required super.source,
    required super.weight,
    required this.rollAxis,
  });

  final Vector3 rollAxis;
}

/// Turns the destination so its [aimAxis] (in its rest local space) points
/// at the source.
class VrmAimConstraint extends VrmNodeConstraint {
  const VrmAimConstraint({
    required super.destination,
    required super.source,
    required super.weight,
    required this.aimAxis,
  });

  final Vector3 aimAxis;
}

/// Gives the destination the source's rotation from its rest.
class VrmRotationConstraint extends VrmNodeConstraint {
  const VrmRotationConstraint({
    required super.destination,
    required super.source,
    required super.weight,
  });
}
