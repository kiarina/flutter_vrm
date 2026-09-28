import 'dart:typed_data';

/// Reads glTF accessor [index] from the GLB [binary] chunk as floats (one
/// list of `count * components`), mapping normalized integers to 0..1 or
/// -1..1. Returns null for sparse accessors, other buffers, and data outside
/// the chunk.
Float32List? readGltfAccessor(
  Map<String, dynamic> gltf,
  Uint8List? binary,
  int index,
) {
  final accessors = (gltf['accessors'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  if (binary == null || index < 0 || index >= accessors.length) return null;
  final a = accessors[index];
  final viewIndex = a['bufferView'] as int?;
  if (viewIndex == null || a['sparse'] != null) return null;
  final views = (gltf['bufferViews'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  if (viewIndex < 0 || viewIndex >= views.length) return null;
  final view = views[viewIndex];
  if ((view['buffer'] as int? ?? 0) != 0) return null;
  final count = a['count'] as int? ?? 0;
  final components = switch (a['type']) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    _ => 0,
  };
  final type = a['componentType'] as int?;
  final size = switch (type) {
    5126 => 4,
    5123 || 5122 => 2,
    5121 || 5120 => 1,
    _ => 0,
  };
  if (components == 0 || size == 0) return null;
  final normalized = a['normalized'] as bool? ?? false;
  final start =
      (view['byteOffset'] as int? ?? 0) + (a['byteOffset'] as int? ?? 0);
  final stride = view['byteStride'] as int? ?? size * components;
  if (count > 0 &&
      start + stride * (count - 1) + size * components > binary.lengthInBytes) {
    return null;
  }
  final data = ByteData.sublistView(binary);
  final out = Float32List(count * components);
  for (var i = 0; i < count; i++) {
    for (var c = 0; c < components; c++) {
      final o = start + i * stride + c * size;
      out[i * components + c] = switch (type) {
        5126 => data.getFloat32(o, Endian.little),
        5123 => data.getUint16(o, Endian.little) / (normalized ? 65535 : 1),
        5121 => data.getUint8(o) / (normalized ? 255 : 1),
        5122 =>
          normalized
              ? (data.getInt16(o, Endian.little) / 32767).clamp(-1.0, 1.0)
              : data.getInt16(o, Endian.little).toDouble(),
        _ =>
          normalized
              ? (data.getInt8(o) / 127).clamp(-1.0, 1.0)
              : data.getInt8(o).toDouble(),
      };
    }
  }
  return out;
}
