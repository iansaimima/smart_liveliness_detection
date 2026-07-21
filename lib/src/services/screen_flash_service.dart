import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../config/screen_flash_config.dart';
import '../models/screen_flash_result.dart';

enum ScreenFlashPhase { idle, running, done }

/// Sub-step within a single color's cycle. Each color gets its OWN local
/// baseline sampled immediately before its flash, instead of every color
/// being compared against one baseline taken once at the very start of the
/// test — outdoor testing showed ambient light can drift by several
/// luminance units over the ~2-3s the full red→green→blue sequence used to
/// take, which a single up-front baseline can't tell apart from an actual
/// flash reflection (the color sampled last ends up systematically
/// disadvantaged vs the one sampled first).
enum _SubPhase { neutralWarmup, neutralSample, colorWarmup, colorSample }

const List<String> _kColors = ['red', 'green', 'blue'];

const Map<String, Color> _kOverlayColors = {
  'red': Color(0xFFFF0000),
  'green': Color(0xFF00FF00),
  'blue': Color(0xFF0000FF),
};

/// Manages the screen-flash anti-spoofing test state machine.
///
/// Call [start] once to begin, then pass every face-detected camera frame to
/// [processFrame]. When the test is complete, [processFrame] returns a
/// [ScreenFlashResult]; until then it returns `null`.
///
/// Expose [activeFlashColor] to the UI so the correct colored overlay is shown
/// on screen during each phase.
class ScreenFlashService {
  final ScreenFlashConfig config;

  ScreenFlashPhase _phase = ScreenFlashPhase.idle;
  _SubPhase _subPhase = _SubPhase.neutralSample;
  int _colorIndex = 0;
  int _frameCounter = 0;

  /// Drives the neutralWarmup/colorWarmup sub-phases, which wait on elapsed
  /// wall-clock time rather than a frame count (see [ScreenFlashConfig.warmupDuration]).
  final Stopwatch _warmupTimer = Stopwatch();

  final Map<String, List<double>> _localBaselineReadings = {
    for (final c in _kColors) c: <double>[],
  };
  final Map<String, List<double>> _colorReadings = {
    for (final c in _kColors) c: <double>[],
  };

  /// Set by the caller once [CameraService.lockExposure] resolves — surfaced
  /// in the result for diagnostics (see [ScreenFlashResult.exposureLockSucceeded]).
  bool? exposureLockSucceeded;

  ScreenFlashService({required this.config});

  ScreenFlashPhase get phase => _phase;

  /// Color that should be shown as a full-screen overlay right now.
  /// `null` means no overlay (neutral/baseline sampling, warmup between
  /// colors, or idle/done).
  Color? get activeFlashColor {
    // _subPhase/_colorIndex aren't reset when the test completes (they stay
    // parked on the last color sampled, e.g. blue) — _phase is the only
    // signal that the test is actually still running. Without this check,
    // the overlay from the last color stays on screen through the entire
    // challenge stage instead of clearing once screenFlashTest finishes.
    if (_phase != ScreenFlashPhase.running) return null;
    if (_subPhase == _SubPhase.colorWarmup || _subPhase == _SubPhase.colorSample) {
      return _kOverlayColors[_kColors[_colorIndex]];
    }
    return null;
  }

  bool get isRunning => _phase == ScreenFlashPhase.running;

  void start() {
    _phase = ScreenFlashPhase.running;
    _colorIndex = 0;
    // No warmup before the very first local baseline: the screen is already
    // showing no color overlay coming into this (matches the old behaviour,
    // where the initial baseline phase had no warmup either). Every
    // subsequent color's local baseline DOES get a neutralWarmup first,
    // since it follows straight after the previous color's overlay.
    _subPhase = _SubPhase.neutralSample;
    _frameCounter = 0;
    _warmupTimer
      ..stop()
      ..reset();
    for (final c in _kColors) {
      _localBaselineReadings[c]!.clear();
      _colorReadings[c]!.clear();
    }
    exposureLockSucceeded = null;
  }

  void reset() {
    _phase = ScreenFlashPhase.idle;
    _subPhase = _SubPhase.neutralSample;
    _colorIndex = 0;
    _frameCounter = 0;
    _warmupTimer
      ..stop()
      ..reset();
    for (final c in _kColors) {
      _localBaselineReadings[c]!.clear();
      _colorReadings[c]!.clear();
    }
    exposureLockSucceeded = null;
  }

