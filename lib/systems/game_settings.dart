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

  /// Endless rivalry — mode picks thief count / pressure, not run length.
  RunMode runMode = RunMode.standard;
}

enum RunMode {
  standard(thiefCount: 1, titleRu: 'Стандарт', blurbRu: '1 вор'),
  long(thiefCount: 2, titleRu: 'Долгий', blurbRu: '2 вора');

  const RunMode({
    required this.thiefCount,
    required this.titleRu,
    required this.blurbRu,
  });

  final int thiefCount;
  final String titleRu;
  final String blurbRu;

  bool get isLong => this == RunMode.long;
}
