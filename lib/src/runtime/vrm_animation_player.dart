import 'package:vector_math/vector_math.dart';

import '../schema/vrm_animation.dart';
import '../schema/vrm_document.dart';
import 'vrm_avatar.dart';

/// Plays a [VrmAnimation] on a [VrmAvatar].
///
/// ```dart
/// final player = VrmAnimationPlayer(avatar, VrmAnimation.fromGlb(bytes));
///
/// // every frame, before avatar.update:
/// player.update(deltaSeconds);
/// avatar.update(deltaSeconds);
/// ```
///
/// Bones the animation moves are overwritten each frame; the others keep
/// whatever you set. A bone the animation has but the model lacks (an
/// optional bone such as `upperChest`) is folded into the model's nearest
/// child bones, as the VRM Animation spec recommends. The hips translation
/// is scaled by the ratio of the two T-pose hips heights.
class VrmAnimationPlayer {
  VrmAnimationPlayer(this.avatar, this.animation) {
    final mapped = avatar.humanoid.bones.toSet();
    for (final bone in mapped) {
      // This bone's own track plus those of unmapped bones between it and
      // its nearest mapped ancestor, outermost first.
      final chain = <VrmAnimationTrack>[];
      final own = animation.rotations[bone];
      if (own != null) chain.add(own);
      for (
        var p = bone.parent;
        p != null && !mapped.contains(p);
        p = p.parent
      ) {
        final t = animation.rotations[p];
        if (t != null) chain.insert(0, t);
      }
      if (chain.isNotEmpty) _chains[bone] = chain;
    }
    final modelHips = avatar.humanoid.restModelPosition(VrmHumanBone.hips);
    _hipsScale = modelHips == null || animation.restHipsHeight <= 0
        ? 1
        : modelHips.y / animation.restHipsHeight;
  }

  final VrmAvatar avatar;
  final VrmAnimation animation;

  /// Seconds into the animation.
  double time = 0;

  /// Playback rate (1 is normal speed, negative plays backwards).
  double speed = 1;

  /// Wrap around at the end (otherwise hold the last frame).
  bool loop = true;

  /// When false, [update] does not advance [time] (it still applies).
  bool playing = true;

  /// Whether the animation's look-at track (if any) drives
  /// `avatar.lookAt.target`.
  bool driveLookAt = true;

  final Map<VrmHumanBone, List<VrmAnimationTrack>> _chains = {};
  late final double _hipsScale;
  final List<double> _q = List.filled(4, 0);
  final List<double> _v = List.filled(4, 0);

  /// Whether a non-looping animation has reached its end.
  bool get finished =>
      !loop && (speed >= 0 ? time >= animation.duration : time <= 0);

  /// Advances by [deltaSeconds] (times [speed]) and applies the pose.
  void update(double deltaSeconds) {
    if (playing) {
      time += deltaSeconds * speed;
      final d = animation.duration;
      if (loop && d > 0) {
        time %= d;
      } else {
        time = time.clamp(0.0, d);
      }
    }
    apply();
  }

  /// Writes the pose, expressions, and look-at at [time] into the avatar.
  /// Call before `avatar.update`, which applies them.
  void apply() {
    final humanoid = avatar.humanoid;
    for (final e in _chains.entries) {
      Matrix3? rotation;
      for (final track in e.value) {
        track.sample(time, _q);
        final m = Quaternion(_q[0], _q[1], _q[2], _q[3]).asRotationMatrix();
        rotation = rotation == null ? m : rotation * m as Matrix3;
      }
      humanoid.setNormalizedRotation(e.key, Quaternion.fromRotation(rotation!));
    }
    final hips = animation.hipsPosition;
    if (hips != null) {
      hips.sample(time, _v);
      humanoid.setHipsPosition(Vector3(_v[0], _v[1], _v[2]) * _hipsScale);
    }
    for (final e in animation.expressions.entries) {
      e.value.sample(time, _v);
      avatar.expressions.setValue(e.key, _v[0].clamp(0.0, 1.0));
    }
    final lookAt = animation.lookAt;
    final head = humanoid.node(VrmHumanBone.head);
    if (driveLookAt && lookAt != null && head != null) {
      lookAt.sample(time, _q);
      // The node's +Z is the gaze, in model space, from the head.
      final gaze = Quaternion(
        _q[0],
        _q[1],
        _q[2],
        _q[3],
      ).asRotationMatrix().transformed(Vector3(0, 0, 1));
      final from = humanoid.modelTransformOf(head).getTranslation();
      avatar.lookAt.target = avatar.modelRoot.globalTransform.transform3(
        from + gaze * 10,
      );
    }
  }
}
