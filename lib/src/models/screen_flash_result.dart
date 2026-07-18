/// Result of the screen-flash anti-spoofing test.
class ScreenFlashResult {
  /// Whether the test passed (face responded to screen illumination).
  final bool passed;

  /// Per-color luminance delta vs that color's OWN local baseline (keys:
  /// 'red', 'green', 'blue') — see [localBaselines]. Not a delta against one
  /// baseline taken once at the start: outdoor testing showed ambient light
  /// can drift by several luminance units within the ~2-3s the full flash
  /// sequence takes, which a single up-front baseline can't tell apart from
  /// an actual flash reflection.
  final Map<String, double> colorDeltas;

  /// Per-color local baseline — luminance sampled with no color overlay
  /// immediately before that color's own flash phase, not one shared
  /// baseline from the very start of the test. Keeps each delta comparison
  /// close in time to the ambient conditions it's measured against.
  final Map<String, double> localBaselines;

  /// Confidence that the response is genuine (0.0–1.0).
  final double confidence;

  /// Raw per-frame luminance samples behind each entry in [localBaselines] —
  /// for diagnostics only, e.g. to tell ambient drift (readings trending up
  /// or down across the phase) apart from a stable reading.
  final Map<String, List<double>> rawLocalBaselineReadings;

  /// Raw per-frame luminance samples per color phase (keys: 'red', 'green',
  /// 'blue') — for diagnostics only, e.g. to tell a noisy/unstable signal
  /// (large spread) apart from a consistently weak one.
  final Map<String, List<double>> rawColorReadings;

  /// Whether [CameraService.lockExposure] reported success before this test
  /// ran. `null` if unknown. `false` means AEC may have kept auto-adjusting
  /// during the flash sequence, which can produce unreliable/negative
  /// deltas on a genuine face — treat a failed test alongside
  /// `exposureLockSucceeded == false` as inconclusive, not confirmed spoof.
  final bool? exposureLockSucceeded;

  const ScreenFlashResult({
    required this.passed,
    required this.colorDeltas,
    required this.localBaselines,
    required this.confidence,
    this.rawLocalBaselineReadings = const {},
    this.rawColorReadings = const {},
    this.exposureLockSucceeded,
  });

  @override
  String toString() =>
      'ScreenFlashResult(passed: $passed, confidence: ${confidence.toStringAsFixed(2)}, deltas: $colorDeltas, localBaselines: $localBaselines)';
}
