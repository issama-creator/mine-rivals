import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/player_skins.dart';
import '../systems/game_settings.dart';
import '../systems/progress_store.dart';
import '../systems/shop_catalog.dart';

/// Crystal shop — card grid for helpers + skins.
class ShopSheet extends StatefulWidget {
  const ShopSheet({super.key});

  @override
  State<ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<ShopSheet> {
  int _tab = 0; // 0 helpers, 1 skins
  String? _toast;
  bool _toastOk = true;

  static const _gemAsset = 'assets/images/items/diamond.png';

  ProgressStore get _store => ProgressStore.instance;

  void _flash(String msg, {bool ok = true}) {
    setState(() {
      _toast = msg;
      _toastOk = ok;
    });
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _toast == msg) setState(() => _toast = null);
    });
  }

  Future<bool> _confirmBuy({
    required String title,
    required int price,
  }) async {
    HapticFeedback.selectionClick();
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A1A12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: const Color(0xFFFFB300).withValues(alpha: 0.7),
            ),
          ),
          title: const Text(
            'Точно хотите купить?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFFE082),
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Списать $price ◆?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF4FC3F7).withValues(alpha: 0.95),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Нет',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF66BB6A),
                      foregroundColor: const Color(0xFF1B5E20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Да, купить',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _buyHeart() async {
    if (_store.stockHearts >= ShopCatalog.maxStockHearts) {
      _flash('Запас сердец полон', ok: false);
      return;
    }
    if (_store.crystalBalance < ShopCatalog.heartPrice) {
      _flash('Мало кристаллов', ok: false);
      return;
    }
    final yes = await _confirmBuy(
      title: 'Сердце',
      price: ShopCatalog.heartPrice,
    );
    if (!yes || !mounted) return;
    final ok = await _store.buyHeart();
    HapticFeedback.mediumImpact();
    setState(() {});
    _flash(
      ok ? 'Сердце в запасе (${_store.stockHearts})' : 'Мало кристаллов',
      ok: ok,
    );
  }

  Future<void> _buyPotion() async {
    if (_store.stockPotions >= ShopCatalog.maxStockPotions) {
      _flash('Запас зелий полон', ok: false);
      return;
    }
    if (_store.crystalBalance < ShopCatalog.potionPrice) {
      _flash('Мало кристаллов', ok: false);
      return;
    }
    final yes = await _confirmBuy(
      title: 'Зелье рывка',
      price: ShopCatalog.potionPrice,
    );
    if (!yes || !mounted) return;
    final ok = await _store.buyPotion();
    HapticFeedback.mediumImpact();
    setState(() {});
    _flash(
      ok ? 'Зелье в запасе (${_store.stockPotions})' : 'Мало кристаллов',
      ok: ok,
    );
  }

  Future<void> _buySkin(PlayerSkin skin) async {
    final price = ShopCatalog.skinPrice(skin.id);
    if (price == null) return;
    if (_store.isSkinUnlocked(skin.id)) {
      unawaited(_store.selectSkin(skin.id));
      HapticFeedback.selectionClick();
      setState(() {});
      _flash('Выбран: ${skin.nameRu}');
      return;
    }
    if (_store.crystalBalance < price) {
      _flash('Мало кристаллов', ok: false);
      return;
    }
    final yes = await _confirmBuy(
      title: 'Скин «${skin.nameRu}»',
      price: price,
    );
    if (!yes || !mounted) return;
    final ok = await _store.buySkin(skin.id);
    HapticFeedback.mediumImpact();
    setState(() {});
    _flash(ok ? 'Куплено: ${skin.nameRu}!' : 'Мало кристаллов', ok: ok);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final bal = _store.crystalBalance;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF5D4037),
              Color(0xFF2A1A12),
              Color(0xFF140C08),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.65),
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB300).withValues(alpha: 0.12),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: h * 0.76,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'МАГАЗИН',
                  style: TextStyle(
                    color: Color(0xFFFFE082),
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _WalletBanner(balance: bal, gemAsset: _gemAsset),
                const SizedBox(height: 6),
                Text(
                  'Запас · ${_store.stockHearts} сердца · ${_store.stockPotions} зелья',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _toast == null
                      ? const SizedBox(height: 8)
                      : Padding(
                          key: ValueKey(_toast),
                          padding: const EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            _toast!,
                            style: TextStyle(
                              color: _toastOk
                                  ? const Color(0xFF81C784)
                                  : const Color(0xFFEF5350),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabChip(
                          label: 'Помощь',
                          selected: _tab == 0,
                          onTap: () => setState(() => _tab = 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TabChip(
                          label: 'Скины',
                          selected: _tab == 1,
                          onTap: () => setState(() => _tab = 1),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _tab == 0
                        ? GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.74,
                            children: [
                              _ShopCard(
                                accent: const Color(0xFFEF5350),
                                title: 'Сердце',
                                subtitle: 'Щит от ямы и шипов',
                                stock:
                                    '${_store.stockHearts}/${ShopCatalog.maxStockHearts}',
                                price: ShopCatalog.heartPrice,
                                canAfford: bal >= ShopCatalog.heartPrice,
                                onTap: _buyHeart,
                                art: const Icon(
                                  Icons.favorite_rounded,
                                  size: 52,
                                  color: Color(0xFFEF5350),
                                ),
                              ),
                              _ShopCard(
                                accent: const Color(0xFFAB47BC),
                                title: 'Зелье',
                                subtitle: 'Рывок — догони вора',
                                stock:
                                    '${_store.stockPotions}/${ShopCatalog.maxStockPotions}',
                                price: ShopCatalog.potionPrice,
                                canAfford: bal >= ShopCatalog.potionPrice,
                                onTap: _buyPotion,
                                art: const Icon(
                                  Icons.science_rounded,
                                  size: 52,
                                  color: Color(0xFFCE93D8),
                                ),
                              ),
                            ],
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: ShopCatalog.paidSkins.length,
                            itemBuilder: (context, i) {
                              final skin = ShopCatalog.paidSkins[i];
                              final price = ShopCatalog.skinPrice(skin.id)!;
                              final owned = _store.isSkinUnlocked(skin.id);
                              final selected =
                                  GameSettings.instance.selectedSkinId ==
                                      skin.id;
                              return _ShopCard(
                                accent: skin.accent,
                                title: skin.nameRu,
                                subtitle: owned
                                    ? (selected ? 'Выбран' : 'Куплен')
                                    : 'Внешний вид',
                                price: price,
                                canAfford: bal >= price,
                                owned: owned,
                                selected: selected,
                                onTap: () => _buySkin(skin),
                                art: Image.asset(
                                  skin.previewAsset,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    size: 56,
                                    color: skin.accent,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletBanner extends StatelessWidget {
  const _WalletBanner({required this.balance, required this.gemAsset});

  final int balance;
  final String gemAsset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0277BD).withValues(alpha: 0.35),
            const Color(0xFF01579B).withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF4FC3F7).withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              gemAsset,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.diamond_rounded,
                color: Color(0xFF4FC3F7),
                size: 22,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$balance',
              style: const TextStyle(
                color: Color(0xFFE1F5FE),
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'кристаллов',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFFFFB300).withValues(alpha: 0.28)
          : Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFB300)
                  : Colors.white.withValues(alpha: 0.1),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFFFE082)
                  : Colors.white.withValues(alpha: 0.65),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared shop product card — helpers and skins.
class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.canAfford,
    required this.onTap,
    required this.art,
    this.stock,
    this.owned = false,
    this.selected = false,
  });

  final Color accent;
  final String title;
  final String subtitle;
  final String? stock;
  final int price;
  final bool canAfford;
  final bool owned;
  final bool selected;
  final VoidCallback onTap;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? accent
        : accent.withValues(alpha: owned ? 0.55 : 0.4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.22),
                Colors.black.withValues(alpha: 0.55),
                const Color(0xFF1A100A),
              ],
            ),
            border: Border.all(
              color: borderColor,
              width: selected ? 2.2 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                accent.withValues(alpha: 0.28),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: art,
                      ),
                      if (owned)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF66BB6A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              selected ? 'ON' : 'OK',
                              style: const TextStyle(
                                color: Color(0xFF1B5E20),
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
                if (stock != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'запас $stock',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: owned
                          ? const [Color(0xFF66BB6A), Color(0xFF43A047)]
                          : canAfford
                              ? const [Color(0xFF4FC3F7), Color(0xFF0288D1)]
                              : [Colors.white24, Colors.white12],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    owned
                        ? (selected ? 'ВЫБРАН' : 'КУПЛЕН')
                        : 'КУПИТЬ · $price ◆',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: owned || canAfford
                          ? Colors.white
                          : Colors.white54,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
