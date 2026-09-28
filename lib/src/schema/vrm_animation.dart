import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'glb.dart';
import 'gltf_accessor.dart';
import 'vrm_document.dart';

enum VrmInterpolation { linear, step, cubicSpline }

/// One animated value over time: keyframe [times] and [values]
/// ([components] floats per key; three times that for cubic splines, as
/// in-tangent, value, out-tangent).
class VrmAnimationTrack {
  VrmAnimationTrack({
    required this.times,
    required this.values,
    required this.components,
    required this.interpolation,
    this.isRotation = false,
  });

  final Float32List times;
  final Float32List values;
  final int components;
  final VrmInterpolation interpolation;

  /// Quaternions (x, y, z, w): interpolated along the sphere and normalized.
  final bool isRotation;

  double get duration => times.isEmpty ? 0 : times.last;

  /// Writes the value at time [t] (seconds, clamped to the keys) into [out].
  void sample(double t, List<double> out) {
    final n = times.length;
    if (n == 0) return;
    final cubic = interpolation == VrmInterpolation.cubicSpline;
    int valueAt(int key) => (cubic ? key * 3 + 1 : key) * components;
    if (n == 1 || t <= times[0]) {
      _copy(valueAt(0), out);
      return;
    }
    if (t >= times[n - 1]) {
      _copy(valueAt(n - 1), out);
      return;
    }
    var lo = 0;
    var hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final dt = times[hi] - times[lo];
    final u = dt <= 0 ? 0.0 : (t - times[lo]) / dt;
    switch (interpolation) {
      case VrmInterpolation.step:
        _copy(valueAt(lo), out);
      case VrmInterpolation.linear:
        final a = valueAt(lo);
        final b = valueAt(hi);
        if (isRotation) {
          _slerp(a, b, u, out);
        } else {
          for (var c = 0; c < components; c++) {
            out[c] = values[a + c] + (values[b + c] - values[a + c]) * u;
          }
        }
      case VrmInterpolation.cubicSpline:
        final u2 = u * u;
        final u3 = u2 * u;
        final h00 = 2 * u3 - 3 * u2 + 1;
        final h10 = u3 - 2 * u2 + u;
        final h01 = -2 * u3 + 3 * u2;
        final h11 = u3 - u2;
        final p0 = valueAt(lo);
        final m0 = p0 + components; // out-tangent of lo
        final p1 = valueAt(hi);
        final m1 = p1 - components; // in-tangent of hi
        for (var c = 0; c < components; c++) {
          out[c] =
              h00 * values[p0 + c] +
              h10 * dt * values[m0 + c] +
              h01 * values[p1 + c] +
              h11 * dt * values[m1 + c];
        }
        if (isRotation) _normalize(out);
    }
  }

  void _copy(int offset, List<double> out) {
    for (var c = 0; c < components; c++) {
      out[c] = values[offset + c];
    }
  }

  void _slerp(int a, int b, double u, List<double> out) {
    var bx = values[b], by = values[b + 1], bz = values[b + 2];
    var bw = values[b + 3];
    final ax = values[a], ay = values[a + 1], az = values[a + 2];
    final aw = values[a + 3];
    var cos = ax * bx + ay * by + az * bz + aw * bw;
    if (cos < 0) {
      cos = -cos;
      bx = -bx;
      by = -by;
      bz = -bz;
      bw = -bw;
    }
    double s0, s1;
    if (cos > 0.9995) {
      s0 = 1 - u;
      s1 = u;
    } else {
      final theta = math.acos(cos);
      final sin = math.sin(theta);
      s0 = math.sin((1 - u) * theta) / sin;
      s1 = math.sin(u * theta) / sin;
    }
    out[0] = ax * s0 + bx * s1;
    out[1] = ay * s0 + by * s1;
    out[2] = az * s0 + bz * s1;
    out[3] = aw * s0 + bw * s1;
    _normalize(out);
  }

  static void _normalize(List<double> q) {
    final l = math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
    if (l < 1e-12) return;
    for (var i = 0; i < 4; i++) {
      q[i] /= l;
    }
  }
}

/// A VRM Animation (`.vrma`, `VRMC_vrm_animation`), converted to what a VRM
/// humanoid consumes: normalized bone rotations (the same space as
/// `VrmHumanoidRig.setNormalizedRotation`), the hips position, and
/// expression weights.
class VrmAnimation {
  VrmAnimation._({
    required this.rotations,
    required this.hipsPosition,
    required this.restHipsHeight,
    required this.expressions,
    required this.lookAt,
    required this.duration,
  });

