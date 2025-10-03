import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

/// A reusable list of social/contact links with icons and actions.
/// Opens external apps (browser, dialer, email, etc.) when tapped.
class SocialLinksList extends StatelessWidget {
  const SocialLinksList({super.key});

  static final List<_SocialLink> links = [
    _SocialLink(
      title: 'About Us',
      icon: CupertinoIcons.info_circle,
      color: Colors.indigo,
      url: 'https://climatewise.app/about',
    ),
    _SocialLink(
      title: 'Email',
      icon: CupertinoIcons.mail_solid,
      color: Colors.orange,
      url: 'mailto:team.ozone.spaceapps@gmail.com',
    ),
    _SocialLink(
      title: 'Website',
      icon: CupertinoIcons.globe,
      color: Colors.teal,
      url: 'https://climatewise.app',
    ),
  ];

  Future<void> _launchUrl(BuildContext context, String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        // Optional UX: show a SnackBar if nothing handled the URL
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $url')),
        );
      }
    } catch (e) {
      // Optional UX: report the error to the user as well
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Launch error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a Column to avoid nested ListViews when placed inside a ListView parent.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Column(
        children: List.generate(links.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Divider(
              height: 14,
              thickness: 0.7,
              color: Colors.grey[300],
            );
          }
          final link = links[i ~/ 2];
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 0, // keep shadows via BoxShadow if you prefer
            clipBehavior: Clip.antiAlias, // ensure ripple clips to radius
            child: InkWell(
              onTap: () => _launchUrl(context, link.url),
              child: ListTile(
                leading: Icon(link.icon, color: link.color, size: 24),
                title: Text(
                  link.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                  ),
                ),
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                trailing: const Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: Colors.grey,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SocialLink {
  final String title;
  final IconData icon;
  final Color color;
  final String url;

  const _SocialLink({
    required this.title,
    required this.icon,
    required this.color,
    required this.url,
  });
}
