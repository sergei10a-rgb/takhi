// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme/takhi_theme.dart';
import '../widgets/circle_icon_button.dart';

/// The brand mark, one file per brightness.
///
/// The gold horse at 2.28:1 on the near-white light sheet is legal for a
/// logo -- WCAG exempts trademarks -- but it sits directly beside the
/// wordmark, and a washed-out horse next to ink-black text reads as a
/// rendering bug rather than as a brand. So light takes the ink cut and
/// dark takes the gold one, which is exactly what the two files exist for.
const _kBrandMarkLight = 'assets/brand/takhi_horse_ink.png';
const _kBrandMarkDark = 'assets/brand/takhi_horse_gold.png';

/// Side of the brand mark, matched to the cap height of the wordmark beside
/// it so the horse and the name share one optical line.
const _kBrandMarkSize = 22.0;

/// Glyph size in the city pill. Smaller than the brand mark: the city is a
/// statement of context, not a second logo.
const _kCityGlyphSize = 14.0;

/// The controls that float across the top of the home map.
///
/// Three separate capsules rather than one bar: the map is the screen, and
/// a full-width header would cut a band out of it. Floating each piece on
/// its own leaves the gaps between them see-through, so the rider keeps as
/// much map as the controls do not literally cover.
///
/// Everything user-visible arrives as a parameter -- no localisation lookup,
/// no navigation, no providers -- so the bar is a pure function of its
/// inputs and can be rendered on its own in a test.
class HomeTopBar extends StatelessWidget {
  /// The wordmark beside the horse. User-visible: pass a localised string.
  final String appName;

  /// The city this build serves. Comes from `config/city_config.dart`, not
  /// from the translations: a fork that serves another city changes the
  /// config, not the language files.
  final String cityName;

  /// Announced by, and shown as a tooltip on, the settings control.
  /// User-visible: pass a localised string.
  final String settingsLabel;

  /// Opens settings.
  final VoidCallback onSettings;

  const HomeTopBar({
    super.key,
    required this.appName,
    required this.cityName,
    required this.settingsLabel,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        _FloatingPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                isDark ? _kBrandMarkDark : _kBrandMarkLight,
                width: _kBrandMarkSize,
                height: _kBrandMarkSize,
                fit: BoxFit.contain,
                // The mark is decoration beside a wordmark that already
                // says the name; announcing it again would make screen
                // readers read "Тахь" twice.
                excludeFromSemantics: true,
              ),
              const SizedBox(width: TakhiSpace.xs),
              Flexible(
                child: Text(
                  appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TakhiType.title.copyWith(color: surfaces.onSheet),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: TakhiSpace.xs),
        // Everything to the right of the brand shares one `Expanded`, and
        // the city pill inside it is the only [Flexible] in the bar. That
        // is the priority order made structural: on a narrow phone, or at
        // a doubled text scale, the city name is what gives way -- the
        // brand and the settings control never shrink, and nothing ever
        // overflows off the edge.
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: _FloatingPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: _kCityGlyphSize,
                        color: surfaces.muted,
                      ),
                      const SizedBox(width: TakhiSpace.xxs),
                      Flexible(
                        child: Text(
                          cityName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TakhiType.label.copyWith(
                            color: surfaces.onSheet,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: TakhiSpace.xs),
              CircleIconButton(
                icon: Icons.settings,
                semanticLabel: settingsLabel,
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A capsule of sheet-coloured surface floating directly on the map.
///
/// Same three-part recipe as every other raised plane in the app -- sheet
/// fill, hairline edge, [TakhiSurfaces.floatShadow] -- so a control over the
/// map stays legible against imagery of any colour without a scrim, and
/// separates itself the way the current brightness separates things (shadow
/// in light, hairline in dark).
class _FloatingPill extends StatelessWidget {
  final Widget child;

  const _FloatingPill({required this.child});

  @override
  Widget build(BuildContext context) {
    final surfaces = TakhiSurfaces.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TakhiSpace.sm,
        vertical: TakhiSpace.xs,
      ),
      decoration: BoxDecoration(
        color: surfaces.sheet,
        borderRadius: TakhiRadius.pillAll,
        border: Border.all(color: surfaces.hairline),
        boxShadow: surfaces.floatShadow,
      ),
      child: child,
    );
  }
}
