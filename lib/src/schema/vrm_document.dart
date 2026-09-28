import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'glb.dart';
import 'node_constraint.dart';
import 'spring_bone.dart';

export 'node_constraint.dart';
export 'spring_bone.dart';

/// VRM 1.0 humanoid bones. Enum names match the `humanBones` keys.
enum VrmHumanBone {
  hips,
  spine,
  chest,
  upperChest,
  neck,
  head,
  leftEye,
  rightEye,
  jaw,
  leftUpperLeg,
  leftLowerLeg,
  leftFoot,
  leftToes,
  rightUpperLeg,
  rightLowerLeg,
  rightFoot,
  rightToes,
  leftShoulder,
  leftUpperArm,
  leftLowerArm,
  leftHand,
  rightShoulder,
  rightUpperArm,
  rightLowerArm,
  rightHand,
  leftThumbMetacarpal,
  leftThumbProximal,
  leftThumbDistal,
  leftIndexProximal,
  leftIndexIntermediate,
  leftIndexDistal,
  leftMiddleProximal,
  leftMiddleIntermediate,
  leftMiddleDistal,
  leftRingProximal,
  leftRingIntermediate,
  leftRingDistal,
  leftLittleProximal,
  leftLittleIntermediate,
  leftLittleDistal,
  rightThumbMetacarpal,
  rightThumbProximal,
  rightThumbDistal,
  rightIndexProximal,
  rightIndexIntermediate,
  rightIndexDistal,
  rightMiddleProximal,
  rightMiddleIntermediate,
  rightMiddleDistal,
  rightRingProximal,
  rightRingIntermediate,
  rightRingDistal,
  rightLittleProximal,
  rightLittleIntermediate,
  rightLittleDistal;

  /// The bones VRM 1.0 requires every humanoid to map.
  static const Set<VrmHumanBone> required = {
    hips,
    spine,
    head,
    leftUpperLeg,
    leftLowerLeg,
    leftFoot,
    rightUpperLeg,
    rightLowerLeg,
    rightFoot,
    leftUpperArm,
    leftLowerArm,
    leftHand,
    rightUpperArm,
    rightLowerArm,
    rightHand,
  };

  static VrmHumanBone? byName(String name) {
    for (final b in values) {
      if (b.name == name) return b;
    }
    return null;
  }
}

/// VRM 1.0 preset expression names.
enum VrmExpressionPreset {
  happy,
  angry,
  sad,
  relaxed,
  surprised,
  aa,
  ih,
  ou,
  ee,
  oh,
  blink,
  blinkLeft,
  blinkRight,
  lookUp,
  lookDown,
  lookLeft,
  lookRight,
  neutral;

  static const Set<VrmExpressionPreset> blinkGroup = {
    blink,
    blinkLeft,
    blinkRight,
  };
  static const Set<VrmExpressionPreset> lookAtGroup = {
    lookUp,
    lookDown,
    lookLeft,
    lookRight,
  };
  static const Set<VrmExpressionPreset> mouthGroup = {aa, ih, ou, ee, oh};
}

/// How an expression suppresses the blink / lookAt / mouth expressions.
enum VrmExpressionOverride { none, block, blend }

/// `meta` of `VRMC_vrm`: who made the avatar and what it may be used for.
class VrmMeta {
  VrmMeta._(this.json);

  /// The raw `meta` object, for fields not surfaced here.
  final Map<String, dynamic> json;

  String get name => json['name'] as String? ?? '';
  String? get version => json['version'] as String?;
  List<String> get authors =>
      (json['authors'] as List? ?? const []).cast<String>();
  String? get copyrightInformation => json['copyrightInformation'] as String?;
  String? get contactInformation => json['contactInformation'] as String?;
  List<String> get references =>
      (json['references'] as List? ?? const []).cast<String>();
  String? get thirdPartyLicenses => json['thirdPartyLicenses'] as String?;

