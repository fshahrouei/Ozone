import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/logo_header.dart';
import '../widgets/social_links_list.dart';
import '../widgets/team_members_list.dart';
import '../widgets/references_list.dart';
import '../../../core/widgets/custom_app_bar.dart';

/// Static "About" screen showing app branding, social links,
/// team members, references, and the current app version.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<String> _getAppVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    // Example: "1.2.0 (42)"
    return '${packageInfo.version} (${packageInfo.buildNumber})';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'About Us',
        centerTitle: true,
        showDrawer: false,
        leading: const [], // hide back button on About
      ),
      body: FutureBuilder<String>(
        future: _getAppVersion(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text('Error loading version'));
          } else if (!snapshot.hasData) {
            return const Center(child: Text('No data available'));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 0),
            children: [
              const LogoHeader(),
              const SizedBox(height: 20),

              // Social links (now a Column, not an inner ListView)
              const SocialLinksList(),
              const SizedBox(height: 25),

              // ---- Team Members ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Text(
                  'Team Members',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18.5,
                    color: const Color.fromARGB(255, 100, 110, 120),
                    letterSpacing: 2.5,
                  ),
                ),
              ),
              const TeamMembersList(),
              const SizedBox(height: 24),

              // ---- References ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Text(
                  'References',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18.5,
                    color: const Color.fromARGB(255, 100, 110, 120),
                    letterSpacing: 2.5,
                  ),
                ),
              ),
              const ReferencesList(),
              const SizedBox(height: 12),

              // ---- Version ----
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child: Text(
                    'Version ${snapshot.data}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      backgroundColor: Colors.grey[100],
    );
  }
}
