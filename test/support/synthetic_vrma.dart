import 'dart:typed_data';

import 'synthetic_vrm.dart';

/// Builds a `.vrma` GLB: [nodes] (glTF node JSON), the humanoid map
/// [humanBones] (bone name -> node), [expressions] (preset name -> node), and
/// one animation of [channels] (node, path, times, values, interpolation).
Uint8List buildVrma({
  required List<Map<String, dynamic>> nodes,
  required Map<String, int> humanBones,
  Map<String, int> expressions = const {},
  int? lookAt,
  required List<
    ({
      int node,
      String path,
      List<double> times,
      List<double> values,
      String interpolation,
    })
  >
  channels,
}) {
  final bin = BytesBuilder();
  final accessors = <Map<String, dynamic>>[];
  final views = <Map<String, dynamic>>[];
  int addAccessor(List<double> data, String type) {
    final bytes = Float32List.fromList(data).buffer.asUint8List();
    views.add({
      'buffer': 0,
      'byteOffset': bin.length,
      'byteLength': bytes.length,
    });
    bin.add(bytes);
    final components = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[type]!;
    accessors.add({
      'bufferView': views.length - 1,
      'componentType': 5126,
      'count': data.length ~/ components,
      'type': type,
    });
    return accessors.length - 1;
  }

  final samplers = <Map<String, dynamic>>[];
  final gltfChannels = <Map<String, dynamic>>[];
  for (final c in channels) {
    final type = c.path == 'rotation' ? 'VEC4' : 'VEC3';
    samplers.add({
      'input': addAccessor(c.times, 'SCALAR'),
      'output': addAccessor(c.values, type),
      'interpolation': c.interpolation,
    });
    gltfChannels.add({
      'sampler': samplers.length - 1,
      'target': {'node': c.node, 'path': c.path},
    });
  }
  final json = {
    'asset': {'version': '2.0'},
    'nodes': nodes,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': views,
    'accessors': accessors,
    'animations': [
      {'channels': gltfChannels, 'samplers': samplers},
    ],
    'extensionsUsed': ['VRMC_vrm_animation'],
    'extensions': {
      'VRMC_vrm_animation': {
        'specVersion': '1.0',
        'humanoid': {
          'humanBones': {
            for (final e in humanBones.entries) e.key: {'node': e.value},
          },
        },
        'expressions': {
          'preset': {
            for (final e in expressions.entries) e.key: {'node': e.value},
          },
        },
        'lookAt': ?(lookAt == null ? null : {'node': lookAt}),
      },
    },
  };
  return buildGlb(json, bin: bin.toBytes());
}
