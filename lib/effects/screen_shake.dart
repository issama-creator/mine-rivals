import 'dart:math';

import 'package:flame/components.dart';

class ScreenShake extends Component {
  ScreenShake({
    required this.onOffset,
    this.intensity = 10,
    this.duration = 0.28,
    Vector2? scratch,
  }) : _scratch = scratch ?? Vector2.zero();

  final void Function(Vector2 offset) onOffset;
  final double intensity;
  final double duration;
  final Random _rng = Random();
  final Vector2 _scratch;
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= duration) {
      _scratch.setZero();
      onOffset(_scratch);
      removeFromParent();
      return;
    }
    final falloff = 1 - (_t / duration);
    _scratch.setValues(
      (_rng.nextDouble() - 0.5) * intensity * falloff * 2,
      (_rng.nextDouble() - 0.5) * intensity * falloff * 2,
    );
    onOffset(_scratch);
  }
}
