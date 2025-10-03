import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../routes/app_routes.dart';
import 'package:flutter/services.dart';

class OnBoardingScreen extends StatefulWidget {
  const OnBoardingScreen({super.key});

  @override
  State<OnBoardingScreen> createState() => _OnBoardingScreenState();
}

class _OnBoardingScreenState extends State<OnBoardingScreen> {
  final introKey = GlobalKey<IntroductionScreenState>();

  Future<void> _onIntroEnd() async {
    if (!FORCE_SHOW_ONBOARDING) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_seen', true);
    }
    if (!mounted) return;

    if (FORCE_SHOW_LOGIN) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoutes.main);
    }
  }

  // Helper to build images from assets
  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('assets/images/robots/$assetName', width: width);
  }

  @override
  Widget build(BuildContext context) {
    // Status bar style
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.blue.shade600,
      statusBarIconBrightness: Brightness.light,
    ));

    // Force white text (title + body)
    const titleStyle = TextStyle(
      fontSize: 28.0,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    const bodyStyle = TextStyle(
      fontSize: 19.0,
      color: Colors.white,
    );

    const pageDecoration = PageDecoration(
      titleTextStyle: titleStyle,
      bodyTextStyle: bodyStyle,
      bodyAlignment: Alignment.center,
      imageAlignment: Alignment.topCenter,
      bodyPadding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
      imagePadding: EdgeInsets.only(top: 60.0, bottom: 0.0),
      contentMargin: EdgeInsets.zero,
      pageColor: Colors.transparent,
    );

    return SafeArea( // <-- wrap instead of isTopSafeArea/isBottomSafeArea
      top: true,
      bottom: true,
      child: IntroductionScreen(
        key: introKey,
        globalBackgroundColor: Colors.blue.shade400,
        allowImplicitScrolling: true,

        // Ease layout pressure at bottom
        controlsMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        controlsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

        // Footer CTA
        globalFooter: SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _onIntroEnd,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: const Text(
              'Let\'s explore the earth!',
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),

        // Slides
        pages: [
PageViewModel(
  title: "what is this?",
  body:
      "An introduction to climate and air pollution, highlighting air-quality forecasts, global warming trends, greenhouse-gas emissions, and health impacts — showing how the planet is changing.",
  image: _buildImage('1.webp'),
  decoration: pageDecoration,
),

          PageViewModel(
            title: "AQ Map",
            body:
                "Air pollution affects millions every day. In North America, view forecasts powered by satellites, ground stations, and weather models — see how pollution spreads in the air you breathe.",
            image: _buildImage('2.webp'),
            decoration: pageDecoration,
          ),
          PageViewModel(
            title: "Heat Map (1950–2100)",
            body:
                "See how temperatures have shifted in every country from 1950 to 2100. Compare historic records with future projections and understand the climate risks ahead.",
            image: _buildImage('3.webp'),
            decoration: pageDecoration,
          ),
          PageViewModel(
            title: "GHG Map (1850–2023)",
            body:
                "Explore global greenhouse-gas emissions from 1850 to today. Track CO₂, methane, and more to learn how nations contribute to warming — and how the world has changed.",
            image: _buildImage('4.webp'),
            decoration: pageDecoration,
          ),
          PageViewModel(
            title: "Health Advisor",
            body:
                "Air pollution is not just numbers — it impacts your health. Add your North American locations and health conditions, and get alerts when polluted air puts you at higher risk.",
            image: _buildImage('5.webp'),
            decoration: pageDecoration,
          ),
        ],

        onDone: _onIntroEnd,
        onSkip: _onIntroEnd,
        showSkipButton: true,

        skip: const Text('Skip',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        next: const Icon(Icons.arrow_forward, color: Colors.white),
        done: const Text('Done',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),

        // Smaller dots to avoid overflow on narrow widths
        dotsDecorator: DotsDecorator(
          size: const Size(8.0, 8.0),
          activeSize: const Size(16.0, 8.0),
          spacing: const EdgeInsets.symmetric(horizontal: 4.0),
          color: Colors.white54,
          activeColor: Colors.white,
          activeShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25.0),
          ),
        ),
      ),
    );
  }
}
