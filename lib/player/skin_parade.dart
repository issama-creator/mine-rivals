import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/game_config.dart';
import '../game/mine_rivals_game.dart';
import '../game/player_skins.dart';
import '../systems/game_settings.dart';

/// Side-by-side compare: real player + ghosts of the other skins (no duplicate).
class SkinParade extends Component with HasGameReference<MineRivalsGame> {
  final List<_ParadeRunner> _runners = [];
  final _PlayerSkinLabel _playerLabel = _PlayerSkinLabel();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await add(_playerLabel);
    for (final skin in PlayerSkins.paradeSkins) {
      await AssetLibrary.ensureSkinLoaded(skin.id);
      final anim = AssetLibrary.skinRuns[skin.id];
      if (anim == null) continue;
      final runner = _ParadeRunner(skin: skin, animation: anim);
      _runners.add(runner);
      await add(runner);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isMounted || _runners.isEmpty) return;
    final player = game.player;
    final selected = GameSettings.instance.selectedSkinId;
    final scale = player.size.y / GameConfig.playerCartHeight;

    _playerLabel.follow(player, PlayerSkins.byId(selected));

    final others = _runners.where((r) => r.skin.id != selected).toList();
    for (final r in _runners) {
      r.hidden = r.skin.id == selected;
    }
    if (others.isEmpty) return;

    final n = others.length;
    final laneSpread = (game.size.x * 0.55).clamp(150.0, 280.0);
    final step = n <= 1 ? 0.0 : laneSpread / (n - 1);
    final left = player.position.x - laneSpread * 0.5;

    for (var i = 0; i < n; i++) {
      final r = others[i];
      r.position.setValues(left + step * i, player.position.y);
      r.applyDepthScale(scale);
    }
  }
}

class _PlayerSkinLabel extends PositionComponent {
  PlayerSkin? _skin;

  static final Paint _labelBg = Paint()..color = const Color(0xCC000000);
  static final TextPainter _tp = TextPainter(textDirection: TextDirection.ltr);

  void follow(PositionComponent player, PlayerSkin skin) {
    _skin = skin;
    position.setValues(player.position.x, player.position.y - player.size.y);
    priority = 40;
  }

  @override
  void render(Canvas canvas) {
    final skin = _skin;
    if (skin == null) return;
    _tp.text = TextSpan(
      text: '▶ ${skin.nameRu}',
      style: TextStyle(
        color: skin.accent,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
    _tp.layout();
    const pad = 3.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -_tp.width * 0.5 - pad,
        -_tp.height - 4,
        _tp.width + pad * 2,
        _tp.height + pad,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, _labelBg);
    _tp.paint(canvas, Offset(-_tp.width * 0.5, -_tp.height - 2));
  }
}

class _ParadeRunner extends SpriteAnimationComponent {
  _ParadeRunner({
    required this.skin,
    required SpriteAnimation animation,
  }) : super(
          animation: animation,
          size: Vector2(
            GameConfig.playerCartWidth * 0.82,
            GameConfig.playerCartHeight * 0.82,
          ),
          anchor: Anchor.bottomCenter,
          priority: 18,
        ) {
    playing = true;
  }

  final PlayerSkin skin;
  bool hidden = false;
  double _displayScale = 0.82;

  static final Paint _labelBg = Paint()..color = const Color(0xCC000000);
  static final TextPainter _tp = TextPainter(textDirection: TextDirection.ltr);

  void applyDepthScale(double playerScale) {
    _displayScale = (0.78 * playerScale).clamp(0.55, 1.05);
    size.setValues(
      GameConfig.playerCartWidth * _displayScale,
      GameConfig.playerCartHeight * _displayScale,
    );
  }

  @override
  void update(double dt) {
    if (hidden) return;
    super.update(dt * 0.85);
  }

  @override
  void render(Canvas canvas) {
    if (hidden) return;
    super.render(canvas);
    _tp.text = TextSpan(
      text: skin.nameRu,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
    _tp.layout();
    const pad = 3.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.x * 0.5 - _tp.width * 0.5 - pad,
        -_tp.height - 8,
        _tp.width + pad * 2,
        _tp.height + pad,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, _labelBg);
    _tp.paint(
      canvas,
      Offset(size.x * 0.5 - _tp.width * 0.5, -_tp.height - 6),
    );
  }
}
