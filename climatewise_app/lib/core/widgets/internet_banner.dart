import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// InternetBanner
///
/// A wrapper widget that listens to network connectivity changes
/// and overlays a banner message when the device is offline.
///
/// - Uses [connectivity_plus] to detect connectivity state.
/// - Displays a red banner at the top of the screen when offline.
/// - Ensures banner is placed above content using a [Stack].
class InternetBanner extends StatelessWidget {
  final Widget child;

  const InternetBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectivityResult>(
      stream: Connectivity().onConnectivityChanged,
      initialData: ConnectivityResult.wifi,
      builder: (context, snapshot) {
        final offline = (snapshot.data == ConnectivityResult.none);
        return Stack(
          children: [
            child,
            if (offline)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Colors.redAccent.withAlpha(250), // slightly transparent background
                  elevation: 6,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 20,
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.wifi_off, color: Colors.white, size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No Internet Connection! Please check your connection.',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
