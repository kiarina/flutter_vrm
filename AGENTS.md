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
- 見た目の確認は example で行う。`--dart-define=MODEL=... POSE=... EXPRESSIONS=happy=1 YAW=30` で、
  操作せずに同じ画面を再現できる

## VRM のファイル

- **VRM のファイルを git に入れない。** サンプルは `mise run fetch-samples` で取得する（`example/assets/samples/`、git の対象外）。
  手元のモデルは `example/assets/local/`（git の対象外）
- README や画像に載せてよいのは、再配布を許すモデルだけ（現在は VRM コンソーシアムの 2 体）。Seed-san はクレジットの表記が要る

## 変更したら

- `CHANGELOG.md` の `Unreleased` に追記する
- `mise run` が通ることを確かめてから commit する
- README を変えたら `README.ja.md` も同じ構成で直す（見出しは英語のまま一致させる）
