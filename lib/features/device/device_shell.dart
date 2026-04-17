import 'package:flutter/material.dart';

/// DeviceShell — fits its child into the inscribed circle of the screen,
/// black-masking the corners so a round display shows nothing outside the
/// circle. Sized for the 800x800 / 3.4" Waveshare class screen but adapts.
class DeviceShell extends StatelessWidget {
  final Widget child;
  const DeviceShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final d = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
            return Center(
              child: SizedBox(
                width: d,
                height: d,
                child: ClipOval(child: child),
              ),
            );
          },
        ),
      ),
    );
  }
}