  /// Normalized rotation (x, y, z, w) per humanoid bone.
  final Map<VrmHumanBone, VrmAnimationTrack> rotations;

  /// The hips position in the animation's model space, if animated.
  final VrmAnimationTrack? hipsPosition;

  /// The hips height of the animation's T-pose, for scaling [hipsPosition]
  /// to a model of another size.
  final double restHipsHeight;

  /// Expression weight per expression name (not yet clamped).
  final Map<String, VrmAnimationTrack> expressions;

  /// The look-at node's local rotation (x, y, z, w), if animated. Its +Z is
  /// the gaze direction in model space.
  final VrmAnimationTrack? lookAt;

  /// Seconds, the end of the longest track.
  final double duration;

  /// Reads animation [animation] (the first by default) of a `.vrma` file.
  static VrmAnimation fromGlb(Uint8List bytes, {int animation = 0}) {
    final glb = GlbContainer.parse(bytes);
    return fromGltf(glb.json, glb.binary, animation: animation);
  }

  /// Reads animation [animation] from decoded glTF JSON and its BIN chunk.
  static VrmAnimation fromGltf(
    Map<String, dynamic> gltf,
    Uint8List? binary, {
    int animation = 0,
  }) {
    final ext =
        (gltf['extensions'] as Map<String, dynamic>?)?['VRMC_vrm_animation']
            as Map<String, dynamic>?;
    if (ext == null) {
      throw const FormatException(
        'not a VRM Animation (no VRMC_vrm_animation)',
      );
    }
    final nodes = (gltf['nodes'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final parents = List<int?>.filled(nodes.length, null);
    for (var i = 0; i < nodes.length; i++) {
      for (final c in (nodes[i]['children'] as List? ?? const []).cast<int>()) {
        if (c >= 0 && c < nodes.length) parents[c] = i;
      }
    }
    final world = List<Matrix4?>.filled(nodes.length, null);
    Matrix4 worldOf(int i) => world[i] ??= () {
      final local = _localMatrix(nodes[i]);
      final p = parents[i];
      return p == null ? local : worldOf(p) * local as Matrix4;
    }();
    Quaternion worldRotation(int? i) =>
        i == null ? Quaternion.identity() : _rotationOf(worldOf(i));

    final boneOfNode = <int, VrmHumanBone>{};
    final humanBones =
        (ext['humanoid'] as Map<String, dynamic>?)?['humanBones']
            as Map<String, dynamic>? ??
        const {};
    for (final e in humanBones.entries) {
      final bone = VrmHumanBone.byName(e.key);
      final node = (e.value as Map<String, dynamic>)['node'];
      if (bone != null && node is int && node >= 0 && node < nodes.length) {
        boneOfNode[node] = bone;
      }
    }
    final expressionOfNode = <int, String>{};
    final expressionsJson =
        ext['expressions'] as Map<String, dynamic>? ?? const {};
    for (final group in ['preset', 'custom']) {
      final entries =
          expressionsJson[group] as Map<String, dynamic>? ?? const {};
      for (final e in entries.entries) {
        final node = (e.value as Map<String, dynamic>)['node'];
        if (node is int) expressionOfNode.putIfAbsent(node, () => e.key);
      }
    }
    final lookAtNode =
        (ext['lookAt'] as Map<String, dynamic>?)?['node'] as int?;

    final animations = (gltf['animations'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final rotations = <VrmHumanBone, VrmAnimationTrack>{};
    final expressions = <String, VrmAnimationTrack>{};
    VrmAnimationTrack? hips;
    VrmAnimationTrack? lookAt;
    if (animation >= 0 && animation < animations.length) {
      final a = animations[animation];
      final samplers = (a['samplers'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final ch
          in (a['channels'] as List? ?? const [])
              .cast<Map<String, dynamic>>()) {
        final target = ch['target'] as Map<String, dynamic>? ?? const {};
        final node = target['node'];
        final path = target['path'];
        final samplerIndex = ch['sampler'];
        if (node is! int || samplerIndex is! int) continue;
        if (samplerIndex < 0 || samplerIndex >= samplers.length) continue;
        final sampler = samplers[samplerIndex];
        final times = readGltfAccessor(gltf, binary, sampler['input'] as int);
        final values = readGltfAccessor(gltf, binary, sampler['output'] as int);
        if (times == null || values == null || times.isEmpty) continue;
        final interpolation = switch (sampler['interpolation']) {
          'STEP' => VrmInterpolation.step,
          'CUBICSPLINE' => VrmInterpolation.cubicSpline,
          _ => VrmInterpolation.linear,
        };
        final bone = boneOfNode[node];
        if (path == 'rotation' && bone != null) {
          // Normalized = P * local * W^-1 (P: parent's rest world rotation,
          // W: the bone's). Linear in the quaternion, so tangents convert
          // the same way.
          final p = worldRotation(parents[node]);
          final wInverse = worldRotation(node)..conjugate();
          for (var i = 0; i + 3 < values.length; i += 4) {
            final q = _mul(
              _mul(
                p,
                Quaternion(
                  values[i],
                  values[i + 1],
                  values[i + 2],
                  values[i + 3],
                ),
              ),
              wInverse,
            );
            values
              ..[i] = q.x
              ..[i + 1] = q.y
              ..[i + 2] = q.z
              ..[i + 3] = q.w;
          }
          rotations[bone] = VrmAnimationTrack(
            times: times,
            values: values,
            components: 4,
            interpolation: interpolation,
            isRotation: true,
          );
        } else if (path == 'translation' && bone == VrmHumanBone.hips) {
          // Into the animation's model space: the parent's rest world
          // transform (its linear part for the tangents).
          final parent = parents[node];
          final m = parent == null ? Matrix4.identity() : worldOf(parent);
          final keys = values.length ~/ 3;
          final perKey = interpolation == VrmInterpolation.cubicSpline ? 3 : 1;
          for (var k = 0; k < keys; k++) {
            final v = Vector3(
              values[k * 3],
              values[k * 3 + 1],
              values[k * 3 + 2],
            );
            final isValue = perKey == 1 || k % 3 == 1;
            final r = isValue ? m.transform3(v) : m.rotated3(v);
            values
              ..[k * 3] = r.x
              ..[k * 3 + 1] = r.y
              ..[k * 3 + 2] = r.z;
          }
          hips = VrmAnimationTrack(
            times: times,
            values: values,
            components: 3,
            interpolation: interpolation,
          );
        } else if (path == 'translation' && expressionOfNode[node] != null) {
          final perKey = values.length ~/ 3;
          final xs = Float32List(perKey);
          for (var k = 0; k < perKey; k++) {
            xs[k] = values[k * 3];
          }
          expressions[expressionOfNode[node]!] = VrmAnimationTrack(
            times: times,
            values: xs,
            components: 1,
            interpolation: interpolation,
          );
        } else if (path == 'rotation' && node == lookAtNode) {
          lookAt = VrmAnimationTrack(
            times: times,
            values: values,
            components: 4,
            interpolation: interpolation,
            isRotation: true,
          );
        }
      }
    }

    final hipsNode = boneOfNode.entries
        .where((e) => e.value == VrmHumanBone.hips)
        .firstOrNull
        ?.key;
    final restHipsHeight = hipsNode == null
        ? 1.0
        : worldOf(hipsNode).getTranslation().y;
    final tracks = [...rotations.values, ...expressions.values, ?hips, ?lookAt];
    return VrmAnimation._(
      rotations: rotations,
      hipsPosition: hips,
      restHipsHeight: restHipsHeight,
      expressions: expressions,
      lookAt: lookAt,
      duration: tracks.fold(0.0, (d, t) => math.max(d, t.duration)),
    );
  }

  static Matrix4 _localMatrix(Map<String, dynamic> node) {
    final m = (node['matrix'] as List?)?.cast<num>();
    if (m != null && m.length == 16) {
      return Matrix4.fromList([for (final v in m) v.toDouble()]);
    }
    final t = (node['translation'] as List?)?.cast<num>();
    final r = (node['rotation'] as List?)?.cast<num>();
    final s = (node['scale'] as List?)?.cast<num>();
    return Matrix4.compose(
      t == null
          ? Vector3.zero()
          : Vector3(t[0].toDouble(), t[1].toDouble(), t[2].toDouble()),
      r == null
          ? Quaternion.identity()
          : Quaternion(
              r[0].toDouble(),
              r[1].toDouble(),
              r[2].toDouble(),
              r[3].toDouble(),
            ),
      s == null
          ? Vector3.all(1)
          : Vector3(s[0].toDouble(), s[1].toDouble(), s[2].toDouble()),
    );
  }

  static Quaternion _rotationOf(Matrix4 m) {
    final t = Vector3.zero();
    final q = Quaternion.identity();
    final s = Vector3.zero();
    m.decompose(t, q, s);
    return q;
  }

  /// Hamilton product a * b (b applied first, as with rotation matrices).
  /// Written out rather than vector_math's operators, whose conventions
  /// differ between Quaternion methods.
  static Quaternion _mul(Quaternion a, Quaternion b) => Quaternion(
    a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
  );
}
