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
- 当たり判定は humanoid の骨に沿ったカプセル（`VrmHitShapes`）で行う。flutter_scene の `Scene.raycast` は skinned mesh を休止姿勢で
  判定するので、アバターのメッシュには使わない。太さはモデルの hips の高さ（0.85 m を基準）で比例させる。頭だけは頭の骨から
  メッシュの上端まで（glTF の POSITION の min / max から。skinned mesh の `Geometry.localBounds` は空）で、頭の大きいモデルも覆う。確認は
  `test/runtime/hit_test_test.dart` と example の `HITS=true`（タップで部位が出る）
- VRMA は読み込み時に仕様の「NormalizedLocalRotation」（P·local·W⁻¹）へ直す。これは `VrmHumanoidRig` の正規化した回転と同じ
  空間なので、プレイヤーは `setNormalizedRotation` に渡すだけ。四元数の積は自前の Hamilton 積で書く（vector_math の演算子に
  頼らない）。確認は `test/schema/vrm_animation_test.dart` と example の `POSE=test.vrma`
- MToon の輪郭線は、同じ geometry に輪郭線用の材質（`mtoon_outline*`、表の面を捨てて頂点の段階で法線方向へ押し出す）の
  primitive を足して描く。**`.fmat` の sampler は fragment の段階でしか読めない**ので、太さのテクスチャは fragment で
  discard するマスクとして使う。**custom attribute（`Geometry.setCustomAttribute`）は使わない。** 材質と geometry の片方にしか無いと壊れる。
  宣言した材質で、付けていない skinned mesh を描くと不定値が読まれて殻が爆発し、付けた geometry を宣言しない材質（MToon の本体）でも描くと
  その描画が飛ばされ、影ありなら 3D の描画全体が消える（本家 #440、再現は labs `2026/09/30/flutter-scene-fmat-repros`）。
  本家の #443 で直る（M4 の Mac と iPad の実機で確かめた。未マージ）。固定先がそれを含んだら、太さを頂点の attribute で渡す形に戻すか決める
- flutter_scene の runtime importer は unlit（`KHR_materials_unlit`）の材質の `alphaMode` を読まず、常に不透明にする。
  `VrmAvatar.fromImported` が glTF の値から補う（`MASK` は unlit に cutoff が無いので blend）。確認は
  `test/runtime/unlit_alpha_test.dart` と、みぃねこの口（閉じた口の面が半透明の unlit）
- flutter_scene の runtime importer は glTF のデータを変えずに読み込み、根のノードに Z の反転を置く。
  そのためこのパッケージの計算はすべてその根の子の空間（= glTF / VRM のモデル空間）で行う

## flutter_scene の版

- `pubspec.yaml` の依存は `>=0.23.0 <0.25.0`。開発と CI は `pubspec_overrides.yaml` の `dependency_overrides` で本家の `master` の
  commit に固定する（`flutter_scene` と `scene` の両方。`example/pubspec_overrides.yaml` も同じ commit）。root の
  `pubspec_overrides.yaml` は pub.dev の公開物に入らないので、利用者は自分の flutter_scene を選ぶ
- README は 0.23 を既定として勧める。0.24 が公開されたら下限を上げて overrides を外す
- `master` の `1fa830b2`（2026-09-16）から `0852630d`（2026-09-30、本家 #438）の前までは、M3 世代以降の GPU（M3・M4 の Mac、最近の iPhone）で
  影ありの材質が Metal のシェーダーコンパイラを落とす（本家 #436、切り分けは labs `2026/09/29/flutter-scene-m4-metal-crash`）。固定先はこの範囲に
  戻さない。どうしてもこの範囲を M4 の Mac で動かすときは、lab の `interpose/safemath.m` を `DYLD_INSERT_LIBRARIES` で差し込む
- pub.dev への公開は取り消せない（discontinue しかできない）。公開の前にリポジトリの持ち主の確認を通し、`flutter pub publish --dry-run` の
  結果を見せる