  /// glTF image index of the thumbnail.
  int? get thumbnailImage => json['thumbnailImage'] as int?;
  String get licenseUrl => json['licenseUrl'] as String? ?? '';
  String get avatarPermission =>
      json['avatarPermission'] as String? ?? 'onlyAuthor';
  bool get allowExcessivelyViolentUsage =>
      json['allowExcessivelyViolentUsage'] as bool? ?? false;
  bool get allowExcessivelySexualUsage =>
      json['allowExcessivelySexualUsage'] as bool? ?? false;
  String get commercialUsage =>
      json['commercialUsage'] as String? ?? 'personalNonProfit';
  bool get allowPoliticalOrReligiousUsage =>
      json['allowPoliticalOrReligiousUsage'] as bool? ?? false;
  bool get allowAntisocialOrHateUsage =>
      json['allowAntisocialOrHateUsage'] as bool? ?? false;
  String get creditNotation => json['creditNotation'] as String? ?? 'required';
  bool get allowRedistribution => json['allowRedistribution'] as bool? ?? false;
  String get modification => json['modification'] as String? ?? 'prohibited';
  String? get otherLicenseUrl => json['otherLicenseUrl'] as String?;
}

/// A morph target weight driven by an expression.
class VrmMorphTargetBind {
  const VrmMorphTargetBind(this.node, this.index, this.weight);

  /// glTF node index (the node carrying the mesh).
  final int node;

  /// Morph target index within that mesh.
  final int index;

  /// Weight at expression value 1.
  final double weight;
}

/// A material color driven by an expression.
class VrmMaterialColorBind {
  const VrmMaterialColorBind(this.material, this.type, this.targetValue);

  /// glTF material index.
  final int material;

  /// `color`, `emissionColor`, `shadeColor`, `matcapColor`, `rimColor` or
  /// `outlineColor`.
  final String type;

  /// RGBA at expression value 1 (emission and shade use RGB).
  final Vector4 targetValue;
}

/// A texture UV offset / scale driven by an expression.
class VrmTextureTransformBind {
  const VrmTextureTransformBind(this.material, this.offset, this.scale);

  final int material;
  final Vector2 offset;
  final Vector2 scale;
}

/// One expression (preset or custom) of `VRMC_vrm.expressions`.
class VrmExpressionDefinition {
  VrmExpressionDefinition({
    required this.name,
    required this.preset,
    required this.isBinary,
    required this.overrideBlink,
    required this.overrideLookAt,
    required this.overrideMouth,
    required this.morphTargetBinds,
    required this.materialColorBinds,
    required this.textureTransformBinds,
  });

  final String name;

  /// The preset this expression implements, or null for a custom one.
  final VrmExpressionPreset? preset;
  final bool isBinary;
  final VrmExpressionOverride overrideBlink;
  final VrmExpressionOverride overrideLookAt;
  final VrmExpressionOverride overrideMouth;
  final List<VrmMorphTargetBind> morphTargetBinds;
  final List<VrmMaterialColorBind> materialColorBinds;
  final List<VrmTextureTransformBind> textureTransformBinds;

  static VrmExpressionDefinition _parse(
    String name,
    VrmExpressionPreset? preset,
    Map<String, dynamic> j,
  ) {
    VrmExpressionOverride ov(String key) {
      final v = j[key] as String?;
      return VrmExpressionOverride.values.firstWhere(
        (o) => o.name == v,
        orElse: () => VrmExpressionOverride.none,
      );
    }

    List<Map<String, dynamic>> list(String key) =>
        (j[key] as List? ?? const []).cast<Map<String, dynamic>>();

    Vector2 v2(Object? o, double d) {
      final l = (o as List?)?.cast<num>();
      return l == null || l.length < 2
          ? Vector2(d, d)
          : Vector2(l[0].toDouble(), l[1].toDouble());
    }

    Vector4 v4(Object? o) {
      final l = (o as List?)?.cast<num>() ?? const [0, 0, 0, 1];
      return Vector4(
        l[0].toDouble(),
        l.length > 1 ? l[1].toDouble() : 0,
        l.length > 2 ? l[2].toDouble() : 0,
        l.length > 3 ? l[3].toDouble() : 1,
      );
    }

    return VrmExpressionDefinition(
      name: name,
      preset: preset,
      isBinary: j['isBinary'] as bool? ?? false,
      overrideBlink: ov('overrideBlink'),
      overrideLookAt: ov('overrideLookAt'),
      overrideMouth: ov('overrideMouth'),
      morphTargetBinds: [
        for (final b in list('morphTargetBinds'))
          VrmMorphTargetBind(
            b['node'] as int,
            b['index'] as int,
            (b['weight'] as num? ?? 1).toDouble(),
          ),
      ],
      materialColorBinds: [
        for (final b in list('materialColorBinds'))
          VrmMaterialColorBind(
            b['material'] as int,
            b['type'] as String,
            v4(b['targetValue']),
          ),
      ],
      textureTransformBinds: [
        for (final b in list('textureTransformBinds'))
          VrmTextureTransformBind(
            b['material'] as int,
            v2(b['offset'], 0),
            v2(b['scale'], 1),
          ),
      ],
    );
  }
}

