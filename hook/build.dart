import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Compiles flutter_vrm's MToon materials (assets/materials/*.fmat) into this
/// package's own flutter_scene_generated/ tree, which pubspec.yaml lists as
/// assets, so apps load them with `loadFmatMaterial(..., package:
/// 'flutter_vrm')` without a hook of their own.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
