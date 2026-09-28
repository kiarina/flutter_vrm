# AGENTS.md

このリポジトリで作業するエージェント向けのガイドラインです。

## 作業前に読むもの

- `README.md`（公開向けの説明。`README.ja.md` はその日本語のミラー）
- `pubspec.yaml`（flutter_scene の版の方針）
- `lib/`（`src/schema/` は描画に依存しない VRM の読み取り、`src/runtime/` は flutter_scene への結合）
- `CHANGELOG.md`

## 設計の決まり

- `lib/src/schema/` は flutter_scene を import しない。VRM の JSON を読むだけの層に保ち、
  `package:flutter_vrm/vrm_schema.dart` から単独で使えるようにする
- アプリ固有の概念（キャラクターの感情、ゲームの状態など）を持ち込まない。VRM の仕様にある概念だけを扱う
- **回転は行列（`Matrix3` / `Matrix4.compose`）で合成する。** vector_math の `Quaternion.rotated` は
  `asRotationMatrix()` や `Matrix4.compose` と逆向きの回転をかける。`Quaternion` は受け渡しにだけ使う
- 骨の姿勢は「正規化した回転」（VRM のモデル空間、T ポーズからの差、親の humanoid の骨に対する相対）で受け取り、
  `VrmHumanoidRig.apply` で各モデルの骨の軸へ変換する
- MToon は `tool/mtoon_template.fmat` を直して `dart run tool/generate_mtoon.dart` で `assets/materials/` の変種を作り直す
  （生成物を直接直さない）。パッケージ自身の `hook/build.dart` がコンパイルして `flutter_scene_generated/` に置き、アプリは
  `loadFmatMaterial(..., package: 'flutter_vrm')` で読む。Flutter 3.47 の stable では Dart data assets が使えないため、この方式にしている
- SpringBone は VRM のモデル空間で積分し、尾の位置だけ世界（`center` があればその節点の空間）で覚える。モデル空間なら回転が
  鏡映に汚されず、世界で覚えればアバターの移動で揺れる。重力の向きは glTF の -Z 鏡映を通してシーンへ写し、根で戻す
  （寝かせても下向き）。動きの確認は `test/runtime/spring_bone_test.dart` と example の `POSE=turn`
- NodeConstraint は three-vrm と同じ式（roll・rotation はローカルの回転、aim は親の回転をモデル空間で）。source やその祖先を
  別の拘束が動かすなら、そちらを先に評価する。確認は `test/runtime/node_constraint_test.dart` と Twist サンプルの袖・短パン
- VRMA は読み込み時に仕様の「NormalizedLocalRotation」（P·local·W⁻¹）へ直す。これは `VrmHumanoidRig` の正規化した回転と同じ
  空間なので、プレイヤーは `setNormalizedRotation` に渡すだけ。四元数の積は自前の Hamilton 積で書く（vector_math の演算子に
  頼らない）。確認は `test/schema/vrm_animation_test.dart` と example の `POSE=test.vrma`
- MToon の輪郭線は、同じ geometry に輪郭線用の材質（`mtoon_outline*`、表の面を捨てて頂点の段階で法線方向へ押し出す）の
  primitive を足して描く。**`.fmat` の sampler は fragment の段階でしか読めない**ので、太さのテクスチャは fragment で
  discard するマスクとして使う。**custom attribute（`Geometry.setCustomAttribute`）は使わない。** 宣言した attribute が無い
  skinned mesh ではゼロでなく不定値が読まれて殻が爆発し、VRoid のモデルに付けると 3D の描画全体が消えた（b02c999、macOS）
- flutter_scene の runtime importer は glTF のデータを変えずに読み込み、根のノードに Z の反転を置く。
  そのためこのパッケージの計算はすべてその根の子の空間（= glTF / VRM のモデル空間）で行う

## flutter_scene の版

- `pubspec.yaml` の依存は `>=0.23.0 <0.25.0`。開発と CI は `dependency_overrides` で本家の `master` の commit に固定する
  （`flutter_scene` と `scene` の両方。`example/pubspec.yaml` も同じ commit）
- 本家の不具合を直すときは、fork（`kiarina/flutter_scene`）の branch で直して本家へ Pull Request を出す。取り込まれるまでの間だけ
  override を fork の branch に向け、取り込まれたら本家の commit に戻す。fork を配布物として保たない
- 本家への Pull Request・issue の文面は、出す前にリポジトリの持ち主の確認を通す
- commit を上げたら、パッケージと example の両方で `mise run` を通す。0.23.0 でもコンパイルできることを、
  override を外した一時的なコピーで確かめる

## テスト

- `flutter test`。VRM のファイルは使わず、`test/support/synthetic_vrm.dart` でメモリ上に組み立てる
- 骨や視線の計算は、軸がそろっていない休止姿勢のリグ（`test/runtime/runtime_test.dart` の `chainVrm`）で確かめる
- 見た目の確認は example で行う。`--dart-define` の `MODEL`・`POSE`・`EXPRESSIONS`（例 `happy=1,aa=0.5`）・`YAW`・
  `FRAMING=face`・`FOCUS_OFFSET`・`AA`（`msaa` など）・`MTOON=false` で、操作せずに同じ画面を再現できる。
  `EXPRESSIONS` に `blink` を入れると自動まばたきが止まる。`POSE=turn` は腰を左右にひねって揺れものを見せ、`POSE=test.vrma` のように
  `.vrma` のファイル名を渡すと VRM Animation を再生する
- 読み込み時間は `LOADS=4` で同じモデルを 4 回読み、「flutter_scene の読み込み + flutter_vrm」の内訳を並べる。1 回目だけ遅いときは、
  初めて描くフレームの準備を待たされていることがある（Windows で 25 秒）
- iOS でだけ起きる描画の誤りは、iOS Simulator で再現する（Simulator も iOS 向けのシェーダーを使う）。実機より速く切り分けられる

## VRM のファイル

- **VRM のファイルを git に入れない。** サンプルは `mise run fetch-samples` で取得する（`example/assets/samples/`、git の対象外）。
  手元のモデルは `example/assets/local/`（git の対象外）
- README や画像に載せてよいのは、再配布を許すモデルだけ（現在は VRM コンソーシアムの 2 体）。Seed-san はクレジットの表記が要る

## 変更したら

- `CHANGELOG.md` の `Unreleased` に追記する
- `mise run` が通ることを確かめてから commit する
- README を変えたら `README.ja.md` も同じ構成で直す（見出しは英語のまま一致させる）
