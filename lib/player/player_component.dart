import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../effects/ground_shadow.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';

class PlayerComponent extends SpriteAnimationComponent {
  PlayerComponent()
      : super(
          size: Vector2(GameConfig.playerWidth, GameConfig.playerHeight),
          anchor: Anchor.bottomCenter,
          priority: 20,
        );

  late RectangleHitbox basketHitbox;
  late GroundShadow _shadow;
  double targetX = 0;
  double _displayScale = 1;
  double _animRate = 1;

  Vector2 get basketWorldCenter {
    final local = Vector2(size.x * 0.5, size.y * 0.12);
    return absolutePositionOf(local);
  }

  void setRunAnimRate(double rate) {
    _animRate = rate.clamp(0.95, 3.0);
  }

  @override
  void update(double dt) {
    // Faster stride as corridors get quicker.
    super.update(dt * _animRate);
  }

  @override
  Future<void> onLoad() async {
    await AssetLibrary.ensureLoaded();
    animation = AssetLibrary.minerRunForSelected();
    playing = true;

    _shadow = GroundShadow();
    _shadow.size = Vector2(size.x * 0.78, size.y * 0.11);
    _shadow.position = Vector2(size.x * 0.5, size.y - 2);
    await add(_shadow);

    basketHitbox = RectangleHitbox(
      size: Vector2(GameConfig.basketWidth * 1.35, GameConfig.basketHeight * 2.2),
      position: Vector2(
        (size.x - GameConfig.basketWidth * 1.35) / 2,
        0,
      ),
    )..collisionType = CollisionType.passive;
    add(basketHitbox);
  }

  void moveToward(double x, double minX, double maxX, double dt) {
    targetX = x.clamp(minX, maxX);
    const speed = 18.0;
    position.x += (targetX - position.x) * (1 - (1 / (1 + speed * dt)));
  }

  void applyDepthScale(double scale, [double dt = 1 / 60]) {
    if (dt >= 0.2) {
      _displayScale = scale;
    } else {
      _displayScale += (scale - _displayScale) * (1 - (1 / (1 + 10 * dt)));
    }
    size = Vector2(
      GameConfig.playerWidth * _displayScale,
      GameConfig.playerHeight * _displayScale,
    );
    _shadow.size = Vector2(size.x * 0.78, size.y * 0.11);
    _shadow.position = Vector2(size.x * 0.5, size.y - 2);
    final bw = GameConfig.basketWidth * 1.35 * _displayScale;
    final bh = GameConfig.basketHeight * 2.2 * _displayScale;
    basketHitbox.size = Vector2(bw, bh);
    basketHitbox.position = Vector2((size.x - bw) / 2, 0);
  }
}
