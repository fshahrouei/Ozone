import 'package:flutter/material.dart';

/// Iconx
///
/// A custom icon registry for project-specific icons mapped from a font file.
/// - Equivalent to CSS icon classes (e.g., `.icon-...`).
/// - The font family must be declared in `pubspec.yaml` as `iconx`.
class Iconx {
  Iconx._();

  /// Font family name (must match pubspec.yaml configuration).
  static const String family = 'iconx';

  /// Map of icon names (CSS-style) to their Unicode codes.
  /// Example: 'icon-globe-alt' → 0xe800.
  static const Map<String, int> _codes = {
    'icon-globe-alt': 0xe800,
    'icon-cup': 0xe801,
    'icon-aparat': 0xe802,
    'icon-youtube': 0xe803,
    'icon-home-1': 0xe804,
    'icon-tick': 0xe805,
    'icon-heart': 0xe806,
    'icon-settings': 0xe807,
    'icon-magnifier': 0xe808,
    'icon-bell': 0xe809,
    'icon-wrench': 0xe80a,
    'icon-film': 0xe80b,
    'icon-rss': 0xe80c,
    'icon-eye-off': 0xe80d,
    'icon-telegram-plane': 0xe80e,
    'icon-heart-full': 0xe80f,
    'icon-play': 0xe810,
    'icon-facebook-f': 0xe811,
    'icon-md-arrow-round-back': 0xe812,
    'icon-circle-out': 0xe813,
    'icon-doc-1': 0xe814,
    'icon-md-arrow-round-forward': 0xe815,
    'icon-instagram': 0xe816,
    'icon-clock-alt': 0xe817,
    'icon-note': 0xe818,
    'icon-cog': 0xe819,
    'icon-exclamation': 0xe81a,
    'icon-bubble': 0xe81b,
    'icon-camera': 0xe81c,
    'icon-gavel': 0xe81d,
    'icon-dollar': 0xe81e,
    'icon-house-user': 0xe81f,
    'icon-id-card-alt': 0xe820,
    'icon-search': 0xe821,
    'icon-info-circle': 0xe822,
    'icon-attention-alt': 0xe823,
    'icon-pencil-alt': 0xe824,
    'icon-search-1': 0xe825,
    'icon-share': 0xe826,
    'icon-shopping-cart': 0xe827,
    'icon-stamp': 0xe828,
    'icon-user': 0xe829,
    'icon-user-cog': 0xe82a,
    'icon-tick-c': 0xe82b,
    'icon-emo-happy': 0xe82c,
    'icon-emo-unhappy': 0xe82d,
    'icon-life-ring': 0xe82e,
    'icon-spin6': 0xe82f,
    'icon-home-simple': 0xe830,
    'icon-lock': 0xe831,
    'icon-book': 0xe832,
    'icon-bag-plus': 0xe833,
    'icon-envelope': 0xe834,
    'icon-circle': 0xe835,
    'icon-angle-down': 0xe836,
    'icon-angle-up': 0xe837,
    'icon-angle-right': 0xe838,
    'icon-angle-left': 0xe839,
    'icon-help-circled-alt': 0xe83a,
    'icon-left-open-big': 0xe83b,
    'icon-times': 0xe83c,
    'icon-linkedin-in': 0xe83d,
    'icon-twitter': 0xe83e,
    'icon-desktop': 0xe83f,
    'icon-right-open-big': 0xe840,
    'icon-sun': 0xe841,
    'icon-moon': 0xe842,
    'icon-whatsapp': 0xe843,
    'icon-sms': 0xe844,
    'icon-key': 0xe845,
    'icon-comment': 0xe846,
    'icon-headphones': 0xe847,
    'icon-times-circle': 0xe848,
    'icon-exclamation-circle': 0xe849,
    'icon-error-alt': 0xe84a,
    'icon-chevron-up': 0xe84b,
    'icon-chevron-left': 0xe84c,
    'icon-chevron-right': 0xe84d,
    'icon-globe-1': 0xe84e,
    'icon-clock': 0xe84f,
    'icon-chevron-down': 0xe850,
    'icon-md-arrow-round-down': 0xe851,
    'icon-md-arrow-round-up': 0xe852,
    'icon-circle-notch': 0xe853,
    'icon-sync-alt': 0xe854,
    'icon-hotjar': 0xe855,
    'icon-eye': 0xe856,
    'icon-chat': 0xe857,
    'icon-sign-out-alt': 0xe858,
    'icon-bookmark': 0xe859,
    'icon-location': 0xe85a,
    'icon-folder-open': 0xe85b,
    'icon-folder': 0xe85c,
    'icon-flow-tree': 0xe85d,
    'icon-shop': 0xe85e,
    'icon-print': 0xe85f,
    'icon-doc-empty': 0xe860,
    'icon-link': 0xe861,
    'icon-box': 0xe862,
    'icon-trash-empty': 0xe863,
    'icon-trash-soft': 0xe864,
    'icon-list': 0xe865,
    'icon-attention': 0xe866,
    'icon-doc-text-inv': 0xe867,
    'icon-money-2': 0xe868,
    'icon-x': 0xe869,
    'icon-24-support': 0xe86a,
    'icon-dynamite-1': 0xe86b,
    'icon-dynamite-2': 0xe86c,
    'icon-hospital': 0xe86d,
    'icon-users': 0xe86e,
    'icon-customer-service': 0xe86f,
    'icon-ok': 0xe870,
    'icon-plus': 0xe871,
    'icon-blog': 0xe872,
    'icon-minus': 0xe873,
    'icon-code': 0xe874,
    'icon-check-circle': 0xe875,
    'icon-key-inv': 0xe876,
    'icon-camera-alt': 0xe877,
    'icon-truck-1': 0xe878,
    'icon-unlock-out': 0xe879,
    'icon-megaphone-fill': 0xe87a,
    'icon-dynamits': 0xe87b,
    'icon-bomb': 0xe87c,
    'icon-newspaper': 0xe87d,
    'icon-tick-s': 0xe87e,
    'icon-pen': 0xe87f,
    'icon-phone-2': 0xe880,
    'icon-pin': 0xe881,
    'icon-home': 0xe882,
    'icon-download': 0xe883,
    'icon-comment-text': 0xe884,
    'icon-qr-code': 0xe8a6,
    'icon-scan': 0xe8a8,
    'icon-bag': 0xe8a9,
    'icon-heart-1': 0xe8aa,
    'icon-bag-dash': 0xe8ab,
    'icon-dinamit': 0xe8ac,
    'icon-heart-fill': 0xe8ad,
    'icon-house': 0xe8af,
    'icon-shop-1': 0xe8b0,
    'icon-bag-fill': 0xe8b1,
    'icon-paperclip': 0xe8b2,
    'icon-lock-out': 0xe8b3,
    'icon-truck': 0xe8b4,
    'icon-geo-alt': 0xe8c3,
    'icon-geo-alt-fill': 0xe8c4,
    'icon-bookmark-1': 0xe8c6,
    'icon-bookmark-fill': 0xe8c7,
    'icon-chat-square': 0xe8c9,
    'icon-sliders2': 0xe8ca,
    'icon-x-circle-fill': 0xe8cb,
    'icon-at': 0xe8cc,
    'icon-envelope-fill': 0xe8cd,
    'icon-envelope-at-fill': 0xe8ce,
    'icon-c-square-fill': 0xe8cf,
    'icon-receipt': 0xe8d0,
    'icon-wallet-fill': 0xe8d1,
    'icon-credit-card-fill': 0xe8d2,
    'icon-upload': 0xe8d3,
    'icon-thumbtack': 0xe910,
    'icon-reply': 0xe913,
    'icon-coins': 0xe915,
    'icon-car': 0xe916,
    'icon-vote-yea': 0xe917,
    'icon-mobile-alt': 0xe918,
    'icon-pepper-hot': 0xe919,
    'icon-newspaper-1': 0xe91b,
    'icon-chart-line': 0xe91c,
    'icon-upload-cloud': 0xf014,
    'icon-download-cloud': 0xf015,
    'icon-globe': 0xf018,
    'icon-hash': 0xf029,
    'icon-ruler': 0xf044,
    'icon-info-circled-alt': 0xf086,
    'icon-bookmark-empty': 0xf097,
    'icon-github-circled': 0xf09b,
    'icon-certificate': 0xf0a3,
    'icon-menu': 0xf0c9,
    'icon-table': 0xf0ce,
    'icon-money': 0xf0d6,
    'icon-gauge': 0xf0e4,
    'icon-user-md': 0xf0f0,
    'icon-stethoscope': 0xf0f1,
    'icon-bell-alt': 0xf0f3,
    'icon-medkit': 0xf0fa,
    'icon-h-sigh': 0xf0fd,
    'icon-folder-empty': 0xf114,
    'icon-folder-open-empty': 0xf115,
    'icon-unlink': 0xf127,
    'icon-calendar-empty': 0xf133,
    'icon-rocket': 0xf135,
    'icon-lock-open-alt': 0xf13e,
    'icon-bitcoin': 0xf15a,
    'icon-doc': 0xf15b,
    'icon-doc-text': 0xf15c,
    'icon-apple': 0xf179,
    'icon-bug': 0xf188,
    'icon-graduation-cap': 0xf19d,
    'icon-google': 0xf1a0,
    'icon-database': 0xf1c0,
    'icon-file-excel': 0xf1c3,
    'icon-trash': 0xf1f8,
    'icon-brush': 0xf1fc,
    'icon-chart-pie': 0xf200,
    'icon-diamond': 0xf219,
    'icon-heartbeat': 0xf21e,
    'icon-server': 0xf233,
    'icon-shopping-bag': 0xf290,
    'icon-shopping-basket': 0xf291,
    'icon-percent': 0xf295,
  };

  /// Returns [IconData] for the given CSS-style [name].
  /// If the name does not exist, returns `null`.
  static IconData? byName(String name) {
    final code = _codes[name];
    if (code == null) return null;
    return IconData(code, fontFamily: family);
  }
}

/// IconxIcon
///
/// A convenience [StatelessWidget] wrapper for rendering icons by name.
/// Usage example:
/// ```dart
/// IconxIcon('icon-globe-alt', size: 24)
/// ```
class IconxIcon extends StatelessWidget {
  final String name;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;

  const IconxIcon(
    this.name, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    final data = Iconx.byName(name);
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
