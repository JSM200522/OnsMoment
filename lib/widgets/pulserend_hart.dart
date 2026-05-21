import 'dart:math';
import 'package:flutter/material.dart';

/// Continu pulserend hart-emoji (scale 1.0 -> 1.1 -> 1.0, herhaalt).
/// Gebruikt in de "Stuur een hartje"-knop en in de ontvanger-popup.
class PulserendHart extends StatefulWidget {
  final double grootte;
  const PulserendHart({super.key, this.grootte = 48});

  @override
  State<PulserendHart> createState() => _PulserendHartState();
}

class _PulserendHartState extends State<PulserendHart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800))
    ..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.1)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Text('💕', style: TextStyle(fontSize: widget.grootte)),
    );
  }
}

/// Laat losse hartjes vanaf onderen omhoog zweven en faden. Self-contained:
/// wordt via een Overlay getoond en ruimt zichzelf op na de animatie.
void toonZwevendeHartjes(BuildContext context) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _HartjesRegen(onKlaar: entry.remove),
  );
  overlay.insert(entry);
}

class _HartjesRegen extends StatefulWidget {
  final VoidCallback onKlaar;
  const _HartjesRegen({required this.onKlaar});

  @override
  State<_HartjesRegen> createState() => _HartjesRegenState();
}

class _HartjesRegenState extends State<_HartjesRegen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  final _rng = Random();
  late final List<_Hartje> _hartjes;

  @override
  void initState() {
    super.initState();
    _hartjes = List.generate(5, (i) => _Hartje(
          xFractie: 0.15 + _rng.nextDouble() * 0.7,
          vertraging: _rng.nextDouble() * 0.3,
          grootte: 26.0 + _rng.nextDouble() * 22.0,
        ));
    _ctrl.forward().whenComplete(widget.onKlaar);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Stack(children: _hartjes.map((h) {
          // Voortgang met vertraging, geclampt tussen 0 en 1.
          final t = ((_ctrl.value - h.vertraging) / (1 - h.vertraging))
              .clamp(0.0, 1.0);
          final top = size.height * (0.78 - 0.55 * t);
          final left = size.width * h.xFractie;
          final opacity = (t < 0.15 ? t / 0.15 : 1 - t).clamp(0.0, 1.0);
          return Positioned(
            left: left,
            top: top,
            child: Opacity(
              opacity: opacity,
              child: Text('💕', style: TextStyle(fontSize: h.grootte)),
            ),
          );
        }).toList()),
      ),
    );
  }
}

class _Hartje {
  final double xFractie, vertraging, grootte;
  _Hartje({required this.xFractie, required this.vertraging,
      required this.grootte});
}
