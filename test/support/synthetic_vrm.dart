import 'dart:convert';
import 'dart:typed_data';

/// Builds GLB bytes from a glTF JSON object (and an optional BIN chunk).
Uint8List buildGlb(Map<String, dynamic> json, {Uint8List? bin}) {
  var jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPad = (4 - jsonBytes.length % 4) % 4;
  jsonBytes = Uint8List.fromList([...jsonBytes, ...List.filled(jsonPad, 0x20)]);
  final binBytes = bin == null
      ? null
      : Uint8List.fromList([
          ...bin,
          ...List.filled((4 - bin.length % 4) % 4, 0),
        ]);
  final total =
      12 + 8 + jsonBytes.length + (binBytes == null ? 0 : 8 + binBytes.length);
  final out = BytesBuilder()
    ..add(_u32s([0x46546C67, 2, total]))
    ..add(_u32s([jsonBytes.length, 0x4E4F534A]))
    ..add(jsonBytes);
  if (binBytes != null) {
    out
      ..add(_u32s([binBytes.length, 0x004E4942]))
      ..add(binBytes);
  }
  return out.toBytes();
}

Uint8List _u32s(List<int> values) {
  final d = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    d.setUint32(i * 4, values[i], Endian.little);
  }
  return d.buffer.asUint8List();
}

/// The required VRM 1.0 bones plus eyes, as one node each.
const List<String> syntheticBones = [
  'hips',
  'spine',
  'head',
  'leftEye',
  'rightEye',
  'leftUpperLeg',
  'leftLowerLeg',
  'leftFoot',
  'rightUpperLeg',
  'rightLowerLeg',
  'rightFoot',
  'leftUpperArm',
  'leftLowerArm',
  'leftHand',
  'rightUpperArm',
  'rightLowerArm',
  'rightHand',
];

/// A minimal VRM 1.0 glTF JSON: one node per bone in [syntheticBones]
/// (flat under a root node, no meshes), with [vrmOverrides] merged into the
/// `VRMC_vrm` object.
Map<String, dynamic> syntheticVrmJson({
  Map<String, dynamic> vrmOverrides = const {},
  Map<String, dynamic>? humanBones,
}) {
  final nodes = <Map<String, dynamic>>[
    {
      'name': 'Root',
      'children': [for (var i = 0; i < syntheticBones.length; i++) i + 1],
    },
    for (final b in syntheticBones) {'name': 'J_$b'},
  ];
  return {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': nodes,
    'extensionsUsed': ['VRMC_vrm'],
    'extensions': {
      'VRMC_vrm': {
        'specVersion': '1.0',
        'meta': {
          'name': 'Synthetic',
          'authors': ['flutter_vrm tests'],
          'licenseUrl': 'https://vrm.dev/licenses/1.0/',
          'allowRedistribution': true,
        },
        'humanoid': {
          'humanBones':
              humanBones ??
              {
                for (var i = 0; i < syntheticBones.length; i++)
                  syntheticBones[i]: {'node': i + 1},
              },
        },
        ...vrmOverrides,
      },
    },
  };
}
