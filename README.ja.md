# flutter_vrm

[![CI](https://github.com/kiarina/flutter_vrm/actions/workflows/ci.yml/badge.svg)](https://github.com/kiarina/flutter_vrm/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.md) | **日本語**

Flutter で VRM 1.0 のアバターを扱うライブラリです。描画は [flutter_scene](https://pub.dev/packages/flutter_scene)
（Flutter GPU / Impeller。Web は WebGL2）が行います。

![example アプリで表示した VRM 1.0 のサンプル 2 体。手を振って口を開けている子と、椅子に座って笑っている子](doc/images/hero.jpg)

## Summary

flutter_scene は、スキニング・モーフターゲット・PBR の材質を含む glTF を読み込み、iOS・Android・macOS・Windows・Linux・Web へ
同じ Dart のコードで描けます。ただし VRM は知らないので、`.vrm` を普通の glTF として読み、`VRMC_*` の拡張は読み飛ばします。
flutter_vrm は同じバイト列からその拡張を読み、読み込まれたモデルを VRM の定めどおりに動かします。humanoid の骨、表情、視線、まばたきです。

> [!NOTE]
> flutter_vrm はまだ初期段階（`0.1.0-dev`）です。API は変わる可能性があり、pub.dev にも公開していません。

## Features

- `VrmAvatar.fromBytes` で VRM 1.0 を flutter_scene の `Node` として**読み込む**
- **Meta**: 名前、作者、ライセンスと利用条件（`VrmMeta`）
- **Humanoid**: *正規化した*骨の回転（モデル空間、T ポーズからの差）で体を動かす。骨の軸の向きがモデルごとに違っても、
  同じポーズがどの VRM 1.0 のモデルにも効く
- **表情**: プリセットとカスタム、`isBinary`、まばたき・視線・口の override、モーフターゲット、材質の色（`color`・`emissionColor`）、
  テクスチャの UV の変換
- **視線**: `bone`（目の骨を回す）と `expression`（lookUp/Down/Left/Right を動かす）の両方。モデルの range map に従う
- **MToon**: `VRMC_materials_mtoon` の材質を MToon 1.0 のシェーダーで描く（影色、影の位置と境界のぼかし、発光、matcap、
  リム、UV アニメーション、アルファのモード、両面、法線マップ、輪郭線）。コンパイル済みでパッケージに含まれ、アプリ側のビルドの手順は要らない
- **SpringBone**: `VRMC_springBone` の揺れもの（髪、服）を、硬さ・重力・空気抵抗に従って揺らし、球とカプセルのコライダーに当てる。
  アバターを動かす・回す（`avatar.root`）と揺れ、寝かせても重力は世界の下向きのまま
- **ノードの拘束**: `VRMC_node_constraint` の roll・aim・rotation（ねじれの補助骨、腕に付いてくる袖など）
- **VRM Animation**: `.vrma` を任意の VRM 1.0 のモデルで再生する（`VrmAnimation`、`VrmAnimationPlayer`）。humanoid の回転
  （正規化した回転で移し替え、モデルに無い骨は子へ畳み込む）、モデルの大きさに合わせた hips の移動、表情、視線
- **当たり判定**: `avatar.hitTest(ray)` で、タップがどの部位に当たったかが分かる。humanoid の骨に沿ったカプセルが姿勢に付いてくるので、
  座っていても寝ていても見た目どおりの場所で当たる
- **自動まばたき**
- **描画に依存しないパーサー**: `package:flutter_vrm/vrm_schema.dart` は flutter_scene を使わずに GLB と VRM 1.0 を読む

まだ無いもの: 一人称の設定、VRM 0.x のファイル。
MToon の描画順（render queue の offset）は無視します（flutter_scene は半透明の面を深度で並べ替える）。

MToon の光はシーンではなく `avatar.mtoonLighting` から読みます。flutter_scene の独自材質がまだシーンの光を読めないためです。
シーンの平行光源に合わせるには、毎フレーム `avatar.mtoonLighting.fromScene(scene)` を呼びます。環境光は環境マップではなく
空と地面の 2 色（`skyColor`、`groundColor`）で近似し、MToon の面には影（シャドウマップ）が落ちません。
輪郭線は裏返した殻として描きます。flutter_scene の独自材質は頂点の段階でテクスチャを読めないため、輪郭線の太さのテクスチャは
マスクとして働きます（太さは係数どおりか 0 のどちらか）。画面の比率で太さを決める輪郭線がカメラの画角に従うよう、
`avatar.update(dt, camera: camera)` にカメラを渡します。

## Quick Start

Flutter 3.47 以上と、flutter_scene の準備（プラットフォームごとに Flutter GPU を有効にする、`dart run flutter_scene:init`）が要ります。
[flutter_scene の README](https://pub.dev/packages/flutter_scene) を参照してください。

```yaml
dependencies:
  flutter_scene: ^0.23.0
  flutter_vrm:
    git:
      url: https://github.com/kiarina/flutter_vrm
```

```dart
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart';

final scene = Scene();
final data = await rootBundle.load('assets/avatar.vrm');
final avatar = await VrmAvatar.fromBytes(data.buffer.asUint8List());
scene.add(avatar.root);

// ポーズ: 座る（モデル空間。+X がモデルの左、+Y が上、+Z が前）
avatar.humanoid
  ..setNormalizedRotation(
      VrmHumanBone.leftUpperLeg, Quaternion.axisAngle(Vector3(1, 0, 0), -1.57))
  ..setNormalizedRotation(
      VrmHumanBone.leftLowerLeg, Quaternion.axisAngle(Vector3(1, 0, 0), 1.57));

avatar.expressions.setPreset(VrmExpressionPreset.happy, 0.8);
avatar.lookAt.target = camera.position;

// 毎フレーム（SceneView の onTick など）
avatar.update(deltaSeconds, camera: camera);
```

タップが何に当たったかは、画面の位置をレイに変えてアバターに当てます。アバターは姿勢に付いてくるカプセル（頭・胴・腕・手・脚・足）で
判定するので、カプセルの外にはみ出す長い髪やスカートには当たりません。flutter_scene の `Scene.raycast` は骨入りのメッシュを
T ポーズのまま判定するので、アバターは外し、手前にある物に遮られるかどうかだけに使います。

```dart
onTapUp: (details) {
  final ray = camera.screenPointToRay(details.localPosition, viewSize);
  final hit = avatar.hitTest(ray); // 複数なら VrmAvatar.hitTestAll(avatars, ray)
  final blocker = scene.raycast(ray, where: (n) => !avatar.contains(n));
  if (hit != null && (blocker == null || hit.distance < blocker.distance)) {
    print('tapped ${hit.bone?.name} at ${hit.point}');
  }
},
```

部位ごとの太さや判定の有無は `avatar.hitShapes.capsules`（`radius`、`enabled`）で変えられます。`springColliders: true` を渡すと、
モデルの SpringBone のコライダーも判定に加えます。

VRM Animation を再生するときは、毎フレーム、アバターより先にプレイヤーを進めます。

```dart
final motion = await rootBundle.load('assets/wave.vrma');
final player = VrmAnimationPlayer(
  avatar,
  VrmAnimation.fromGlb(motion.buffer.asUint8List()),
);

// 毎フレーム:
player.update(deltaSeconds);
avatar.update(deltaSeconds, camera: camera);
```

アバターを動かす・向きを変えるときは `avatar.root` を変えます。モデルは自分の空間で +Z を向いており、flutter_scene のシーンでは -Z を向きます。

### Which flutter_scene

flutter_vrm は、公開済みの flutter_scene 0.23 と本家の `master`（開発中の 0.24）のどちらでもコンパイルできますが、
動作を確かめているのは `master` です（MToon のコンパイル済みシェーダーを含む。読み込めないときは glTF の材質のまま描きます）。このリポジトリは `master` の特定の
commit に固定して開発しています。私たちの計測では Android で 2〜3 倍速く描けました。アプリで同じようにするには、同じ commit の
2 つのパッケージを override します。

```yaml
dependency_overrides:
  flutter_scene:
    git:
      url: https://github.com/bdero/flutter_scene
      path: packages/flutter_scene
      ref: b02c99989473771a5d0baeba3cc03305a854f4eb
  scene:
    git:
      url: https://github.com/bdero/flutter_scene
      path: packages/scene
      ref: b02c99989473771a5d0baeba3cc03305a854f4eb
```

## Example

`example/` はビューアです。モデルを選び、カメラを回し、ポーズ・VRM Animation・表情のスライダーを試し、視線・まばたき・
揺れものを切り替え、部位をタップして当たり判定を試し（カプセルも描ける）、モデルのライセンスを確かめられます。

```sh
mise run fetch-samples      # サンプルのモデルとアニメーションをダウンロードする
cd example
flutter run -d macos        # ios、android、windows、chrome でも
```

自分の `.vrm` と `.vrma` を `example/assets/local/`（git の対象外）に置くと、一覧に出ます。

## Development

```sh
mise run          # フォーマットの確認、analyze、テスト（パッケージと example）
```

テストは小さな VRM をメモリ上で組み立てるので、モデルのファイルは要りません。

## Credits

example は次のモデルを [vrm-c/vrm-specification](https://github.com/vrm-c/vrm-specification/tree/master/samples) からダウンロードします。
このリポジトリには含めていません。

- Seed-san: Seed-san model by VirtualCast, Inc.（[VRM Public License 1.0](https://vrm.dev/licenses/1.0/)）
- VRM1_Constraint_Twist_Sample: (c) 2022 pixiv Inc.（[VRM Public License 1.0](https://vrm.dev/licenses/1.0/)）

上の画像は、この 2 体を example アプリで表示したものです。example はさらに
[pixiv/three-vrm](https://github.com/pixiv/three-vrm) の `test.vrma`（MIT、(c) pixiv Inc.）をダウンロードします。

## License

[MIT](LICENSE)
