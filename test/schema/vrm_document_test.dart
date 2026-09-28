import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/vrm_schema.dart';

import '../support/synthetic_vrm.dart';

void main() {
  group('GlbContainer', () {
    test('reads the JSON and BIN chunks', () {
      final glb = buildGlb({
        'asset': {'version': '2.0'},
      }, bin: Uint8List.fromList([1, 2, 3]));
      final c = GlbContainer.parse(glb);
      expect(c.json['asset'], {'version': '2.0'});
      expect(c.binary!.sublist(0, 3), [1, 2, 3]);
    });

    test('rejects a file that is not a GLB', () {
      expect(
        () => GlbContainer.parse(Uint8List(32)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a chunk that runs past the end', () {
      final glb = buildGlb({
        'asset': {'version': '2.0'},
      });
      ByteData.sublistView(glb).setUint32(12, 1 << 20, Endian.little);
      expect(() => GlbContainer.parse(glb), throwsA(isA<FormatException>()));
    });
  });

  group('VrmDocument', () {
    test('reads meta and humanoid bones', () {
      final doc = VrmDocument.fromGlb(buildGlb(syntheticVrmJson()));
      expect(doc.specVersion, '1.0');
      expect(doc.meta.name, 'Synthetic');
      expect(doc.meta.authors, ['flutter_vrm tests']);
      expect(doc.meta.allowRedistribution, isTrue);
      expect(doc.meta.modification, 'prohibited'); // spec default
      expect(doc.humanBones[VrmHumanBone.hips], 1);
      expect(doc.humanBones[VrmHumanBone.leftEye], 4);
      expect(doc.humanBones.containsKey(VrmHumanBone.jaw), isFalse);
    });

    test('rejects a humanoid without the required bones', () {
      final json = syntheticVrmJson(
        humanBones: {
          'hips': {'node': 1},
        },
      );
      expect(
        () => VrmDocument.fromGltfJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('spine'),
          ),
        ),
      );
    });

    test('rejects a bone pointing at a missing node', () {
      final json = syntheticVrmJson();
      ((json['extensions']['VRMC_vrm']['humanoid']['humanBones'] as Map)['hips']
              as Map)['node'] =
          999;
      expect(
        () => VrmDocument.fromGltfJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('says so for VRM 0.x files', () {
      expect(
        () => VrmDocument.fromGltfJson({
          'extensions': {'VRM': <String, dynamic>{}},
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('VRM 0.x'),
          ),
        ),
      );
    });

    test('reads preset and custom expressions with their binds', () {
      final doc = VrmDocument.fromGltfJson(
        syntheticVrmJson(
          vrmOverrides: {
            'expressions': {
              'preset': {
                'happy': {
                  'isBinary': true,
                  'overrideBlink': 'block',
                  'overrideMouth': 'blend',
                  'morphTargetBinds': [
                    {'node': 3, 'index': 2, 'weight': 0.5},
                  ],
                  'materialColorBinds': [
                    {
                      'material': 1,
                      'type': 'color',
                      'targetValue': [1, 0, 0, 1],
                    },
                  ],
                  'textureTransformBinds': [
                    {
                      'material': 0,
                      'offset': [0, -0.25],
                    },
                  ],
                },
                'notAPreset': <String, dynamic>{},
              },
              'custom': {
                'wink': {
                  'morphTargetBinds': [
                    {'node': 3, 'index': 5, 'weight': 1},
                  ],
                },
              },
            },
          },
        ),
      );
      final happy = doc.expressions['happy']!;
      expect(happy.preset, VrmExpressionPreset.happy);
      expect(happy.isBinary, isTrue);
      expect(happy.overrideBlink, VrmExpressionOverride.block);
      expect(happy.overrideLookAt, VrmExpressionOverride.none);
      expect(happy.overrideMouth, VrmExpressionOverride.blend);
      expect(happy.morphTargetBinds.single.weight, 0.5);
      expect(happy.materialColorBinds.single.targetValue.x, 1);
      expect(happy.textureTransformBinds.single.offset.y, -0.25);
      expect(happy.textureTransformBinds.single.scale.x, 1); // default
      expect(doc.expressions.containsKey('notAPreset'), isFalse);
      expect(doc.expressions['wink']!.preset, isNull);
    });

    test('reads look-at with the spec default range maps', () {
      final bone = VrmDocument.fromGltfJson(
        syntheticVrmJson(
          vrmOverrides: {
            'lookAt': {
              'type': 'bone',
              'offsetFromHeadBone': [0, 0.06, 0.02],
              'rangeMapHorizontalOuter': {
                'inputMaxValue': 45,
                'outputScale': 9,
              },
            },
          },
        ),
      ).lookAt!;
      expect(bone.offsetFromHeadBone.y, closeTo(0.06, 1e-6));
      expect(bone.rangeMapHorizontalOuter.map(90), 9); // clamped to max
      expect(bone.rangeMapHorizontalOuter.map(22.5), closeTo(4.5, 1e-9));
      expect(bone.rangeMapHorizontalInner.outputScale, 10); // bone default
      final expression = VrmDocument.fromGltfJson(
        syntheticVrmJson(
          vrmOverrides: {
            'lookAt': {'type': 'expression'},
          },
        ),
      ).lookAt!;
      expect(
        expression.rangeMapVerticalUp.outputScale,
        1,
      ); // expression default
      expect(expression.rangeMapVerticalUp.map(-10), 0);
    });
  });
}