  /// Process one camera frame. Returns [ScreenFlashResult] when all phases
  /// are complete, otherwise `null`.
  ScreenFlashResult? processFrame(Face face, CameraImage image) {
    if (_phase != ScreenFlashPhase.running) return null;

    final lum = _sampleFaceLuminance(image, face.boundingBox);
    final color = _kColors[_colorIndex];

    switch (_subPhase) {
      case _SubPhase.neutralWarmup:
        if (!_warmupTimer.isRunning) _warmupTimer.start();
        if (_warmupTimer.elapsed >= config.neutralSettleDuration) {
          _warmupTimer
            ..stop()
            ..reset();
          _subPhase = _SubPhase.neutralSample;
          _frameCounter = 0;
        }

      case _SubPhase.neutralSample:
        _localBaselineReadings[color]!.add(lum);
        _frameCounter++;
        if (_frameCounter >= config.baselineFrames) {
          _subPhase = _SubPhase.colorWarmup;
          _frameCounter = 0;
        }

      case _SubPhase.colorWarmup:
        if (!_warmupTimer.isRunning) _warmupTimer.start();
        if (_warmupTimer.elapsed >= config.warmupDuration) {
          _warmupTimer
            ..stop()
            ..reset();
          _subPhase = _SubPhase.colorSample;
          _frameCounter = 0;
        }

      case _SubPhase.colorSample:
        _colorReadings[color]!.add(lum);
        _frameCounter++;
        if (_frameCounter >= config.framesPerColor) {
          if (_colorIndex < _kColors.length - 1) {
            _colorIndex++;
            _subPhase = _SubPhase.neutralWarmup;
            _frameCounter = 0;
          } else {
            _phase = ScreenFlashPhase.done;
            return _buildResult();
          }
        }
    }
    return null;
  }

  ScreenFlashResult _buildResult() {
    final localBaselines = <String, double>{};
    final deltas = <String, double>{};
    for (final color in _kColors) {
      final baseline = _mean(_localBaselineReadings[color]!);
      localBaselines[color] = baseline;
      deltas[color] = _mean(_colorReadings[color]!) - baseline;
    }

    // Pass if ≥ 2 colors show a positive delta above threshold, each
    // measured against its OWN local baseline (see [_SubPhase] doc).
    final passingColors =
        deltas.values.where((d) => d >= config.reflectionThreshold).length;
    final passed = passingColors >= 2;

    // Confidence: average positive delta normalised to an expected max of 50
    final avgPositiveDelta =
        deltas.values.fold(0.0, (acc, d) => acc + d.clamp(0.0, 50.0)) / 3;
    final confidence = (avgPositiveDelta / 50.0).clamp(0.0, 1.0);

    return ScreenFlashResult(
      passed: passed,
      colorDeltas: deltas,
      localBaselines: localBaselines,
      confidence: confidence,
      rawLocalBaselineReadings: {
        for (final c in _kColors) c: List.unmodifiable(_localBaselineReadings[c]!),
      },
      rawColorReadings: {
        for (final c in _kColors) c: List.unmodifiable(_colorReadings[c]!),
      },
      exposureLockSucceeded: exposureLockSucceeded,
    );
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _sampleFaceLuminance(CameraImage image, Rect faceRect) {
    try {
      final x0 = faceRect.left.toInt().clamp(0, image.width - 1);
      final y0 = faceRect.top.toInt().clamp(0, image.height - 1);
      final x1 = faceRect.right.toInt().clamp(0, image.width);
      final y1 = faceRect.bottom.toInt().clamp(0, image.height);
      if (x1 <= x0 || y1 <= y0) return 0;

      final plane = image.planes[0];
      final bytes = plane.bytes;
      final bpr = plane.bytesPerRow;
      final isBGRA = image.format.group == ImageFormatGroup.bgra8888;
      const step = 6;

      double sum = 0;
      int count = 0;

      for (int y = y0; y < y1; y += step) {
        for (int x = x0; x < x1; x += step) {
          if (isBGRA) {
            final idx = y * bpr + x * 4;
            if (idx + 2 < bytes.length) {
              sum += 0.299 * bytes[idx + 2] +
                  0.587 * bytes[idx + 1] +
                  0.114 * bytes[idx];
              count++;
            }
          } else {
            final idx = y * bpr + x;
            if (idx < bytes.length) {
              sum += bytes[idx];
              count++;
            }
          }
        }
      }
      return count > 0 ? sum / count : 0;
    } catch (_) {
      return 0;
    }
  }
}
