import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class InternetFloatingButton extends StatelessWidget {
  const InternetFloatingButton({super.key});

  static const double horizontalMargin = 20;
  static const double buttonBottomMargin = 180;
  static const double iconButtonSize = 60;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectivityResult>(
      stream: Connectivity().onConnectivityChanged,
      initialData: ConnectivityResult.wifi,
      builder: (context, snapshot) {
        final offline = snapshot.data == ConnectivityResult.none;
        if (!offline) return const SizedBox.shrink();

        return Positioned(
          left: horizontalMargin,
          bottom: buttonBottomMargin,
          child: GestureDetector(
            onTap: () {
              _showAnimatedSnackBar(context);
            },
            child: Container(
              width: iconButtonSize,
              height: iconButtonSize,
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(160),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withAlpha(60),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: const Center(
                child: Icon(Icons.wifi_off, color: Colors.white, size: 34),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAnimatedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 6,
        backgroundColor: Colors.redAccent.withAlpha(190),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(
          bottom: 40,
          left: horizontalMargin,
          right: horizontalMargin,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
        content: Row(
          children: const [
            Icon(Icons.wifi_off, color: Colors.white, size: 28),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'No internet connection!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
