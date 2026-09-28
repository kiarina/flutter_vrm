/// The renderer-independent part of flutter_vrm: GLB and VRM 1.0 parsing.
///
/// Import this instead of `flutter_vrm.dart` to read `.vrm` files without
/// flutter_scene (for tools or servers).
library;

export 'src/schema/glb.dart' show GlbContainer;
export 'src/schema/vrm_document.dart';
