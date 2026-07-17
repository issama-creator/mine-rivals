/// Lightweight session settings shared by menu + game.
class GameSettings {
  GameSettings._();
  static final GameSettings instance = GameSettings._();

  bool soundEnabled = true;
  bool shakeEnabled = true;
}
