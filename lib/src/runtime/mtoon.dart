import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'material_handles.dart';

/// The light MToon materials shade with.
///
/// flutter_scene does not yet let custom unlit materials read the scene's
/// lights, so MToon takes them from here. [VrmAvatar.update] writes these
/// values into the avatar's MToon materials every frame; use [fromScene] to
/// follow the scene's directional light.
class VrmMToonLighting {
  /// Direction *toward* the light, in world space.
  Vector3 direction = Vector3(0.3, 0.8, 0.5)..normalize();

  /// Linear light color, intensity included (1 is a plain white light).
  Vector3 color = Vector3.all(1);

  /// Ambient light from above and below (MToon's global illumination).
  Vector3 skyColor = Vector3(0.35, 0.35, 0.38);
  Vector3 groundColor = Vector3(0.2, 0.19, 0.18);

  /// Copies [scene]'s directional light. flutter_scene's default intensity
  /// (3) maps to MToon's 1; [intensityScale] changes that.
  void fromScene(Scene scene, {double intensityScale = 1 / 3}) {
    final light = scene.directionalLight;
    if (light == null) return;
    direction = -light.direction.normalized();
    color = light.color.xyz * (light.intensity * intensityScale);
  }
}

/// One glTF material rendered with flutter_vrm's MToon `.fmat`.
class VrmMToonMaterialHandle implements VrmMaterialHandle {
  VrmMToonMaterialHandle._(this.material);

  final PreprocessedMaterial material;

  final Map<String, Vector4> _colors = {};
  Vector2 _uvOffset = Vector2.zero();
  Vector2 _uvScale = Vector2(1, 1);

  static const Map<String, String> _colorParams = {
    'color': 'base_color_factor',
    'emissionColor': 'emissive_factor',
    'shadeColor': 'shade_color_factor',
    'matcapColor': 'matcap_factor',
    'rimColor': 'parametric_rim_color_factor',
  };

  @override
  Vector4? readColor(String type) => _colors[type]?.clone();

  @override
  void writeColor(String type, Vector4 value) {
    final param = _colorParams[type];
    if (param == null || !_colors.containsKey(type)) return;
    _colors[type] = value.clone();
    if (type == 'color') {
      material.parameters.setVec4(param, value);
    } else {
      material.parameters.setVec3(param, value.xyz);
    }
  }

  @override
  (Vector2, Vector2)? readUvTransform() =>
      (_uvOffset.clone(), _uvScale.clone());

  @override
  void writeUvTransform(Vector2 offset, Vector2 scale) {
    _uvOffset = offset.clone();
    _uvScale = scale.clone();
    material.parameters
      ..setVec2('uv_offset', offset)
      ..setVec2('uv_scale', scale);
  }

  /// Writes the per-frame inputs.
  void updateFrame(VrmMToonLighting lighting, double time) {
    material.parameters
      ..setVec3('light_direction', lighting.direction)
      ..setVec3('light_color', lighting.color)
      ..setVec3('gi_sky_color', lighting.skyColor)
      ..setVec3('gi_ground_color', lighting.groundColor)
      ..setFloat('time', time);
  }
}

/// Builds MToon materials for the glTF materials that carry
/// `VRMC_materials_mtoon`, reusing textures the importer already uploaded
/// where it can and decoding the MToon-only ones from the file.
class VrmMToonFactory {
  VrmMToonFactory(this.gltf, this.binary);

  final Map<String, dynamic> gltf;
  final Uint8List? binary;
  final Map<int, Future<Texture2D?>> _images = {};

