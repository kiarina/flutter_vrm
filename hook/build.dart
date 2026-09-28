import 'dart:io';

import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Compiles flutter_vrm's MToon materials (assets/materials/*.fmat) into this
/// package's own flutter_scene_generated/ tree, which pubspec.yaml lists as
/// assets, so apps load them with `loadFmatMaterial(..., package:
/// 'flutter_vrm')` without a hook of their own.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildMaterials(buildInput: input, buildOutput: output);
    // flutter_scene 0.23 writes one flat tree, 0.24 one directory per shader
    // backend. pubspec.yaml lists the 0.24 directories, and Flutter refuses
    // to build when a listed asset directory is missing, so make sure they
    // exist whichever version compiled the materials.
    for (final backend in const [
      'metal_ios',
      'metal_desktop',
      'opengl_es_vulkan',
      'opengl_es',
    ]) {
      Directory.fromUri(
        input.packageRoot.resolve('flutter_scene_generated/$backend/'),
      ).createSync(recursive: true);
    }
  });
}
