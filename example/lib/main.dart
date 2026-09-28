import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'poses.dart';

/// Opens with the first model when set (`--dart-define=MODEL=Seed-san.vrm`).
const String kInitialModel = String.fromEnvironment('MODEL');

/// Initial pose name (see poses.dart), for screenshots and quick checks.
const String kInitialPose = String.fromEnvironment(
  'POSE',
  defaultValue: 'rest',
);

/// Initial expression values, e.g. `happy=1,aa=0.5`.
const String kInitialExpressions = String.fromEnvironment('EXPRESSIONS');

/// Initial camera yaw in degrees (0 looks at the avatar's face).
const String kInitialYaw = String.fromEnvironment('YAW');

/// `face` frames the head instead of the whole body.
const String kFraming = String.fromEnvironment('FRAMING');

/// Raises the camera focus by this many meters (for heads above the bone).
const String kFocusOffset = String.fromEnvironment('FOCUS_OFFSET');

/// Anti-aliasing mode name (`auto`, `none`, `msaa`, `fxaa`, `smaa`, `taa`).
const String kAntiAliasing = String.fromEnvironment('AA', defaultValue: 'auto');

/// `false` renders with the imported glTF materials instead of MToon.
const bool kMToon = bool.fromEnvironment('MTOON', defaultValue: true);

/// Loads the initial model this many times and lists every load's time
/// (to tell a slow first load from slow loads).
const int kLoads = int.fromEnvironment('LOADS', defaultValue: 1);

void main() => runApp(const ViewerApp());

