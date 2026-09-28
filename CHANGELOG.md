# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed

- MToon no longer washes out on iOS: missing matcap and shading-shift textures now zero their
  factors instead of relying on the shader's `default_black` placeholder, which samples white
  on iOS with the pinned flutter_scene.

### Changed

- `VrmAvatar.fromImported` is now asynchronous (it builds MToon materials).

### Added

- `VrmDocument` and `GlbContainer`: renderer-independent reading of VRM 1.0 meta, humanoid,
  expressions, and look-at (`package:flutter_vrm/vrm_schema.dart`).
- `VrmAvatar`: loads a `.vrm` into flutter_scene and maps glTF nodes and materials onto the
  imported model.
- `VrmHumanoidRig`: normalized humanoid bone rotations.
- `VrmExpressionManager`: expression weights with `isBinary` and overrides; morph target,
  material color (`color`, `emissionColor`), and texture transform binds.
- `VrmLookAt`: bone and expression look-at with range maps.
- `VrmAutoBlink`.
- MToon 1.0 materials (`assets/materials/*.fmat`, generated from `tool/mtoon_template.fmat`),
  compiled by the package's own build hook, with `VrmMToonLighting`. Textures honor the glTF
  sampler's wrap and filter modes.
- `VrmMaterialHandle`: material color and UV binds now drive MToon parameters as well as
  flutter_scene's standard materials.
- Example viewer app and `mise run fetch-samples`.
