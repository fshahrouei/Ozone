import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/about_model.dart';

/// Team grid with tappable cards. Tapping a card opens a dialog
/// showing a large circular avatar, name, role, and the member bio.
class TeamMembersList extends StatelessWidget {
  const TeamMembersList({super.key});

  // --- Member bios keyed by the exact display name ---
  static const Map<String, String> _descriptions = {
    'Fariba Shahrouei':
        'Hello, I am Fariba Shahrouei, I am 26 years old and from Turkey. I hold a Bachelor\'s degree in Petroleum Engineering and am currently pursuing a Master\'s degree in Chemical Engineering. I served as the Project Lead, Concept Owner, and was responsible for the project design and scenario development. I personally managed all aspects of problem selection, ideation, content creation, and overall project management, while actively contributing to the research. The technical execution (app development) was carried out by an external development team under my supervision. Through close collaboration with the developer, to whom I conveyed the project\'s structure and logic, I successfully oversaw the implementation of the application.',
    'Mersana Dashtizadeh':
        'Hi, I am mersanadashtizadeh, a 13-year-old participant from Turkey. I contributed to the research component of our project.',
    'Zahra Derakhshandeh':
        'Hi, I am zahra derakhshandeh, a 40-year-old participant from Turkey. I contributed to the research component of our project.',
    'Mahan Gholamian nejad':
        'Hi, I am mahan gholamian nejad, a 17-year-old participant from Turkey. I contributed to the research component of our project.',
    'Reza Modares':
        'Hi, I am reza modares, a 17-year-old participant from Turkey. I contributed to the research component of our project.',
    'Mohammad Mehdi Mozafar':
        'Hi, I am mohammad mehdi mozafar, a 14-year-old participant from Turkey. I contributed to the research component of our project.',
  };

  // --- Team list (you can fill socials later if needed) ---
  static final List<TeamMember> members = [
    TeamMember(
      name: 'Fariba Shahrouei',
      role: 'Project Lead',
      imageUrl: 'https://climatewise.app/img/members/app_1.webp',
      instagramUrl: '',
      facebookUrl: '',
      twitterUrl: '',
      telegramUrl: '',
    ),
    TeamMember(
      name: 'Mersana Dashtizadeh',
      role: 'Research',
      imageUrl: 'https://climatewise.app/img/members/app_2.webp',
      instagramUrl: '',
      facebookUrl: '',
      twitterUrl: '',
      telegramUrl: '',
    ),
    TeamMember(
      name: 'Zahra Derakhshandeh',
      role: 'Research',
      imageUrl: 'https://climatewise.app/img/members/app_3.webp',
      instagramUrl: '',
      facebookUrl: '',
      twitterUrl: '',
      telegramUrl: '',
    ),
    TeamMember(
      name: 'Mahan Gholamian nejad',
      role: 'Research',
      imageUrl: 'https://climatewise.app/img/members/app_4.webp',
      instagramUrl: '',
      facebookUrl: '',
      twitterUrl: '',
      telegramUrl: '',
    ),
    TeamMember(
      name: 'Reza Modares',
      role: 'Research',
      imageUrl: 'https://climatewise.app/img/members/app_6.webp',
      instagramUrl: '',
      facebookUrl: '',
      twitterUrl: '',
      telegramUrl: '',
    ),
    TeamMember(
      name: 'Mohammad Mehdi Mozafar',
      role: 'Research',
      imageUrl: 'https://climatewise.app/img/members/app_5.webp',
      instagramUrl: '',
      facebookUrl: '',
      twitterUrl: '',
      telegramUrl: '',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = members.length <= 2 ? 1 : 2;

    // --- compute card width based on outer paddings and spacing
    final size = MediaQuery.of(context).size;
    const double outerHPad = 20.0;   // from parent Padding(horizontal: 20)
    const double gridHSpacing = 14.0;
    final double totalHPad = outerHPad * 2 + (crossAxisCount - 1) * gridHSpacing;
    final double cardWidth = (size.width - totalHPad) / crossAxisCount;

    // --- avatar size inside each card
    final double desiredAvatar = (cardWidth * 0.7).clamp(70.0, 96.0);

    // --- estimate text heights (font * line-height) + small buffer
    const int nameLines = 2;
    const int roleLines = 2;
    const double nameFont = 15.2;
    const double roleFont = 12.8;
    const double lh = 1.4;
    final double nameH = nameFont * lh * nameLines;
    final double roleH = roleFont * lh * roleLines;
    const double safetyBuffer = 16.0; // avoid overflow on small devices

    // --- fixed paddings/gaps inside card
    const double padTopBottom = 8.0 + 6.0; // container vertical padding
    const double gapAvatarTop = 20.0;      // top gap before avatar
    const double gapTop = 12.0;            // between avatar and name
    const double gapBetweenTexts = 10.0;   // between name and role
    const double bottomGapWanted = 15.0;   // bottom padding
    const double socialsRowHeightIfAny = 0.0; // change to 24 if you add socials

    // --- final grid cell height
    final double itemHeight = padTopBottom
        + gapAvatarTop
        + desiredAvatar
        + gapTop
        + nameH
        + roleH
        + gapBetweenTexts
        + socialsRowHeightIfAny
        + bottomGapWanted
        + safetyBuffer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: outerHPad, vertical: 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: members.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 16,
          crossAxisSpacing: gridHSpacing,
          mainAxisExtent: itemHeight,
        ),
        itemBuilder: (context, idx) => _TeamMemberCard(
          member: members[idx],
          description: _descriptions[members[idx].name] ?? '',
        ),
      ),
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  final TeamMember member;
  final String description;
  const _TeamMemberCard({required this.member, required this.description});

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showMemberDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- Large circular avatar in dialog
                  CircleAvatar(
                    radius: 70, // bigger than card avatar
                    backgroundImage: NetworkImage(member.imageUrl),
                    backgroundColor: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  // --- Name
                  Text(
                    member.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // --- Role
                  Text(
                    member.role,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 16),
                  // --- Description
                  Text(
                    description.isNotEmpty
                        ? description
                        : 'No additional bio provided.',
                    textAlign: TextAlign.start,
                    style: const TextStyle(fontSize: 14.0, height: 1.45),
                  ),

                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = constraints.maxWidth;
        final double avatarDiameter =
            (cardWidth * 0.7).clamp(70.0, 96.0).toDouble();

        return InkWell(
          onTap: () => _showMemberDialog(context), // whole card is tappable
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 20), // top gap before avatar
                CircleAvatar(
                  radius: avatarDiameter / 2,
                  backgroundImage: NetworkImage(member.imageUrl),
                  backgroundColor: Colors.grey[300],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    member.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.2,
                    ),
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    member.role,
                    style: TextStyle(
                      fontSize: 12.8,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                  ),
                ),
                // If you plan to add social icons in card footer, keep spacing here.
                // const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Helper to carry icon + url if you later add social buttons in the dialog
class _SocialIconData {
  final IconData icon;
  final Color? color;
  final String url;
  _SocialIconData({required this.icon, required this.color, required this.url});
}
