import 'package:flutter/material.dart';
import '../theme/kleuren.dart';

/// Invoerveld met emoji-prefix, label boven het veld en focus-animatie.
/// Zelfde hoogte als OWKnop (56px invoergebied) voor consistente ritmiek.
/// Gebruik [fout] om een rode validatietekst onder het veld te tonen.
class OWInvoer extends StatefulWidget {
  final String emoji;
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool verborgen;
  final TextInputType toetsenbord;
  final TextCapitalization hoofdletters;
  final String? fout;

  const OWInvoer({
    super.key,
    required this.emoji,
    required this.label,
    required this.hint,
    required this.controller,
    this.verborgen = false,
    this.toetsenbord = TextInputType.text,
    this.hoofdletters = TextCapitalization.sentences,
    this.fout,
  });

  @override
  State<OWInvoer> createState() => _OWInvoerState();
}

class _OWInvoerState extends State<OWInvoer> {
  final _focus = FocusNode();
  bool _heeftFocus = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() => _heeftFocus = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heeftFout = widget.fout != null && widget.fout!.isNotEmpty;
    final randKleur = heeftFout
        ? kRood
        : (_heeftFocus ? kPeach : kPeachLight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kTextMuted,
                letterSpacing: 0.3)),
        const SizedBox(height: 5),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: randKleur, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 52,
                    color: kPeachPale,
                    alignment: Alignment.center,
                    child: Text(widget.emoji,
                        style: const TextStyle(fontSize: 20)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      obscureText: widget.verborgen,
                      keyboardType: widget.toetsenbord,
                      textCapitalization: widget.hoofdletters,
                      style: const TextStyle(
                          color: kBrown,
                          fontWeight: FontWeight.w700,
                          fontSize: 15),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: const TextStyle(
                            color: kPeachLight, fontSize: 14),
                        contentPadding:
                            const EdgeInsets.fromLTRB(14, 18, 16, 18),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (heeftFout) ...[
          const SizedBox(height: 4),
          Text(widget.fout!,
              style: const TextStyle(
                  fontSize: 12,
                  color: kRood,
                  fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}
