/// Lightweight session settings shared by menu + game.
class GameSettings {
  GameSettings._();
  static final GameSettings instance = GameSettings._();

  bool soundEnabled = true;
  bool shakeEnabled = true;

  /// Selected miner skin id — see [PlayerSkins].
  String selectedSkinId = 'player';

  /// Standard = 5×700 m, Long = 10×700 m.
  RunMode runMode = RunMode.standard;
}

enum RunMode {
  standard(corridors: 5, titleRu: 'Стандарт', subtitleRu: '5 шахт · 3500 м'),
  long(corridors: 10, titleRu: 'Долгий', subtitleRu: '10 шахт · 7000 м');

  const RunMode({
    required this.corridors,
    required this.titleRu,
    required this.subtitleRu,
  });

  final int corridors;
  final String titleRu;
  final String subtitleRu;
}
