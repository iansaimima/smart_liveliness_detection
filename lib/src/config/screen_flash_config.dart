import 'package:flutter/material.dart';

/// Configuration for the Screen Flash anti-spoofing test.
///
/// When enabled, the screen briefly flashes red, green, and blue after the
/// face is centred. A real face reflects the light; a printed photo or
/// video replay does not respond with the expected brightness change.
class ScreenFlashConfig {
  /// Whether the screen-flash test is active.
  final bool enabled;

  /// Colors cycled during the flash test (in order).
  final List<Color> flashColors;

  /// Camera frames to capture per flash color (more = stabler reading).
  final int framesPerColor;

  /// Camera frames sampled with no color overlay, immediately before EACH
  /// color's own flash phase (establishes that color's local baseline
  /// luminance — see ScreenFlashService._SubPhase doc for why it's local
  /// per-color rather than one baseline shared by all colors).
  final int baselineFrames;

  /// Frames to skip at the start of each flash color phase while the camera
  /// and UI settle before sampling begins. Prevents reading AEC-transitioning
  /// frames that haven't stabilised yet.
  final int warmupFramesPerColor;

  /// Frames to skip when the screen returns to neutral (no overlay) right
  /// after a color phase, before sampling that neutral phase as the NEXT
  /// color's local baseline. Deliberately longer than [warmupFramesPerColor]:
  /// field testing showed a saturated full-screen flash can leave a brief
  /// afterglow (AWB/sensor settling) that, if the next local baseline is
  /// sampled too soon, inflates that baseline and makes the following
  /// color's delta look artificially negative even on a genuine face.
  final int neutralSettleFrames;

  /// Minimum luminance delta (0–255 scale) required per color to pass.
  /// Kept intentionally low because AEC partially offsets the flash; the test
  /// looks for any positive response, not the full flash magnitude.
  final double reflectionThreshold;

  /// When `true`, a failed flash test marks the session as spoofing detected.
  /// When `false`, the result is reported via callback but the session continues.
  final bool failSessionOnSpoofing;

  const ScreenFlashConfig({
    this.enabled = false,
    this.flashColors = const [
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
    ],
    this.framesPerColor = 5,
    this.baselineFrames = 3,
    this.warmupFramesPerColor = 2,
    this.neutralSettleFrames = 5,
    this.reflectionThreshold = 4.0,
    this.failSessionOnSpoofing = false,
  });
}
