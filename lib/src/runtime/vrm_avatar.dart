import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

import '../schema/glb.dart';
import '../schema/vrm_document.dart';
import 'expression_manager.dart';
import 'gltf_mapping.dart';
import 'humanoid_rig.dart';
import 'look_at.dart';

/// A VRM 1.0 avatar in a flutter_scene [Scene].
///
/// ```dart
/// final avatar = await VrmAvatar.fromBytes(bytes);
/// scene.add(avatar.root);
///
/// avatar.expressions.setPreset(VrmExpressionPreset.happy, 0.8);
/// avatar.lookAt.target = camera.position;
///
/// // every frame
/// avatar.update(deltaSeconds);
/// ```
///
/// Move, turn, or scale the avatar through [root]. The model faces +Z in its
/// own (model) space, which the importer maps to -Z in the scene.
class VrmAvatar {
  VrmAvatar._({
    required this.document,
    required this.root,
    required this.modelRoot,
    required this.gltfNodes,
    required this.humanoid,
    required this.expressions,
    required this.lookAt,
  });

  /// The parsed VRM content (meta, humanoid, expressions, look-at).
  final VrmDocument document;

  /// Add this to the scene; transform it to place the avatar.
  final Node root;

  /// The importer's root, whose child space is the VRM model space.
  final Node modelRoot;

  /// Imported nodes by glTF node index.
  final List<Node?> gltfNodes;
  final VrmHumanoidRig humanoid;
  final VrmExpressionManager expressions;
  final VrmLookAt lookAt;

  /// Automatic blinking; set [VrmAutoBlink.enabled] to false to drive
  /// `blink` yourself.
  final VrmAutoBlink autoBlink = VrmAutoBlink();

  VrmMeta get meta => document.meta;

  /// Loads a `.vrm` file.
  ///
  /// [onWarning] receives the importer's non-fatal warnings; by default the
  /// expected "unrecognized extension VRMC_*" ones are dropped.
  static Future<VrmAvatar> fromBytes(
    Uint8List bytes, {
    void Function(String message)? onWarning,
  }) async {
    final glb = GlbContainer.parse(bytes);
    final document = VrmDocument.fromGltfJson(glb.json);
    final imported = await Node.fromGlbBytes(
      bytes,
      onWarning: (w) {
        final text = '$w';
        if (onWarning != null) {
          onWarning(text);
        } else if (!text.contains('VRMC_')) {
          debugPrint('flutter_vrm: $text');
        }
      },
    );
    return fromImported(document, imported);
  }

  /// Wraps a model flutter_scene already imported from the same bytes that
  /// produced [document].
  static VrmAvatar fromImported(VrmDocument document, Node imported) {
    final root = Node(name: 'vrm:${document.meta.name}')..add(imported);
    final nodes = mapGltfNodes(document.gltf, imported);
    final materials = mapGltfMaterials(document.gltf, nodes);
    final humanoid = VrmHumanoidRig(document.humanBones, nodes, imported);
    final expressions = VrmExpressionManager(
      document.expressions,
      nodes,
      materials,
    );
    return VrmAvatar._(
      document: document,
      root: root,
      modelRoot: imported,
      gltfNodes: nodes,
      humanoid: humanoid,
      expressions: expressions,
      lookAt: VrmLookAt(document.lookAt, humanoid, expressions),
    );
  }

  /// Applies the pose, look-at, and expressions for this frame.
  ///
  /// Order: humanoid pose, look-at (which reads the posed head and may set
  /// eye rotations or look expressions), then expressions.
  void update(double deltaSeconds) {
    humanoid.apply();
    lookAt.update();
    humanoid.apply();
    autoBlink.update(deltaSeconds, expressions);
    expressions.apply();
  }
}

/// Blinks at random intervals by driving the `blink` expression.
class VrmAutoBlink {
  VrmAutoBlink({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  /// When false, `blink` is left to the caller.
  bool enabled = true;

  /// Seconds between blinks: [minInterval] plus up to [randomInterval].
  double minInterval = 2.0;
  double randomInterval = 4.0;

  /// How long one blink takes, closing and opening.
  double duration = 0.16;

  double _timer = 1.0;
  double _phase = -1;

  void update(double dt, VrmExpressionManager expressions) {
    if (!enabled) return;
    if (_phase < 0) {
      _timer -= dt;
      if (_timer <= 0) {
        _phase = 0;
        _timer = minInterval + _random.nextDouble() * randomInterval;
      }
    }
    var value = 0.0;
    if (_phase >= 0) {
      _phase += dt / duration;
      value = _phase < 0.5 ? _phase * 2 : (1 - _phase) * 2;
      if (_phase >= 1) _phase = -1;
    }
    expressions.setPreset(VrmExpressionPreset.blink, value.clamp(0.0, 1.0));
  }
}