  /// Returns a handle for glTF material [index], or null when it is not an
  /// MToon material. [imported] is what the importer made for it (its
  /// textures are reused).
  Future<VrmMToonMaterialHandle?> create(int index, Material? imported) async {
    final materials = (gltf['materials'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (index < 0 || index >= materials.length) return null;
    final m = materials[index];
    final ext = (m['extensions'] as Map<String, dynamic>? ?? const {});
    final mtoon = ext['VRMC_materials_mtoon'] as Map<String, dynamic>?;
    if (mtoon == null) return null;

    final alphaMode = m['alphaMode'] as String? ?? 'OPAQUE';
    final doubleSided = m['doubleSided'] as bool? ?? false;
    final zWrite = mtoon['transparentWithZWrite'] as bool? ?? false;
    final stem = StringBuffer('mtoon_')
      ..write(
        alphaMode == 'BLEND' ? (zWrite ? 'blend_zwrite' : 'blend') : 'opaque',
      )
      ..write(doubleSided ? '_double' : '');
    final material = await loadFmatMaterial(
      'assets/materials/$stem.fmat',
      package: 'flutter_vrm',
    );
    final handle = VrmMToonMaterialHandle._(material);
    final p = material.parameters;

    final pbr = m['pbrMetallicRoughness'] as Map<String, dynamic>? ?? const {};
    final baseColor = _vec4(pbr['baseColorFactor'], [1, 1, 1, 1]);
    p
      ..setVec4('base_color_factor', baseColor)
      ..setInt('alpha_mode', switch (alphaMode) {
        'MASK' => 1,
        'BLEND' => 2,
        _ => 0,
      })
      ..setFloat('alpha_cutoff', _num(m['alphaCutoff'], 0.5));
    handle._colors['color'] = baseColor;

    final emissiveStrength = _num(
      (ext['KHR_materials_emissive_strength']
          as Map<String, dynamic>?)?['emissiveStrength'],
      1,
    );
    final emissive = _vec3(m['emissiveFactor'], [0, 0, 0]) * emissiveStrength;
    p.setVec3('emissive_factor', emissive);
    handle._colors['emissionColor'] = Vector4(
      emissive.x,
      emissive.y,
      emissive.z,
      1,
    );

    final shade = _vec3(mtoon['shadeColorFactor'], [0, 0, 0]);
    final matcap = _vec3(mtoon['matcapFactor'], [1, 1, 1]);
    final rim = _vec3(mtoon['parametricRimColorFactor'], [0, 0, 0]);
    p
      ..setVec3('shade_color_factor', shade)
      ..setFloat('shading_shift_factor', _num(mtoon['shadingShiftFactor'], 0))
      ..setFloat('shading_toony_factor', _num(mtoon['shadingToonyFactor'], 0.9))
      ..setFloat(
        'gi_equalization_factor',
        _num(mtoon['giEqualizationFactor'], 0.9),
      )
      ..setVec3('matcap_factor', matcap)
      ..setVec3('parametric_rim_color_factor', rim)
      ..setFloat(
        'parametric_rim_fresnel_power_factor',
        _num(mtoon['parametricRimFresnelPowerFactor'], 5),
      )
      ..setFloat(
        'parametric_rim_lift_factor',
        _num(mtoon['parametricRimLiftFactor'], 0),
      )
      ..setFloat(
        'rim_lighting_mix_factor',
        _num(mtoon['rimLightingMixFactor'], 1),
      )
      ..setFloat(
        'uv_animation_scroll_x_speed_factor',
        _num(mtoon['uvAnimationScrollXSpeedFactor'], 0),
      )
      ..setFloat(
        'uv_animation_scroll_y_speed_factor',
        _num(mtoon['uvAnimationScrollYSpeedFactor'], 0),
      )
      ..setFloat(
        'uv_animation_rotation_speed_factor',
        _num(mtoon['uvAnimationRotationSpeedFactor'], 0),
      );
    handle._colors['shadeColor'] = Vector4(shade.x, shade.y, shade.z, 1);
    handle._colors['matcapColor'] = Vector4(matcap.x, matcap.y, matcap.z, 1);
    handle._colors['rimColor'] = Vector4(rim.x, rim.y, rim.z, 1);

    // The base color texture's KHR_texture_transform is the UV transform the
    // whole material uses (as VRM expressions assume).
    final baseInfo = pbr['baseColorTexture'] as Map<String, dynamic>?;
    final transform =
        (baseInfo?['extensions']
                as Map<String, dynamic>?)?['KHR_texture_transform']
            as Map<String, dynamic>?;
    handle.writeUvTransform(
      _vec2(transform?['offset'], [0, 0]),
      _vec2(transform?['scale'], [1, 1]),
    );

    // Textures. The base color and emissive ones come from the importer.
    Future<void> bind(
      String param,
      Map<String, dynamic>? info, {
      TextureSource? reuse,
    }) async {
      if (info == null) return;
      final texIndex = info['index'] as int?;
      if (texIndex == null) return;
      final gpuTexture =
          reuse?.sampledTexture ?? (await _texture(texIndex))?.sampledTexture;
      if (gpuTexture == null) return;
      p.setTexture(param, gpuTexture, sampler: _sampler(texIndex));
    }

    final pbrImported = imported is PhysicallyBasedMaterial ? imported : null;
    final unlitImported = imported is UnlitMaterial ? imported : null;
    await Future.wait([
      bind(
        'base_color_texture',
        baseInfo,
        reuse: pbrImported?.baseColorTexture ?? unlitImported?.baseColorTexture,
      ),
      bind(
        'emissive_texture',
        m['emissiveTexture'] as Map<String, dynamic>?,
        reuse: pbrImported?.emissiveTexture,
      ),
      bind(
        'shade_multiply_texture',
        mtoon['shadeMultiplyTexture'] as Map<String, dynamic>?,
      ),
      bind(
        'shading_shift_texture',
        mtoon['shadingShiftTexture'] as Map<String, dynamic>?,
      ),
      bind('matcap_texture', mtoon['matcapTexture'] as Map<String, dynamic>?),
      bind(
        'rim_multiply_texture',
        mtoon['rimMultiplyTexture'] as Map<String, dynamic>?,
      ),
      bind(
        'uv_animation_mask_texture',
        mtoon['uvAnimationMaskTexture'] as Map<String, dynamic>?,
      ),
    ]);
    // Missing textures must contribute nothing. Do not rely on the shader's
    // `default_black` placeholder: on iOS it samples white (seen with
    // flutter_scene b02c999), which adds a full-strength matcap everywhere.
    final shiftInfo = mtoon['shadingShiftTexture'] as Map<String, dynamic>?;
    p.setFloat(
      'shading_shift_texture_scale',
      shiftInfo == null ? 0 : _num(shiftInfo['scale'], 1),
    );
    if (mtoon['matcapTexture'] == null) {
      p.setVec3('matcap_factor', Vector3.zero());
      handle._colors['matcapColor'] = Vector4(0, 0, 0, 1);
    }
    return handle;
  }

  Future<Texture2D?> _texture(int textureIndex) {
    final textures = (gltf['textures'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (textureIndex < 0 || textureIndex >= textures.length) {
      return Future.value(null);
    }
    final image = textures[textureIndex]['source'] as int?;
    if (image == null) return Future.value(null);
    return _images.putIfAbsent(image, () => _decodeImage(image));
  }

  Future<Texture2D?> _decodeImage(int imageIndex) async {
    final images = (gltf['images'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (imageIndex >= images.length) return null;
    final image = images[imageIndex];
    Uint8List? bytes;
    final viewIndex = image['bufferView'] as int?;
    if (viewIndex != null && binary != null) {
      final view =
          (gltf['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
      final offset = view['byteOffset'] as int? ?? 0;
      bytes = Uint8List.sublistView(
        binary!,
        offset,
        offset + (view['byteLength'] as int),
      );
    } else {
      final uri = image['uri'] as String?;
      if (uri != null && uri.startsWith('data:')) {
        bytes = base64Decode(uri.substring(uri.indexOf(',') + 1));
      }
    }
    if (bytes == null) {
      debugPrint(
        'flutter_vrm: MToon image $imageIndex is not embedded; skipped',
      );
      return null;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    try {
      return await Texture2D.fromImage(frame.image);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  }

  /// The glTF sampler of [textureIndex] as Flutter GPU sampler options, so
  /// CLAMP_TO_EDGE and MIRRORED_REPEAT are honored.
  gpu.SamplerOptions _sampler(int textureIndex) {
    final textures = (gltf['textures'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final samplerIndex = textureIndex < textures.length
        ? textures[textureIndex]['sampler'] as int?
        : null;
    final samplers = (gltf['samplers'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final s = samplerIndex != null && samplerIndex < samplers.length
        ? samplers[samplerIndex]
        : const <String, dynamic>{};
    gpu.SamplerAddressMode wrap(int? mode) => switch (mode) {
      33071 => gpu.SamplerAddressMode.clampToEdge,
      33648 => gpu.SamplerAddressMode.mirror,
      _ => gpu.SamplerAddressMode.repeat,
    };
    final mag = s['magFilter'] as int?;
    final min = s['minFilter'] as int?;
    final nearestMag = mag == 9728;
    final nearestMin = min == 9728 || min == 9984 || min == 9986;
    final mipNearest = min == 9984 || min == 9985;
    return gpu.SamplerOptions(
      minFilter: nearestMin
          ? gpu.MinMagFilter.nearest
          : gpu.MinMagFilter.linear,
      magFilter: nearestMag
          ? gpu.MinMagFilter.nearest
          : gpu.MinMagFilter.linear,
      mipFilter: mipNearest ? gpu.MipFilter.nearest : gpu.MipFilter.linear,
      widthAddressMode: wrap(s['wrapS'] as int?),
      heightAddressMode: wrap(s['wrapT'] as int?),
    );
  }

  static double _num(Object? v, double d) => (v as num?)?.toDouble() ?? d;

  static Vector2 _vec2(Object? v, List<double> d) {
    final l = (v as List?)?.cast<num>();
    return Vector2(
      l != null && l.isNotEmpty ? l[0].toDouble() : d[0],
      l != null && l.length > 1 ? l[1].toDouble() : d[1],
    );
  }

  static Vector3 _vec3(Object? v, List<double> d) {
    final l = (v as List?)?.cast<num>();
    double at(int i) => l != null && l.length > i ? l[i].toDouble() : d[i];
    return Vector3(at(0), at(1), at(2));
  }

  static Vector4 _vec4(Object? v, List<double> d) {
    final l = (v as List?)?.cast<num>();
    double at(int i) => l != null && l.length > i ? l[i].toDouble() : d[i];
    return Vector4(at(0), at(1), at(2), at(3));
  }
}
