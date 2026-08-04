import 'package:flutter/material.dart';

const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kCream      = Color(0xFFFFFAF7);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kBrownLight = Color(0xFF8B6354);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);
const Color kGreen      = Color(0xFF4CAF82);
const Color kBlue       = Color(0xFF4A90E2);
const Color kRood       = Color(0xFFE74C3C);

// Warme kaartvlak-kleur — iets warmer dan zuiver wit, koeler dan kCream.
// Gebruik als achtergrond voor kaarten, tegels en invoervelden.
const Color kCard = Color(0xFFFFFBF8);

// Zachte kaartschaduw — warm bruin, ~7% opacity. Geeft kaarten lichte diepte
// zonder harde randen. Gebruik als [kCardShadow] in boxShadow.
const BoxShadow kCardShadow = BoxShadow(
  color: Color(0x12C27B4E),
  blurRadius: 14,
  offset: Offset(0, 4),
);

// Peach-schaduw voor actieve / geselecteerde interactieve elementen.
// Gebruik als [kPeachShadow] in boxShadow.
const BoxShadow kPeachShadow = BoxShadow(
  color: Color(0x3DFF9B71),
  blurRadius: 18,
  offset: Offset(0, 6),
);