class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_vrm viewer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const ViewerPage(),
  );
}

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 30 * vm.degrees2Radians,
    fovNear: 0.05,
    fovFar: 100,
  );

  List<String> models = [];

  /// `.vrma` assets, offered next to the built-in poses.
  List<String> animations = [];
  final Map<String, VrmAnimation> _animationCache = {};
  VrmAnimationPlayer? player;
  String? current;
  VrmAvatar? avatar;
  String status = 'initializing';
  bool ready = false;

  // Orbit camera around the avatar's chest.
  double yaw = (double.tryParse(kInitialYaw) ?? 0) * vm.degrees2Radians;
  double pitch = 5 * vm.degrees2Radians;
  double distance = 2.4;
  vm.Vector3 focus = vm.Vector3(0, 1.1, 0);
  double _lastScale = 1;

  String pose = kInitialPose;
  bool lookAtCamera = true;
  bool showMeta = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Scene.initializeStaticResources();
    scene.antiAliasingMode = AntiAliasingMode.values.firstWhere(
      (m) => m.name == kAntiAliasing,
      orElse: () => AntiAliasingMode.auto,
    );
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.3, -1, -0.5)..normalize(),
      intensity: 3,
      castsShadow: true,
    );
    scene.add(
      Node(
        name: 'floor',
        mesh: Mesh(
          CylinderGeometry(bottomRadius: 1.2, topRadius: 1.2, height: 0.02),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.8, 0.8, 0.82, 1)
            ..roughnessFactor = 0.9
            ..metallicFactor = 0,
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -0.01, 0)),
      ),
    );
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    models =
        manifest
            .listAssets()
            .where((a) => a.toLowerCase().endsWith('.vrm'))
            .toList()
          ..sort();
    animations =
        manifest
            .listAssets()
            .where((a) => a.toLowerCase().endsWith('.vrma'))
            .toList()
          ..sort();
    final initialAnimation = animations
        .where((a) => pose.endsWith('.vrma') && a.endsWith(pose))
        .firstOrNull;
    if (initialAnimation != null) pose = initialAnimation;
    setState(() {
      ready = true;
      status = models.isEmpty
          ? 'No VRM files. Run `mise run fetch-samples` or put .vrm files '
                'in example/assets/local/.'
          : '${models.length} models';
    });
    if (models.isNotEmpty) {
      final initial = models.firstWhere(
        (m) => kInitialModel.isNotEmpty && m.endsWith(kInitialModel),
        orElse: () => models.first,
      );
      for (var i = 0; i < kLoads; i++) {
        await _load(initial);
      }
    }
  }

  /// Every load's time as "import+flutter_vrm" milliseconds.
  final List<String> _loadTimes = [];

  Future<void> _load(String asset) async {
    setState(() => status = 'loading ${asset.split('/').last}');
    final sw = Stopwatch()..start();
    try {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      // VrmAvatar.fromBytes in two steps, to time flutter_scene's import
      // and flutter_vrm's part separately.
      final glb = GlbContainer.parse(bytes);
      final document = VrmDocument.fromGltfJson(glb.json);
      final imported = await Node.fromGlbBytes(
        bytes,
        onWarning: (w) {
          if (!'$w'.contains('VRMC_')) debugPrint('$w');
        },
      );
      final importMs = sw.elapsedMilliseconds;
      final next = await VrmAvatar.fromImported(
        document,
        imported,
        binary: glb.binary,
        mtoon: kMToon,
      );
      _loadTimes.add('$importMs+${sw.elapsedMilliseconds - importMs}');
      final old = avatar;
      if (old != null) scene.remove(old.root);
      scene.add(next.root);
      next.update(0);
      final head = next.humanoid.worldPosition(VrmHumanBone.head);
      setState(() {
        avatar = next;
        current = asset;
        final headY = head?.y ?? 1.4;
        if (kFraming == 'face') {
          focus = vm.Vector3(
            0,
            headY + 0.06 + (double.tryParse(kFocusOffset) ?? 0),
            0,
          );
          distance = 0.55;
        } else {
          focus = vm.Vector3(0, headY * 0.8, 0);
          distance = math.max(1.4, headY * 2.0);
        }
        status =
            '${kLoads > 1 ? 'loads (import+vrm ms): ${_loadTimes.join(', ')} · ' : ''}'
            '${next.meta.name} · loaded in ${sw.elapsedMilliseconds} ms · '
            '${next.document.expressions.length} expressions · '
            '${next.mtoonMaterialCount} MToon '
            '(${next.mtoonOutlineCount} outlined) · '
            '${next.springBones.chainCount} springs · '
            'AA ${scene.effectiveAntiAliasingMode.name} · '
            'look-at ${next.document.lookAt?.type ?? 'none'}';
      });
      _applyPose();
      for (final kv in kInitialExpressions.split(',')) {
        final parts = kv.split('=');
        if (parts.length == 2) {
          next.expressions.setValue(parts[0], double.tryParse(parts[1]) ?? 0);
          // An explicit blink value would be overwritten by auto blink.
          if (parts[0] == 'blink') next.autoBlink.enabled = false;
        }
      }
    } on Object catch (e) {
      setState(() => status = 'failed: $e');
    }
  }

  void _applyPose() {
    final a = avatar;
    if (a == null) return;
    a.humanoid.resetPose();
    player = null;
    if (pose.endsWith('.vrma')) {
      _playAnimation(a, pose);
      return;
    }
    final rotations = kPoses[pose] ?? const {};
    for (final e in rotations.entries) {
      a.humanoid.setNormalizedRotation(e.key, e.value);
    }
  }

  Future<void> _playAnimation(VrmAvatar a, String asset) async {
    try {
      final animation = _animationCache[asset] ??= VrmAnimation.fromGlb(
        (await rootBundle.load(asset)).buffer.asUint8List(),
      );
      if (!identical(avatar, a) || pose != asset) return;
      setState(() => player = VrmAnimationPlayer(a, animation));
    } on Object catch (e) {
      setState(() => status = 'animation failed: $e');
    }
  }

  void _onTick(Duration elapsed, double dt) {
    final eye =
        focus +
        vm.Vector3(
              math.sin(yaw) * math.cos(pitch),
              math.sin(pitch),
              -math.cos(yaw) * math.cos(pitch),
            ) *
            distance;
    camera
      ..position = eye
      ..target = focus;
    final a = avatar;
    if (a != null) {
      a.mtoonLighting.fromScene(scene);
      a.lookAt.enabled = lookAtCamera;
      a.lookAt.target = lookAtCamera ? eye : null;
      if (pose == 'idle') {
        // A small breathing sway on top of the relaxed arms.
        final t = elapsed.inMicroseconds / 1e6;
        a.humanoid.setNormalizedRotation(
          VrmHumanBone.spine,
          vm.Quaternion.axisAngle(
            vm.Vector3(1, 0, 0),
            math.sin(t * 2 * math.pi / 4) * 0.02,
          ),
        );
      }
      if (pose == 'turn') {
        final t = elapsed.inMicroseconds / 1e6;
        a.humanoid.setNormalizedRotation(
          VrmHumanBone.hips,
          vm.Quaternion.axisAngle(
            vm.Vector3(0, 1, 0),
            math.sin(t * 2 * math.pi / 2) * 0.7,
          ),
        );
      }
      player?.update(dt);
      a.update(dt, camera: camera);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return Scaffold(body: Center(child: Text(status)));
    final a = avatar;
    Widget controls(VrmAvatar a) => _Controls(
      avatar: a,
      pose: pose,
      animations: animations,
      lookAtCamera: lookAtCamera,
      showMeta: showMeta,
      onPose: (p) => setState(() {
        pose = p;
        _applyPose();
      }),
      onLookAt: (v) => setState(() => lookAtCamera = v),
      onMeta: (v) => setState(() => showMeta = v),
      onChanged: () => setState(() {}),
    );
    // Phones get the controls in a bottom sheet instead of a side panel.
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Scaffold(
      floatingActionButton: !wide && a != null
          ? FloatingActionButton.small(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => StatefulBuilder(
                  builder: (context, setSheet) => SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.45,
                    child: _Controls(
                      avatar: a,
                      pose: pose,
                      animations: animations,
                      lookAtCamera: lookAtCamera,
                      showMeta: showMeta,
                      onPose: (p) {
                        setState(() {
                          pose = p;
                          _applyPose();
                        });
                        setSheet(() {});
                      },
                      onLookAt: (v) {
                        setState(() => lookAtCamera = v);
                        setSheet(() {});
                      },
                      onMeta: (v) {
                        setState(() => showMeta = v);
                        setSheet(() {});
                      },
                      onChanged: () {
                        setState(() {});
                        setSheet(() {});
                      },
                    ),
                  ),
                ),
              ),
              child: const Icon(Icons.tune),
            )
          : null,
      body: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        setState(
                          () => distance =
                              (distance * math.pow(1.0015, e.scrollDelta.dy))
                                  .clamp(0.4, 8.0),
                        );
                      }
                    },
                    child: GestureDetector(
                      onScaleStart: (_) => _lastScale = 1,
                      onScaleUpdate: (d) {
                        yaw -= d.focalPointDelta.dx * 0.01;
                        pitch = (pitch + d.focalPointDelta.dy * 0.006).clamp(
                          -1.2,
                          1.4,
                        );
                        if (d.pointerCount >= 2 || d.scale != 1) {
                          distance = (distance / (d.scale / _lastScale)).clamp(
                            0.4,
                            8.0,
                          );
                          _lastScale = d.scale;
                        }
                      },
                      child: SceneView(scene, camera: camera, onTick: _onTick),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: MediaQuery.paddingOf(context).top + 12,
                  right: 12,
                  child: _TopBar(
                    models: models,
                    current: current,
                    status: status,
                    onSelect: _load,
                  ),
                ),
                if (showMeta && a != null)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: _MetaPanel(meta: a.meta),
                  ),
              ],
            ),
          ),
          if (a != null && wide) SizedBox(width: 300, child: controls(a)),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.models,
    required this.current,
    required this.status,
    required this.onSelect,
  });

  final List<String> models;
  final String? current;
  final String status;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (models.isNotEmpty)
            DropdownButton<String>(
              value: current,
              underline: const SizedBox(),
              items: [
                for (final m in models)
                  DropdownMenuItem(value: m, child: Text(m.split('/').last)),
              ],
              onChanged: (m) => m == null ? null : onSelect(m),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          Text(
            kIsWeb ? 'web' : defaultTargetPlatform.name,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.avatar,
    required this.pose,
    required this.animations,
    required this.lookAtCamera,
    required this.showMeta,
    required this.onPose,
    required this.onLookAt,
    required this.onMeta,
    required this.onChanged,
  });

  final VrmAvatar avatar;
  final String pose;
  final bool lookAtCamera;
  final bool showMeta;
  final ValueChanged<String> onPose;

  /// `.vrma` assets, shown as extra pose chips.
  final List<String> animations;
  final ValueChanged<bool> onLookAt;
  final ValueChanged<bool> onMeta;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final names = avatar.document.expressions.keys.toList()
      ..sort((a, b) {
        int rank(String n) =>
            VrmExpressionPreset.values.indexWhere((p) => p.name == n);
        final ra = rank(a), rb = rank(b);
        if (ra >= 0 && rb >= 0) return ra - rb;
        if (ra >= 0) return -1;
        if (rb >= 0) return 1;
        return a.compareTo(b);
      });
    return Material(
      elevation: 2,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Pose', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final p in kPoses.keys)
                ChoiceChip(
                  label: Text(p),
                  selected: pose == p,
                  onSelected: (_) => onPose(p),
                ),
              for (final p in animations)
                ChoiceChip(
                  avatar: const Icon(Icons.play_arrow, size: 16),
                  label: Text(p.split('/').last),
                  selected: pose == p,
                  onSelected: (_) => onPose(p),
                ),
            ],
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Look at the camera'),
            value: lookAtCamera,
            onChanged: onLookAt,
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Auto blink'),
            value: avatar.autoBlink.enabled,
            onChanged: (v) {
              avatar.autoBlink.enabled = v;
              if (!v) avatar.expressions.setValue('blink', 0);
              onChanged();
            },
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Spring bones'),
            value: avatar.springBones.enabled,
            onChanged: (v) {
              avatar.springBones.enabled = v;
              avatar.springBones.reset();
              onChanged();
            },
          ),
          SwitchListTile(
            dense: true,
            title: const Text('License / meta'),
            value: showMeta,
            onChanged: onMeta,
          ),
          const Divider(),
          Text('Expressions', style: Theme.of(context).textTheme.titleSmall),
          for (final n in names)
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(n, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: Slider(
                    value: avatar.expressions.value(n),
                    onChanged:
                        (n == 'blink' && avatar.autoBlink.enabled) ||
                            (lookAtCamera &&
                                n.startsWith('look') &&
                                avatar.document.lookAt?.type == 'expression')
                        ? null
                        : (v) {
                            avatar.expressions.setValue(n, v);
                            onChanged();
                          },
                  ),
                ),
              ],
            ),
          TextButton(
            onPressed: () {
              avatar.expressions.resetValues();
              onChanged();
            },
            child: const Text('Reset expressions'),
          ),
        ],
      ),
    );
  }
}

class _MetaPanel extends StatelessWidget {
  const _MetaPanel({required this.meta});

  final VrmMeta meta;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('name', meta.name),
      ('authors', meta.authors.join(', ')),
      if (meta.copyrightInformation != null)
        ('copyright', meta.copyrightInformation!),
      ('license', meta.licenseUrl),
      ('avatar permission', meta.avatarPermission),
      ('commercial usage', meta.commercialUsage),
      ('credit notation', meta.creditNotation),
      ('redistribution', meta.allowRedistribution ? 'allowed' : 'not allowed'),
      ('modification', meta.modification),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (k, v) in rows)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$k: ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: v),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                const JsonEncoder.withIndent(' ').convert({
                  'violent': meta.allowExcessivelyViolentUsage,
                  'sexual': meta.allowExcessivelySexualUsage,
                  'political/religious': meta.allowPoliticalOrReligiousUsage,
                  'antisocial/hate': meta.allowAntisocialOrHateUsage,
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
