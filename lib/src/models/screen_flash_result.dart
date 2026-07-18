/// Result of the screen-flash anti-spoofing test.
class ScreenFlashResult {
  /// Whether the test passed (face responded to screen illumination).
  final bool passed;

  /// Per-color luminance delta vs baseline (keys: 'red', 'green', 'blue').
  final Map<String, double> colorDeltas;

  /// Average face luminance captured before any flash.
  final double baselineLuminance;

  /// Confidence that the response is genuine (0.0–1.0).
  final double confidence;

  /// Raw per-frame luminance samples captured during the baseline phase —
  /// for diagnostics only (see [colorDeltas]/[baselineLuminance], which are
  /// already the mean of these).
  final List<double> rawBaselineReadings;

  /// Raw per-frame luminance samples per color phase (keys: 'red', 'green',
  /// 'blue') — for diagnostics only, e.g. to tell a noisy/unstable signal
  /// (large spread) apart from a consistently weak one.
  final Map<String, List<double>> rawFlashReadings;

  /// Whether [CameraService.lockExposure] reported success before this test
  /// ran. `null` if unknown. `false` means AEC may have kept auto-adjusting
  /// during the flash sequence, which can produce unreliable/negative
  /// deltas on a genuine face — treat a failed test alongside
  /// `exposureLockSucceeded == false` as inconclusive, not confirmed spoof.
  final bool? exposureLockSucceeded;

  const ScreenFlashResult({
    required this.passed,
    required this.colorDeltas,
    required this.baselineLuminance,
    required this.confidence,
    this.rawBaselineReadings = const [],
    this.rawFlashReadings = const {},
    this.exposureLockSucceeded,
  });

  @override
  String toString() =>
      'ScreenFlashResult(passed: $passed, confidence: ${confidence.toStringAsFixed(2)}, deltas: $colorDeltas)';
}