/// A look-at range map: input angle (degrees) to output angle or weight.
class VrmLookAtRangeMap {
  const VrmLookAtRangeMap(this.inputMaxValue, this.outputScale);

  final double inputMaxValue;
  final double outputScale;

  /// Maps a non-negative input angle in degrees.
  double map(double degrees) {
    if (inputMaxValue <= 0) return 0;
    final x = degrees < 0
        ? 0.0
        : (degrees > inputMaxValue ? inputMaxValue : degrees);
    return x / inputMaxValue * outputScale;
  }

  static VrmLookAtRangeMap _parse(Object? o, double defaultScale) {
    final j = o as Map<String, dynamic>? ?? const {};
    return VrmLookAtRangeMap(
      (j['inputMaxValue'] as num? ?? 90).toDouble(),
      (j['outputScale'] as num? ?? defaultScale).toDouble(),
    );
  }
}

/// `VRMC_vrm.lookAt`.
class VrmLookAtDefinition {
  const VrmLookAtDefinition({
    required this.type,
    required this.offsetFromHeadBone,
    required this.rangeMapHorizontalInner,
    required this.rangeMapHorizontalOuter,
    required this.rangeMapVerticalDown,
    required this.rangeMapVerticalUp,
  });

  /// `bone` (rotate the eye bones) or `expression` (drive lookUp/Down/...).
  final String type;

  /// The eye position relative to the head bone, in model space.
  final Vector3 offsetFromHeadBone;
  final VrmLookAtRangeMap rangeMapHorizontalInner;
  final VrmLookAtRangeMap rangeMapHorizontalOuter;
  final VrmLookAtRangeMap rangeMapVerticalDown;
  final VrmLookAtRangeMap rangeMapVerticalUp;

  static VrmLookAtDefinition? _parse(Map<String, dynamic>? j) {
    if (j == null) return null;
    final type = j['type'] as String? ?? 'bone';
    final scale = type == 'expression' ? 1.0 : 10.0;
    final off = (j['offsetFromHeadBone'] as List?)?.cast<num>();
    return VrmLookAtDefinition(
      type: type,
      offsetFromHeadBone: off == null
          ? Vector3.zero()
          : Vector3(off[0].toDouble(), off[1].toDouble(), off[2].toDouble()),
      rangeMapHorizontalInner: VrmLookAtRangeMap._parse(
        j['rangeMapHorizontalInner'],
        scale,
      ),
      rangeMapHorizontalOuter: VrmLookAtRangeMap._parse(
        j['rangeMapHorizontalOuter'],
        scale,
      ),
      rangeMapVerticalDown: VrmLookAtRangeMap._parse(
        j['rangeMapVerticalDown'],
        scale,
      ),
      rangeMapVerticalUp: VrmLookAtRangeMap._parse(
        j['rangeMapVerticalUp'],
        scale,
      ),
    );
  }
}

/// The VRM 1.0 content of a `.vrm` file, independent of any renderer.
///
/// flutter_scene imports the file as plain glTF and ignores the `VRMC_*`
/// extensions; this class reads them from the same bytes.
class VrmDocument {
  VrmDocument._({
    required this.gltf,
    required this.specVersion,
    required this.meta,
    required this.humanBones,
    required this.expressions,
    required this.lookAt,
    required this.springBone,
    required this.nodeConstraints,
  });

  /// The whole glTF JSON (for extensions this class does not model yet).
  final Map<String, dynamic> gltf;
  final String specVersion;
  final VrmMeta meta;

  /// Humanoid bone -> glTF node index.
  final Map<VrmHumanBone, int> humanBones;

