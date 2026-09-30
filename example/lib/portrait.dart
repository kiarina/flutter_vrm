// Takes a bust-up portrait of each VRM file on a transparent background and
// writes it as a PNG. Run through `mise run portrait` (desktop only: it reads
// and writes local files).
//
// Jobs come in the PORTRAIT_JOBS environment variable, a JSON list of
// {"in": "<.vrm path>", "out": "<.png path>"}. PORTRAIT_SIZE sets the image's
// side in pixels (default 512) and PORTRAIT_EXPRESSIONS the expression values
// (for example `happy=0.3`). The app exits when every job is done, with a
// non-zero code if any failed.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'poses.dart';

/// The logical size of the view that is captured. The capture is scaled to
/// the requested pixel size, and the scene renders at twice that.
const double _viewSize = 400;

/// Vertical field of view. Narrow, so the face is not distorted.
const double _fovDegrees = 20;

/// Frames simulated before the capture, so hair and clothes settle.
const int _settleFrames = 90;

void main() => runApp(const PortraitApp());

class PortraitApp extends StatelessWidget {
  const PortraitApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'flutter_vrm portrait',
    debugShowCheckedModeBanner: false,
    home: PortraitPage(),
  );
}

class PortraitPage extends StatefulWidget {
  const PortraitPage({super.key});

  @override
  State<PortraitPage> createState() => _PortraitPageState();
}

class _PortraitPageState extends State<PortraitPage> {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: _fovDegrees * vm.degrees2Radians,
    fovNear: 0.05,
    fovFar: 100,
  );
  final GlobalKey _boundary = GlobalKey();

  final int size =
      int.tryParse(Platform.environment['PORTRAIT_SIZE'] ?? '') ?? 512;
  final String expressions = Platform.environment['PORTRAIT_EXPRESSIONS'] ?? '';

  bool ready = false;
  String status = 'initializing';
  VrmAvatar? avatar;

  /// Counts simulated frames while an avatar settles; the capture waits for
  /// [_settleFrames] of them.
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Scene.initializeStaticResources();
    scene.antiAliasingMode = AntiAliasingMode.msaa;
    // From the camera's side and above, without shadows (MToon receives
    // none, and a shadow pass would only cost time).
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(0.3, -0.5, 1)..normalize(),
      intensity: 3,
    );
    setState(() => ready = true);

    final jobs = (jsonDecode(
      Platform.environment['PORTRAIT_JOBS'] ?? '[]',
    ) as List).cast<Map<String, dynamic>>();
    var failed = 0;
    for (final job in jobs) {
      final input = job['in'] as String, output = job['out'] as String;
      try {
        await _capture(input, output);
        stdout.writeln('[portrait] wrote $output');
      } on Object catch (e) {
        failed++;
        stderr.writeln('[portrait] failed $input: $e');
      }
    }
    exit(jobs.isEmpty || failed > 0 ? 1 : 0);
  }

  Future<void> _capture(String input, String output) async {
    setState(() => status = input);
    final next = await VrmAvatar.fromBytes(await File(input).readAsBytes());
    final old = avatar;
    if (old != null) scene.remove(old.root);
    scene.add(next.root);

    for (final e in kPoses['idle']!.entries) {
      next.humanoid.setNormalizedRotation(e.key, e.value);
    }
    next.autoBlink.enabled = false;
    for (final kv in expressions.split(',')) {
      final parts = kv.split('=');
      if (parts.length == 2) {
        next.expressions.setValue(parts[0], double.tryParse(parts[1]) ?? 0);
      }
    }
    next.update(0);
    final framing = VrmPortrait.bust(
      next,
      fovYRadians: _fovDegrees * vm.degrees2Radians,
    );
    camera
      ..position = framing.position
      ..target = framing.target;
    next.lookAt.target = camera.position;
    next.springBones.reset();

    _frames = 0;
    setState(() => avatar = next);
    while (_frames < _settleFrames) {
      await WidgetsBinding.instance.endOfFrame;
    }
    // One more frame, so the view shows the last update.
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: size / _viewSize);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(output).parent.create(recursive: true);
    await File(output).writeAsBytes(png!.buffer.asUint8List());
  }

  void _onTick(Duration elapsed, double dt) {
    final a = avatar;
    if (a == null) return;
    a.mtoonLighting.fromScene(scene);
    // A fixed step, so the settling does not depend on the frame rate.
    a.update(1 / 60, camera: camera);
    _frames++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF808080),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: _boundary,
            child: SizedBox.square(
              dimension: _viewSize,
              child: ready
                  ? SceneView(
                      scene,
                      camera: camera,
                      pixelRatio: size / _viewSize * 2,
                      onTick: _onTick,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(status),
        ],
      ),
    ),
  );
}
