import 'package:flutter/material.dart';

// app_box brand colours — the accent is the logo's anchor purple (#4E28D5).
// The branding generator (stacked_kit/branding) reads kcPrimaryColor as the
// seed for the generated brand ramp; do NOT hand-edit generated/brand_colors.dart.
const Color kcPrimaryColor = Color(0xFF4E28D5);
const Color kcPrimaryColorDark = Color(0xFF2A1A6B);
const Color kcBlack = Color(0xFF000000);
const Color kcDarkGreyColor = Color(0xFF1A1B1E);
const Color kcMediumGrey = Color(0xFF474A54);
const Color kcLightGrey = Color.fromARGB(255, 187, 187, 187);
const Color kcVeryLightGrey = Color(0xFFE3E3E3);
const Color kcWhite = Color(0xFFFFFFFF);
const Color kcSoftYellow = Color(0xFFF6E7B0);
const Color kcBackgroundColor = kcDarkGreyColor;

// Gate signal — the design brief's signature orange for the three human gates
// (brief §3, non-negotiable #4: gates must be visually unmistakable). Distinct
// from the brand accent so a gate never reads as ordinary chrome.
const Color kcGateColor = Color(0xFFD2522B);
const Color kcGateColorDark = Color(0xFFB8431F);
