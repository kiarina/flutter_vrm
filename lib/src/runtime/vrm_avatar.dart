import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Ray;

import '../schema/glb.dart';
import '../schema/vrm_document.dart';
import 'expression_manager.dart';
import 'gltf_mapping.dart';
import 'hit_test.dart';
import 'humanoid_rig.dart';
import 'look_at.dart';
import 'material_handles.dart';
import 'mtoon.dart';
import 'node_constraint.dart';
import 'spring_bone.dart';

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
    required this.constraints,
    required this.springBones,
    required this.hitShapes,
    required List<VrmMToonMaterialHandle> mtoonMaterials,
  }) : _mtoonMaterials = mtoonMaterials;

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

  /// `VRMC_node_constraint` helper nodes (twist bones and the like).
  final VrmNodeConstraints constraints;

  /// The body-part capsules [hitTest] uses (adjust radii or disable parts).
  final VrmHitShapes hitShapes;

  /// The swaying chains (hair, clothes) of `VRMC_springBone`.
  final VrmSpringBoneSystem springBones;

  /// Automatic blinking; set [VrmAutoBlink.enabled] to false to drive
  /// `blink` yourself.
  final VrmAutoBlink autoBlink = VrmAutoBlink();

  /// The light MToon materials use (see [VrmMToonLighting.fromScene]).
  final VrmMToonLighting mtoonLighting = VrmMToonLighting();

  final List<VrmMToonMaterialHandle> _mtoonMaterials;
  double _time = 0;

  /// How many of the model's materials render as MToon.
  int get mtoonMaterialCount => _mtoonMaterials.length;

  /// How many of those also draw an outline.
  int get mtoonOutlineCount =>
      _mtoonMaterials.where((m) => m.outlineMaterial != null).length;

  VrmMeta get meta => document.meta;

  /// Loads a `.vrm` file.
  ///
  /// [onWarning] receives the importer's non-fatal warnings; by default the
  /// expected "unrecognized extension VRMC_*" ones are dropped.
  ///
  /// With [mtoon] (the default), materials carrying `VRMC_materials_mtoon`
  /// render with flutter_vrm's MToon shader; otherwise, or if the shader is
  /// unavailable, they keep the glTF PBR / unlit material the importer made.
  static Future<VrmAvatar> fromBytes(
    Uint8List bytes, {
    void Function(String message)? onWarning,
    bool mtoon = true,
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
    return fromImported(document, imported, binary: glb.binary, mtoon: mtoon);
  }

  /// Wraps a model flutter_scene already imported from the same bytes that
  /// produced [document]. [binary] is the file's BIN chunk, needed for the
  /// MToon-only textures.
  static Future<VrmAvatar> fromImported(
    VrmDocument document,
    Node imported, {
    Uint8List? binary,
    bool mtoon = true,
  }) async {
    final root = Node(name: 'vrm:${document.meta.name}')..add(imported);
    final nodes = mapGltfNodes(document.gltf, imported);
    final primitives = mapGltfPrimitives(document.gltf, nodes);

    final handles = <int, List<VrmMaterialHandle>>{};
    final mtoonHandles = <VrmMToonMaterialHandle>[];
    final factory = mtoon
        ? VrmMToonFactory(
            document.gltf,
            binary,
            imported: {
              for (final e in primitives.entries) e.key: e.value.first.material,
            },
          )
        : null;
    Object? mtoonError;
    final created = factory == null
        ? const <int, VrmMToonMaterialHandle?>{}
        : Map.fromEntries(
            await Future.wait([
              for (final e in primitives.entries)
                factory
                    .create(e.key)
                    .then<VrmMToonMaterialHandle?>((h) => h)
                    .catchError((Object error) {
                      mtoonError ??= error;
                      return null;
                    })
                    .then((h) => MapEntry(e.key, h)),
            ]),
          );
    if (mtoonError != null) {
      debugPrint(
        'flutter_vrm: MToon unavailable, keeping the imported materials '
        '($mtoonError)',
      );
    }
    // The mesh each primitive belongs to, for adding outline hulls.
    final owners = <MeshPrimitive, Mesh>{
      for (final node in nodes)
        if (node?.mesh case final mesh?)
          for (final p in mesh.primitives) p: mesh,
    };
    for (final e in primitives.entries) {
      final h = mtoonError == null ? created[e.key] : null;
      if (h != null) {
        for (final p in e.value) {
          p.material = h.material;
          final outline = h.outlineMaterial;
          if (outline != null) {
            owners[p]?.primitives.add(MeshPrimitive(p.geometry, outline));
          }
        }
        handles[e.key] = [h];
        mtoonHandles.add(h);
      } else {
        handles[e.key] = [
          for (final m in {for (final p in e.value) p.material})
            VrmStandardMaterialHandle(m),
        ];
      }
    }

    final humanoid = VrmHumanoidRig(document.humanBones, nodes, imported);
    final expressions = VrmExpressionManager(
      document.expressions,
      nodes,
      handles,
    );
    return VrmAvatar._(
      document: document,
      root: root,
      modelRoot: imported,
      gltfNodes: nodes,
      humanoid: humanoid,
      expressions: expressions,
      lookAt: VrmLookAt(document.lookAt, humanoid, expressions),
      constraints: VrmNodeConstraints(
        document.nodeConstraints,
        nodes,
        imported,
      ),
      hitShapes: VrmHitShapes(
        humanoid,
        imported,
        springBone: document.springBone,
        gltfNodes: nodes,
        gltf: document.gltf,
      ),
      springBones: VrmSpringBoneSystem(document.springBone, nodes, imported),
      mtoonMaterials: mtoonHandles,
    );
  }

  /// Where [ray] (world space, for example from
  /// `camera.screenPointToRay`) first hits this avatar, or null.
  ///
  /// The avatar is tested with capsules that follow its posed humanoid bones
  /// (head, torso, arms, hands, legs, feet), so a sitting or lying avatar is
  /// hit where it is drawn; [VrmHit.bone] tells which part. With
  /// [springColliders], the model's spring bone colliders count too. Long
  /// hair, skirts, and loose clothes outside the capsules are not hit.
  ///
  /// Scene objects in front of the avatar are not considered; compare
  /// [VrmHit.distance] with `Scene.raycast` to let furniture block it.
  VrmHit? hitTest(Ray ray, {bool springColliders = false}) =>
      hitShapes.hitTest(ray, springColliders: springColliders);

  /// Whether [node] belongs to this avatar (for example, to leave the
  /// avatar out of `Scene.raycast(ray, where: (n) => !avatar.contains(n))`,
  /// which would test its meshes in the T-pose).
  bool contains(Node node) {
    for (Node? n = node; n != null; n = n.parent) {
      if (identical(n, root)) return true;
    }
    return false;
  }

  /// The nearest hit of [ray] among [avatars], with the avatar it hit.
  static (VrmAvatar, VrmHit)? hitTestAll(
    Iterable<VrmAvatar> avatars,
    Ray ray, {
    bool springColliders = false,
  }) {
    (VrmAvatar, VrmHit)? nearest;
    for (final a in avatars) {
      final hit = a.hitTest(ray, springColliders: springColliders);
      if (hit != null &&
          (nearest == null || hit.distance < nearest.$2.distance)) {
        nearest = (a, hit);
      }
    }
    return nearest;
  }

  /// Applies the pose, look-at, and expressions for this frame.
  ///
  /// Order: humanoid pose, look-at (which reads the posed head and may set
  /// eye rotations or look expressions), node constraints, spring bones
  /// (which follow the posed body), then expressions.
  ///
  /// Pass the [camera] that draws the avatar so MToon outlines sized in
  /// screen coordinates follow its field of view.
  void update(double deltaSeconds, {Camera? camera}) {
    _time += deltaSeconds;
    final fovY = camera is PerspectiveCamera
        ? camera.fovRadiansY
        : 45 * math.pi / 180;
    final screenScale = 2 * math.tan(fovY / 2);
    for (final m in _mtoonMaterials) {
      m.updateFrame(mtoonLighting, _time, screenScale: screenScale);
    }
    humanoid.apply();
    lookAt.update();
    humanoid.apply();
    constraints.update();
    springBones.update(deltaSeconds);
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
