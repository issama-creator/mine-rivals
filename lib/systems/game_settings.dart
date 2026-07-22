/// Lightweight session settings shared by menu + game.
class GameSettings {
  GameSettings._();
  static final GameSettings instance = GameSettings._();

  bool soundEnabled = true;
  bool shakeEnabled = true;

  /// Lane steer sensitivity — 0 = плавно, 1 = резко.
  /// Slightly snappier default for “finger feels good” polish.
  double controlSensitivity = 0.42;

  /// Selected miner skin id — see [PlayerSkins].
  String selectedSkinId = 'player';

  /// Series rivalry — mode picks round count + thief pressure.
  RunMode runMode = RunMode.standard;
}

enum RunMode {
  standard(
    thiefCount: 1,
    seriesRounds: 10, // 10 × 500 м = 5 км
    titleRu: 'Стандарт',
    blurbRu: '5 км · 1 вор',
  ),
  long(
    thiefCount: 2,
    seriesRounds: 20, // 20 × 500 м = 10 км
    titleRu: 'Хардкор',
    blurbRu: '10 км · 2 вора',
  );

  const RunMode({
    required this.thiefCount,
    required this.seriesRounds,
    required this.titleRu,
    required this.blurbRu,
  });

  final int thiefCount;
  final int seriesRounds;
  final String titleRu;
  final String blurbRu;

  /// Target run length in meters (seriesRounds × 500 м).
  double get targetMeters => seriesRounds * 500.0;

  bool get isLong => this == RunMode.long;
  bool get isHardcore => this == RunMode.long;
}