- 本家の不具合を直すときは、fork（`kiarina/flutter_scene`）の branch で直して本家へ Pull Request を出す。取り込まれるまでの間だけ
  override を fork の branch に向け、取り込まれたら本家の commit に戻す。fork を配布物として保たない
- 本家への Pull Request・issue の文面は、出す前にリポジトリの持ち主の確認を通す
- commit を上げたら、パッケージと example の両方で `mise run` を通す。0.23.0 でもコンパイルできることを、
  `pubspec_overrides.yaml` を外した一時的なコピーで確かめる

## テスト

- `flutter test`。VRM のファイルは使わず、`test/support/synthetic_vrm.dart` でメモリ上に組み立てる
- テストの環境には GPU が無い。メッシュや材質が要るテストは、`UnskinnedGeometry()` と材質のインスタンス（`UnlitMaterial()` など）で
  `Mesh.primitives` を組む（`test/runtime/unlit_alpha_test.dart`）。`CuboidGeometry` などは作る時点で GPU へ上げるので使えない。`Scene()` も作れない
- 骨や視線の計算は、軸がそろっていない休止姿勢のリグ（`test/runtime/runtime_test.dart` の `chainVrm`）で確かめる
- 見た目の確認は example で行う。`--dart-define` の `MODEL`・`POSE`・`EXPRESSIONS`（例 `happy=1,aa=0.5`）・`YAW`・
  `FRAMING=face`・`FOCUS_OFFSET`・`AA`（`msaa` など）・`MTOON=false` で、操作せずに同じ画面を再現できる。
  `EXPRESSIONS` に `blink` を入れると自動まばたきが止まる。`POSE=turn` は腰を左右にひねって揺れものを見せ、`POSE=test.vrma` のように
  `.vrma` のファイル名を渡すと VRM Animation を再生する
- 読み込み時間は `LOADS=4` で同じモデルを 4 回読み、「flutter_scene の読み込み + flutter_vrm」の内訳を並べる。1 回目だけ遅いときは、
  初めて描くフレームの準備を待たされていることがある（Windows。ANGLE がシェーダーを D3DCompile で変換する時間で、`aae39f9` の影ありで 7〜8 秒、
  起動のたびにやり直す。切り分けは labs `2026/09/30/flutter-scene-windows-first-draw`）
- バストアップの撮影は `mise run portrait <file.vrm>...`（`example/lib/portrait.dart` を macOS でビルドして、VRM ごとに
  背景透過の PNG を書く）。任意のパスを読み書きするため、example の macOS の debug ビルドは sandbox を切っている。
  構図は `VrmPortrait.bust`（`lib/src/runtime/portrait.dart`）で、頭の上端（当たり判定の頭のカプセル）から肩の少し下まで。半透明の材質が穴を開けていないかは、背景透過の PNG を
  色のある背景に重ねると分かる（穴かどうかは、後ろに不透明な板を置いて撮ると切り分けられる。板まで消えていれば、合成されずに上書きされている）。
  `mise run portrait` は example の macOS の debug ビルドを撮影用の入口で上書きする。画面の読み戻しは `RepaintBoundary.toImage`
  （skybox を置かなければ背景は透明）
- 実機の iOS で見つけた描画の誤りは、iOS Simulator で再現する（Simulator も iOS 向けのシェーダーを使う）。実機より速く切り分けられる。
  ただし Simulator の GPU とシェーダーのコンパイラは Mac のものなので、直ったことの確認は実機でする

## VRM のファイル

- **VRM のファイルを git に入れない。** サンプルは `mise run fetch-samples` で取得する（`example/assets/samples/`、git の対象外）。
  手元のモデルは `example/assets/local/`（git の対象外）
- README や画像に載せてよいのは、再配布を許すモデルだけ（現在は VRM コンソーシアムの 2 体）。Seed-san はクレジットの表記が要る

## 変更したら

- `CHANGELOG.md` の `Unreleased` に追記する
- `mise run` が通ることを確かめてから commit する
- README を変えたら `README.ja.md` も同じ構成で直す（見出しは英語のまま一致させる）
