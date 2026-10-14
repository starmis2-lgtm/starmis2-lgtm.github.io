import 'dart:math' as math;

import 'package:flutter/material.dart';

/// True while the app shows the dark theme (set by the MaterialApp builder).
bool darkUi = false;

/// Text / icon accent colour: as given in light mode, lifted so it reads on dark surfaces in dark mode.
Color ink(Color c) {
  if (!darkUi) return c;
  final h = HSLColor.fromColor(c);
  return h.withLightness(math.max(h.lightness, 0.74)).withSaturation(math.min(h.saturation, 0.85)).toColor();
}

/// Pale background tint: as given in light mode, a deep tint of the same hue in dark mode.
Color wash(Color c) {
  if (!darkUi) return c;
  final h = HSLColor.fromColor(c);
  return h.withLightness(0.16).withSaturation(math.min(h.saturation, 0.42)).toColor();
}

/// Pale border colour: as given in light mode, a muted line of the same hue in dark mode.
Color edge(Color c) {
  if (!darkUi) return c;
  final h = HSLColor.fromColor(c);
  return h.withLightness(0.30).withSaturation(math.min(h.saturation, 0.40)).toColor();
}
