import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/kleuren.dart';

/// Primaire actieknop: volle breedte, peach→rose gradient, 56px hoog.
/// Geeft lichte press-animatie en haptische feedback. onTap == null of
/// bezig == true → uitgeschakeld (50% opacity, geen tap).
class OWKnop extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool bezig;
  final IconData? icoon;

  const OWKnop({
    super.key,
    required this.label,
    this.onTap,
    this.bezig = false,
    this.icoon,
  });

  @override
  State<OWKnop> createState() => _OWKnopState();
}

class _OWKnopState extends State<OWKnop> {
  bool _ingedrukt = false;

  bool get _actief => widget.onTap != null && !widget.bezig;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _actief ? (_) => setState(() => _ingedrukt = true) : null,
      onTapUp: _actief ? (_) => setState(() => _ingedrukt = false) : null,
      onTapCancel: _actief ? () => setState(() => _ingedrukt = false) : null,
      onTap: _actief
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _ingedrukt ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Opacity(
          opacity: _actief ? 1.0 : 0.5,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPeach, kRose]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: kPeach.withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: widget.bezig
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: kWhite, strokeWidth: 3),
                        ),
                        SizedBox(width: 12),
                        Text('Bezig…',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: kWhite)),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icoon != null) ...[
                          Icon(widget.icoon, color: kWhite, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Text(widget.label,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: kWhite)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secundaire knop: wit met peach-rand, zelfde afmetingen als OWKnop.
class OWKnopSecundair extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icoon;

  const OWKnopSecundair({
    super.key,
    required this.label,
    this.onTap,
    this.icoon,
  });

  @override
  State<OWKnopSecundair> createState() => _OWKnopSecundairState();
}

class _OWKnopSecundairState extends State<OWKnopSecundair> {
  bool _ingedrukt = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _ingedrukt = true),
      onTapUp: (_) => setState(() => _ingedrukt = false),
      onTapCancel: () => setState(() => _ingedrukt = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _ingedrukt ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: kWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPeach, width: 2),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icoon != null) ...[
                  Icon(widget.icoon, color: kPeach, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(widget.label,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kPeach)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
