import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vrm/flutter_vrm.dart';

import '../support/import_like.dart';
import '../support/synthetic_vrm.dart';

void main() {
  test('unlit materials take their alphaMode from the glTF material', () async {
    const unlit = {'KHR_materials_unlit': <String, dynamic>{}};
    final gltf = syntheticVrmJson()
      ..['materials'] = [
        {'name': 'blend', 'alphaMode': 'BLEND', 'extensions': unlit},
        {'name': 'mask', 'alphaMode': 'MASK', 'extensions': unlit},
        {'name': 'opaque', 'extensions': unlit},
      ]
      ..['meshes'] = [
        {
          'primitives': [
            {'material': 0},
            {'material': 1},
            {'material': 2},
          ],
        },
      ];
    (gltf['nodes'] as List).first['mesh'] = 0;
    final imported = importLike(gltf);
    // What the importer makes: unlit materials, all left opaque.
    final materials = [UnlitMaterial(), UnlitMaterial(), UnlitMaterial()];
    imported.children.first.mesh = Mesh.primitives(
      primitives: [
        for (final m in materials) MeshPrimitive(UnskinnedGeometry(), m),
      ],
    );

    await VrmAvatar.fromImported(
      VrmDocument.fromGltfJson(gltf),
      imported,
      mtoon: false,
    );

    expect(materials.map((m) => m.alphaMode), [
      AlphaMode.blend,
      // flutter_scene's unlit material has no cutoff; blend is the nearest.
      AlphaMode.blend,
      AlphaMode.opaque,
    ]);
  });
}
