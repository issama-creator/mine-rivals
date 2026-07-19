import '../game/player_skins.dart';

/// Prices and stock caps for the crystal shop.
class ShopCatalog {
  ShopCatalog._();

  static const int heartPrice = 75;
  static const int potionPrice = 110;
  static const int maxStockHearts = 9;
  static const int maxStockPotions = 5;

  /// Welcome pack so the shop is usable before the first big run.
  static const int starterCrystals = 300;

  /// Paid skins only — free skins are not listed for purchase.
  static const Map<String, int> skinPrices = {
    'ninja': 500,
    'robot': 1200,
    'monkey': 2500,
    'pingvin': 5000,
    'mag': 8000,
  };

  static int? skinPrice(String id) => skinPrices[id];

  static List<PlayerSkin> get paidSkins => PlayerSkins.all
      .where((s) => skinPrices.containsKey(s.id))
      .toList(growable: false);
}
