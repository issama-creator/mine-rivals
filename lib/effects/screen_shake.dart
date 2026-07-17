import 'dart:math';

import 'package:flame/components.dart';

class ScreenShake extends Component {
  ScreenShake({
    required this.onOffset,
    this.intensity = 10,
    this.duration = 0.28,
  });

  final void Function(Vector2 offset) onOffset;
  final double intensity;
  final double duration;
  final Random _rng = Random();
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= duration) {
      onOffset(Vector2.zero());
      removeFromParent();
      return;
    }
    final falloff = 1 - (_t / duration);
    onOffset(
      Vector2(
        (_rng.nextDouble() - 0.5) * intensity * falloff * 2,
        (_rng.nextDouble() - 0.5) * intensity * falloff * 2,
      ),
    );
  }
}
