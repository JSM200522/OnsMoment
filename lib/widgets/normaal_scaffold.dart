import 'package:flutter/material.dart';

/// Gedeelde Scaffold-wrapper voor 'gewone' content-schermen (Category 1).
///
/// Voegt automatisch de juiste SafeArea toe:
/// - Zonder AppBar: SafeArea(top:true) — statusbalk EN navigatiebalk afgedekt.
/// - Met AppBar: SafeArea(top:false) — Scaffold+AppBar verwerkt de statusbalk
///   al zelf; alleen de navigatiebalk wordt hier afgedekt.
///
/// Full-bleed schermen (videogesprek, tablet-kiosk, popup-overlays) gebruiken
/// NIET deze wrapper; die zijn bewust Category 2 met eigen Stack-layout.
class NormaalScaffold extends StatelessWidget {
  const NormaalScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backgroundColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color? backgroundColor;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: SafeArea(
        top: appBar == null,
        child: body,
      ),
    );
  }
}
