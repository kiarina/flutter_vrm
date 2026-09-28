# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
- Example viewer app and `mise run fetch-samples`.
