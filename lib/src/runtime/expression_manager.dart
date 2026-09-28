import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../schema/vrm_document.dart';
import 'material_handles.dart';

/// Holds expression values and writes them to morph targets, material
/// colors, and texture transforms following the VRM 1.0 rules:
///
/// * `isBinary` expressions snap to 0 or 1 at 0.5
/// * an expression with `overrideBlink` / `overrideLookAt` / `overrideMouth`
///   set to `block` silences that group while its weight is above 0, and
///   `blend` scales the group by `1 - weight`
/// * binds of all active expressions are summed
class VrmExpressionManager {
  VrmExpressionManager(this.definitions, this._gltfNodes, this._materials) {
    for (final def in definitions.values) {
      for (final b in def.morphTargetBinds) {
        _boundMorphs.add((b.node, b.index));
      }
      for (final b in def.materialColorBinds) {
        for (final h in _materials[b.material] ?? const <VrmMaterialHandle>[]) {
          final base = h.readColor(b.type);
          if (base == null) {
            _warnOnce(
              'color ${b.type} ${h.runtimeType}',
              'materialColorBind "${b.type}" is not supported on '
                  '${h.runtimeType}',
            );
            continue;
          }
          _baseColors.putIfAbsent((h, b.type), () => base);
        }
      }
      for (final b in def.textureTransformBinds) {
        for (final h in _materials[b.material] ?? const <VrmMaterialHandle>[]) {
          final base = h.readUvTransform();
          if (base != null) _baseTransforms.putIfAbsent(h, () => base);
        }
      }
    }
  }

  /// Every expression the model defines, keyed by name.
  final Map<String, VrmExpressionDefinition> definitions;
  final List<Node?> _gltfNodes;
  final Map<int, List<VrmMaterialHandle>> _materials;

  final Map<String, double> _values = {};
  final Set<(int, int)> _boundMorphs = {};
  final Map<(VrmMaterialHandle, String), Vector4> _baseColors = {};
  final Map<VrmMaterialHandle, (Vector2, Vector2)> _baseTransforms = {};
  final Set<String> _warned = {};

  /// Sets expression [name] to [value] (clamped to 0..1). Unknown names are
  /// ignored, so presets a model lacks are harmless.
  void setValue(String name, double value) {
    if (!definitions.containsKey(name)) return;
    _values[name] = value.clamp(0.0, 1.0);
  }

  /// Sets a preset expression.
  void setPreset(VrmExpressionPreset preset, double value) =>
      setValue(preset.name, value);

  /// The value last set for [name] (0 when never set).
  double value(String name) => _values[name] ?? 0;

  /// Sets every expression back to 0.
  void resetValues() => _values.clear();

  /// The weight each expression actually applies after `isBinary` and the
  /// override rules.
  Map<String, double> effectiveWeights() {
    double binary(VrmExpressionDefinition d, double v) =>
        d.isBinary ? (v > 0.5 ? 1.0 : 0.0) : v;

    var blink = 1.0, lookAt = 1.0, mouth = 1.0;
    for (final e in _values.entries) {
      final d = definitions[e.key]!;
      final w = binary(d, e.value);
      if (w <= 0) continue;
      double apply(double factor, VrmExpressionOverride o) => switch (o) {
        VrmExpressionOverride.block => 0.0,
        VrmExpressionOverride.blend => factor * (1 - w),
        VrmExpressionOverride.none => factor,
      };
      blink = apply(blink, d.overrideBlink);
      lookAt = apply(lookAt, d.overrideLookAt);
      mouth = apply(mouth, d.overrideMouth);
    }

    final out = <String, double>{};
    for (final e in _values.entries) {
      final d = definitions[e.key]!;
      var w = binary(d, e.value);
      final p = d.preset;
      if (p != null) {
        if (VrmExpressionPreset.blinkGroup.contains(p)) w *= blink;
        if (VrmExpressionPreset.lookAtGroup.contains(p)) w *= lookAt;
        if (VrmExpressionPreset.mouthGroup.contains(p)) w *= mouth;
      }
      if (w > 0) out[e.key] = w;
    }
    return out;
  }

  /// Writes the current values into the imported model.
  void apply() {
    final weights = effectiveWeights();

    // Every bound target is rewritten each frame, so released expressions
    // return to their base values.
    final morph = <(int, int), double>{for (final k in _boundMorphs) k: 0.0};
    final colors = <(VrmMaterialHandle, String), Vector4>{};
    final offsets = <VrmMaterialHandle, Vector2>{};
    final scales = <VrmMaterialHandle, Vector2>{};

    for (final e in weights.entries) {
      final d = definitions[e.key]!;
      final w = e.value;
      for (final b in d.morphTargetBinds) {
        final k = (b.node, b.index);
        morph[k] = morph[k]! + b.weight * w;
      }
      for (final b in d.materialColorBinds) {
        for (final h in _materials[b.material] ?? const <VrmMaterialHandle>[]) {
          final k = (h, b.type);
          final base = _baseColors[k];
          if (base == null) continue;
          colors[k] = (colors[k] ?? base.clone()) + (b.targetValue - base) * w;
        }
      }
      for (final b in d.textureTransformBinds) {
        for (final h in _materials[b.material] ?? const <VrmMaterialHandle>[]) {
          offsets[h] = (offsets[h] ?? Vector2.zero()) + b.offset * w;
          scales[h] =
              (scales[h] ?? Vector2.zero()) + (b.scale - Vector2(1, 1)) * w;
        }
      }
    }

    for (final e in morph.entries) {
      final node = _gltfNodes.length > e.key.$1 ? _gltfNodes[e.key.$1] : null;
      if (node == null) continue;
      final weights = node.morphWeights;
      if (weights == null || e.key.$2 >= weights.length) {
        _warnOnce(
          'morph ${e.key}',
          'node ${e.key.$1} has no morph target ${e.key.$2}',
        );
        continue;
      }
      node.setMorphWeight(e.key.$2, e.value);
    }

    for (final e in _baseColors.entries) {
      e.key.$1.writeColor(e.key.$2, colors[e.key] ?? e.value);
    }

    for (final e in _baseTransforms.entries) {
      final (offset, scale) = e.value;
      e.key.writeUvTransform(
        offset + (offsets[e.key] ?? Vector2.zero()),
        scale + (scales[e.key] ?? Vector2.zero()),
      );
    }
  }

  void _warnOnce(String key, String message) {
    if (_warned.add(key)) debugPrint('flutter_vrm: $message');
  }
}
