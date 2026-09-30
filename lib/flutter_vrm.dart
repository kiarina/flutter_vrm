/// VRM 1.0 avatars on flutter_scene.
///
/// [VrmDocument] reads the VRM content of a `.vrm` file without a renderer;
/// [VrmAvatar] loads the file into a flutter_scene [Node] and animates it.
library;

export 'src/runtime/expression_manager.dart' show VrmExpressionManager;
export 'src/runtime/hit_test.dart' show VrmHit, VrmHitCapsule, VrmHitShapes;
export 'src/runtime/humanoid_rig.dart' show VrmHumanoidRig;
export 'src/runtime/look_at.dart' show VrmLookAt;
export 'src/runtime/material_handles.dart'
    show VrmMaterialHandle, VrmStandardMaterialHandle;
export 'src/runtime/mtoon.dart' show VrmMToonLighting, VrmMToonMaterialHandle;
export 'src/runtime/node_constraint.dart' show VrmNodeConstraints;
export 'src/runtime/portrait.dart' show VrmPortrait;
export 'src/runtime/spring_bone.dart' show VrmSpringBoneSystem;
export 'src/runtime/vrm_animation_player.dart' show VrmAnimationPlayer;
export 'src/runtime/vrm_avatar.dart' show VrmAvatar, VrmAutoBlink;
export 'src/schema/vrm_animation.dart';
export 'src/schema/glb.dart' show GlbContainer;
export 'src/schema/vrm_document.dart';