  /// Every expression, keyed by name (preset names for presets).
  final Map<String, VrmExpressionDefinition> expressions;
  final VrmLookAtDefinition? lookAt;

  /// `VRMC_springBone`, or null when the model has no spring bones.
  final VrmSpringBoneDefinition? springBone;

  /// `VRMC_node_constraint` of every node that has one.
  final List<VrmNodeConstraint> nodeConstraints;

  /// The raw `extensions` object of glTF material [index], if any.
  Map<String, dynamic>? materialExtensions(int index) {
    final materials = gltf['materials'] as List?;
    if (materials == null || index < 0 || index >= materials.length) {
      return null;
    }
    return (materials[index] as Map<String, dynamic>)['extensions']
        as Map<String, dynamic>?;
  }

  /// Parses the VRM content of a `.vrm` (GLB) file.
  static VrmDocument fromGlb(Uint8List bytes) =>
      fromGltfJson(GlbContainer.parse(bytes).json);

  /// Parses the VRM content from an already decoded glTF JSON object.
  ///
  /// Throws a [FormatException] for a file without `VRMC_vrm` (for example
  /// a VRM 0.x file, which uses the `VRM` extension instead).
  static VrmDocument fromGltfJson(Map<String, dynamic> gltf) {
    final ext = gltf['extensions'] as Map<String, dynamic>? ?? const {};
    final vrm = ext['VRMC_vrm'] as Map<String, dynamic>?;
    if (vrm == null) {
      if (ext.containsKey('VRM')) {
        throw const FormatException(
          'VRM 0.x is not supported (found the VRM extension, not VRMC_vrm)',
        );
      }
      throw const FormatException('not a VRM 1.0 file (no VRMC_vrm)');
    }
    final nodeCount = (gltf['nodes'] as List? ?? const []).length;

    final bones = <VrmHumanBone, int>{};
    final humanBones =
        (vrm['humanoid'] as Map<String, dynamic>?)?['humanBones']
            as Map<String, dynamic>? ??
        const {};
    for (final e in humanBones.entries) {
      final bone = VrmHumanBone.byName(e.key);
      final node = (e.value as Map<String, dynamic>)['node'] as int?;
      if (bone == null || node == null) continue;
      if (node < 0 || node >= nodeCount) {
        throw FormatException(
          'humanBone ${e.key} points at missing node $node',
        );
      }
      bones[bone] = node;
    }
    final missing = VrmHumanBone.required.difference(bones.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        'humanoid lacks required bones: ${missing.map((b) => b.name).join(', ')}',
      );
    }

    final expressions = <String, VrmExpressionDefinition>{};
    final exprJson = vrm['expressions'] as Map<String, dynamic>? ?? const {};
    final presets = exprJson['preset'] as Map<String, dynamic>? ?? const {};
    for (final e in presets.entries) {
      final preset = VrmExpressionPreset.values
          .where((p) => p.name == e.key)
          .firstOrNull;
      if (preset == null) continue;
      expressions[e.key] = VrmExpressionDefinition._parse(
        e.key,
        preset,
        e.value as Map<String, dynamic>,
      );
    }
    final customs = exprJson['custom'] as Map<String, dynamic>? ?? const {};
    for (final e in customs.entries) {
      if (expressions.containsKey(e.key)) continue; // presets win
      expressions[e.key] = VrmExpressionDefinition._parse(
        e.key,
        null,
        e.value as Map<String, dynamic>,
      );
    }

    return VrmDocument._(
      gltf: gltf,
      specVersion: vrm['specVersion'] as String? ?? '1.0',
      meta: VrmMeta._(vrm['meta'] as Map<String, dynamic>? ?? const {}),
      humanBones: bones,
      expressions: expressions,
      lookAt: VrmLookAtDefinition._parse(
        vrm['lookAt'] as Map<String, dynamic>?,
      ),
      springBone: VrmSpringBoneDefinition.parse(
        ext['VRMC_springBone'] as Map<String, dynamic>?,
        nodeCount,
      ),
      nodeConstraints: [
        for (final (i, n)
            in (gltf['nodes'] as List? ?? const [])
                .cast<Map<String, dynamic>>()
                .indexed)
          ?VrmNodeConstraint.parse(i, n, nodeCount),
      ],
    );
  }
}
