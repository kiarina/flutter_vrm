import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// What expressions need from a material: read and write the colors and UV
/// transform VRM's material binds address, whatever material type the
/// model ended up with.
abstract class VrmMaterialHandle {
  /// The current value of a `materialColorBinds` type (`color`,
  /// `emissionColor`, `shadeColor`, `matcapColor`, `rimColor`,
  /// `outlineColor`), or null when this material has no such color.
  Vector4? readColor(String type);

  void writeColor(String type, Vector4 value);

  /// The UV offset and scale, or null when unsupported.
  (Vector2, Vector2)? readUvTransform();

  void writeUvTransform(Vector2 offset, Vector2 scale);
}

/// flutter_scene's own [PhysicallyBasedMaterial] or [UnlitMaterial].
class VrmStandardMaterialHandle implements VrmMaterialHandle {
  VrmStandardMaterialHandle(this.material);

  final Material material;

  @override
  Vector4? readColor(String type) {
    final m = material;
    switch (type) {
      case 'color':
        if (m is PhysicallyBasedMaterial) return m.baseColorFactor.clone();
        if (m is UnlitMaterial) return m.baseColorFactor.clone();
      case 'emissionColor':
        if (m is PhysicallyBasedMaterial) return m.emissiveFactor.clone();
    }
    return null;
  }

  @override
  void writeColor(String type, Vector4 value) {
    final m = material;
    switch (type) {
      case 'color':
        if (m is PhysicallyBasedMaterial) m.baseColorFactor = value;
        if (m is UnlitMaterial) m.baseColorFactor = value;
      case 'emissionColor':
        if (m is PhysicallyBasedMaterial) m.emissiveFactor = value;
    }
  }

  @override
  (Vector2, Vector2)? readUvTransform() {
    final m = material;
    final TextureTransform t;
    if (m is PhysicallyBasedMaterial) {
      t = m.baseColorTextureTransform;
    } else if (m is UnlitMaterial) {
      t = m.baseColorTextureTransform;
    } else {
      return null;
    }
    return (t.offset.clone(), t.scale.clone());
  }

  @override
  void writeUvTransform(Vector2 offset, Vector2 scale) {
    final m = material;
    if (m is PhysicallyBasedMaterial) {
      final rotation = m.baseColorTextureTransform.rotation;
      TextureTransform t() =>
          TextureTransform(offset: offset, scale: scale, rotation: rotation);
      // VRM moves every texture of the material together.
      m.baseColorTextureTransform = t();
      m.emissiveTextureTransform = t();
      m.normalTextureTransform = t();
      m.metallicRoughnessTextureTransform = t();
      m.occlusionTextureTransform = t();
    } else if (m is UnlitMaterial) {
      m.baseColorTextureTransform = TextureTransform(
        offset: offset,
        scale: scale,
        rotation: m.baseColorTextureTransform.rotation,
      );
    }
  }
}
