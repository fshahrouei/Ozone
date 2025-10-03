import 'package:flutter/material.dart';

/// A customizable AppBar:
/// - By default shows a back button if nothing else is provided.
/// - If [showDrawer] is true (and [leading] is null), shows a menu button that opens the drawer.
/// - If [leading] is provided, uses that instead.
/// - Accepts [actions] on the right.
/// - Title can be centered or left-aligned via [centerTitle].
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  /// Custom leading widgets on the left.
  /// If null, falls back to [showDrawer] or default back button.
  final List<Widget>? leading;

  /// Custom action widgets on the right.
  final List<Widget>? actions;

  /// Whether to center the title or not. Defaults to false (left).
  final bool centerTitle;

  /// If true, shows a menu button (only used when [leading] is null).
  final bool showDrawer;

  /// Optional callback for default back button.
  final VoidCallback? onBackPressed;

  const CustomAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.centerTitle = false, // default left
    this.showDrawer = false,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget? resolvedLeading;

    if (leading != null) {
      resolvedLeading = Row(
        mainAxisSize: MainAxisSize.min,
        children: leading!,
      );
    } else if (showDrawer) {
      resolvedLeading = Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      );
    } else {
      resolvedLeading = IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackPressed ?? () => Navigator.pop(context),
      );
    }

    return AppBar(
      centerTitle: centerTitle,
      title: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: theme.appBarTheme.foregroundColor,
        ),
      ),
      leadingWidth: (leading != null && leading!.length > 1) ? 100 : 56,
      leading: resolvedLeading,
      actions: actions,
      elevation: 0,
      backgroundColor: theme.appBarTheme.backgroundColor,
      foregroundColor: theme.appBarTheme.foregroundColor,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
