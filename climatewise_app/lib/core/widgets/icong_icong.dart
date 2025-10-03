import 'package:flutter/material.dart';

/// Icong
///
/// A custom icon registry for the `icong` font family.
/// - Equivalent to CSS icon classes (e.g., `.icong-*`).
/// - The font family must be declared in `pubspec.yaml` as `icong`.
class Icong {
  Icong._();

  /// Font family name (must match pubspec.yaml configuration).
  static const String family = 'icong';

  /// Map of icon names (CSS-style) to their Unicode codes.
  /// Example: 'icon-g-car' → 0xe800.
  static const Map<String, int> _codes = {
    'icon-g-car': 0xe800,
    'icon-g-chair': 0xe801,
    'icon-g-diamond': 0xe802,
    'icon-g-handshake': 0xe803,
    'icon-g-handyman': 0xe804,
    'icon-g-imagesearch-roller': 0xe805,
    'icon-g-lunch-dining': 0xe806,
    'icon-g-package': 0xe807,
    'icon-g-palette': 0xe808,
    'icon-g-phone': 0xe809,
    'icon-g-real-estate': 0xe80a,
    'icon-g-watch': 0xe80b,
    'icon-g-badge': 0xe80c,
    'icon-g-beauty': 0xe80d,
    'icon-g-garage_home': 0xe80e,
    'icon-g-grocery': 0xe80f,
    'icon-g-home_and_garden': 0xe810,
    'icon-g-other_houses': 0xe811,
    'icon-g-psychiatry': 0xe812,
    'icon-g-source_environment': 0xe813,
    'icon-g-storefront': 0xe814,
    'icon-g-universal_local': 0xe815,
    'icon-g-villa': 0xe816,
    'icon-g-warehouse': 0xe817,
    'icon-g-apartment': 0xe818,
    'icon-g-arrow_selector_tool': 0xe819,
    'icon-g-crop_landscape': 0xe81a,
    'icon-g-explosion': 0xe81b,
    'icon-g-factory': 0xe81c,
    'icon-g-living': 0xe81d,
    'icon-g-location_away': 0xe81e,
    'icon-g-night_shelter': 0xe81f,
    'icon-g-receipt_long': 0xe820,
    'icon-g-roofing': 0xe821,
    'icon-g-store': 0xe822,
    'icon-g-account_balance': 0xe823,
    'icon-g-foundation': 0xe824,
    'icon-g-house_siding': 0xe825,
    'icon-g-bike': 0xe826,
    'icon-g-sailing': 0xe827,
    'icon-g-car-1': 0xe828,
    'icon-g-transport': 0xe829,
    'icon-g-flight': 0xe82a,
    'icon-g-truck': 0xe82b,
    'icon-g-swap_driving': 0xe82c,
    'icon-g-car_tag': 0xe82d,
    'icon-g-motor': 0xe82e,
    'icon-g-service_toolbox': 0xe82f,
    'icon-g-minor_crash': 0xe830,
    'icon-g-car_repair': 0xe831,
    'icon-g-shuttle': 0xe832,
    'icon-g-no_crash': 0xe833,
    'icon-car-crash': 0xe834,
    'icon-g-car-rental': 0xe835,
    'icon-g-taxi': 0xe836,
    'icon-g-towing': 0xe837,
    'icon-g-agriculture': 0xe838,
    'icon-g-forklift': 0xe839,
    'icon-g-subway': 0xe83a,
    'icon-g-hookup': 0xe83b,
    'icon-g-bus': 0xe83c,
    'icon-g-loader': 0xe83d,
    'icon-g-select_all': 0xe83e,
    'icon-g-snowmobile': 0xe83f,
    'icon-g-ship': 0xe840,
    'icon-g-binoculars': 0xe841,
    'icon-g-hangout_video': 0xe842,
    'icon-g-tv': 0xe843,
    'icon-g-music_video': 0xe844,
    'icon-g-router': 0xe845,
    'icon-g-print': 0xe846,
    'icon-g-watch_screentime': 0xe847,
    'icon-g-watch-1': 0xe848,
    'icon-g-laptop_mac': 0xe849,
    'icon-g-sim_card': 0xe84a,
    'icon-g-tablet_mac': 0xe84b,
    'icon-g-more': 0xe84c,
    'icon-g-solar_power': 0xe84d,
    'icon-g-nest_cam': 0xe84e,
    'icon-g-party_mode': 0xe84f,
    'icon-g-call': 0xe850,
    'icon-g-stadia_controller': 0xe851,
    'icon-g-mic': 0xe852,
    'icon-g-computer': 0xe853,
    'icon-g-videocam': 0xe854,
    'icon-g-dark_mode': 0xe855,
    'icon-g-shopping_basket': 0xe856,
    'icon-g-glass': 0xe857,
    'icon-g-wine_bar': 0xe858,
    'icon-g-check_box': 0xe859,
    'icon-g-view_compact': 0xe85a,
    'icon-g-king_bed': 0xe85b,
    'icon-g-stockpot': 0xe85c,
    'icon-g-countertops': 0xe85d,
    'icon-g-cut': 0xe85e,
    'icon-g-dry_cleaning': 0xe85f,
    'icon-g-work': 0xe860,
    'icon-g-eyeglasses': 0xe861,
    'icon-g-endocrinology': 0xe862,
    'icon-g-crop': 0xe863,
    'icon-g-shoes': 0xe864,
    'icon-g-girl': 0xe865,
    'icon-g-woman': 0xe866,
    'icon-g-man': 0xe867,
    'icon-g-food_bank': 0xe868,
    'icon-g-vaping_rooms': 0xe869,
    'icon-g-pill': 0xe86a,
    'icon-g-face': 0xe86b,
    'icon-g-soap': 0xe86c,
    'icon-g-sanitizer': 0xe86d,
    'icon-g-dentistry': 0xe86e,
    'icon-g-face_2': 0xe86f,
    'icon-g-cleaning': 0xe870,
    'icon-g-groups': 0xe871,
    'icon-g-category': 0xe872,
    'icon-g-landscape': 0xe873,
    'icon-g-potted_plant': 0xe874,
    'icon-g-pets': 0xe875,
    'icon-g-sports_soccer': 0xe876,
    'icon-g-toys': 0xe877,
    'icon-g-square_foot': 0xe878,
    'icon-g-book': 0xe879,
    'icon-g-piano': 0xe87a,
    'icon-g-flight_takeoff': 0xe87b,
    'icon-g-ad': 0xe87c,
    'icon-g-encrypted': 0xe87d,
    'icon-g-gesture': 0xe87e,
    'icon-g-checkroom': 0xe87f,
    'icon-g-home_repair': 0xe880,
    'icon-g-medical_services': 0xe881,
    'icon-g-work_alert': 0xe882,
    'icon-g-mystery': 0xe883,
    'icon-g-key': 0xe884,
    'icon-g-cleaning_services': 0xe885,
    'icon-g-local_florist': 0xe886,
    'icon-g-payments': 0xe887,
    'icon-g-school': 0xe888,
    'icon-g-bolt': 0xe889,
    'icon-g-location': 0xe88a,
  };

  /// Returns [IconData] for the given CSS-style [name].
  /// If the name does not exist, returns `null`.
  static IconData? byName(String name) {
    final code = _codes[name];
    if (code == null) return null;
    return IconData(code, fontFamily: family);
  }
}

/// IcongIcon
///
/// A convenience widget for rendering icons by name.
/// Example:
/// ```dart
/// IcongIcon('icon-g-bike', size: 24)
/// ```
class IcongIcon extends StatelessWidget {
  final String name;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;

  const IcongIcon(
    this.name, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    final data = Icong.byName(name);
    if (data == null) {
      // Fallback icon if the name is not found
      return Icon(
        Icons.help_outline,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        textDirection: textDirection,
      );
    }
    return Icon(
      data,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }
}
