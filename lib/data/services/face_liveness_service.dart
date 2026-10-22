import 'dart:math' as math;

import 'face_capture_processor.dart';

enum FaceLivenessChallengeType {
  blink,
  turnLeft,
  turnRight,
}

class FaceLivenessChallenge {
  FaceLivenessChallenge(this.type);
  final FaceLivenessChallengeType type;

  // Multi-phase state for blink detection
  bool _eyesWereOpen = false;
  bool _eyesWereClosed = false;
  bool _completed = false;

  bool get isCompleted => _completed;

  String get id => switch (type) {
    FaceLivenessChallengeType.blink => 'BLINK',
    FaceLivenessChallengeType.turnLeft => 'TURN_LEFT',
    FaceLivenessChallengeType.turnRight => 'TURN_RIGHT',
  };

  String get promptTitle => switch (type) {
    FaceLivenessChallengeType.blink => 'Blink Both Eyes',
    FaceLivenessChallengeType.turnLeft => 'Turn Head Left',
    FaceLivenessChallengeType.turnRight => 'Turn Head Right',
  };

  String get instruction => switch (type) {
    FaceLivenessChallengeType.blink => 'Please blink both eyes naturally',
    FaceLivenessChallengeType.turnLeft => 'Slowly turn your head to your left',
    FaceLivenessChallengeType.turnRight => 'Slowly turn your head to your right',
  };

  void reset() {
    _eyesWereOpen = false;
    _eyesWereClosed = false;
    _completed = false;
  }

  /// Updates state with current frame assessment and returns true if completed on this frame.
  bool update(FaceCaptureAssessment assessment) {
    if (_completed) return true;
    if (!assessment.faceDetected) return false;

    switch (type) {
      case FaceLivenessChallengeType.turnLeft:
        // Positive yaw indicates turned towards subject's left / camera's right
        if (assessment.yaw > 16.0) {
          _completed = true;
          return true;
        }
        break;

      case FaceLivenessChallengeType.turnRight:
        // Negative yaw indicates turned towards subject's right / camera's left
        if (assessment.yaw < -16.0) {
          _completed = true;
          return true;
        }
        break;

      case FaceLivenessChallengeType.blink:
        final left = assessment.leftEyeOpenProbability;
        final right = assessment.rightEyeOpenProbability;
        if (left == null || right == null) return false;

        // Phase 1: Eyes clearly open (> 0.65)
        if (!_eyesWereOpen && left > 0.65 && right > 0.65) {
          _eyesWereOpen = true;
        }
        // Phase 2: Eyes closed (< 0.25 on either eye) after having been open
        else if (_eyesWereOpen && !_eyesWereClosed && (left < 0.25 || right < 0.25)) {
          _eyesWereClosed = true;
        }
        // Phase 3: Eyes reopened (> 0.65) after closing
        else if (_eyesWereClosed && left > 0.65 && right > 0.65) {
          _completed = true;
          return true;
        }
        break;
    }
    return false;
  }
}

class FaceLivenessResult {
  const FaceLivenessResult({
    required this.passed,
    required this.completedChallenges,
    required this.durationMs,
    this.failureReason,
    this.securityNote = FaceLivenessSession.securityDisclaimer,
  });

  final bool passed;
  final List<String> completedChallenges;
  final int durationMs;
  final String? failureReason;
  final String securityNote;
}

class FaceLivenessSession {
  FaceLivenessSession({
    required this.challenges,
    this.timeLimitPerChallengeSeconds = 7,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _startTime = (clock ?? DateTime.now)(),
        _challengeStartTime = (clock ?? DateTime.now)();

  final List<FaceLivenessChallenge> challenges;
  final int timeLimitPerChallengeSeconds;
  final DateTime Function() _clock;

  int _currentIndex = 0;
  final DateTime _startTime;
  DateTime _challengeStartTime;
  final List<String> _completedIds = [];
  bool _isCompleted = false;
  bool _isFailed = false;
  String? _failureReason;

  static const String securityDisclaimer =
      'These challenges reduce simple photo attacks but are not reliable protection against replay videos or sophisticated spoofing.';

  int get currentIndex => _currentIndex;
  int get totalChallenges => challenges.length;
  bool get isCompleted => _isCompleted;
  bool get isFailed => _isFailed;
  String? get failureReason => _failureReason;
  List<String> get completedChallengeIds => List.unmodifiable(_completedIds);

  FaceLivenessChallenge? get activeChallenge =>
      _currentIndex < challenges.length ? challenges[_currentIndex] : null;

  int remainingSeconds() {
    if (_isCompleted || _isFailed) return 0;
    final elapsed = _clock().difference(_challengeStartTime).inSeconds;
    return math.max(0, timeLimitPerChallengeSeconds - elapsed);
  }

  /// Processes a single frame and checks if the challenge advances or times out.
  void processFrame(FaceCaptureAssessment assessment) {
    if (_isCompleted || _isFailed) return;

    final now = _clock();
    // 1. Check time limit
    if (now.difference(_challengeStartTime).inSeconds >= timeLimitPerChallengeSeconds) {
      _isFailed = true;
      _failureReason = 'Liveness challenge timed out. Follow the visual prompts promptly.';
      return;
    }

    final current = activeChallenge;
    if (current == null) {
      _isCompleted = true;
      return;
    }

    // 2. Update challenge state
    final passed = current.update(assessment);
    if (passed) {
      _completedIds.add(current.id);
      _currentIndex++;
      _challengeStartTime = _clock();
      if (_currentIndex >= challenges.length) {
        _isCompleted = true;
      }
    }
  }

  FaceLivenessResult toResult() {
    final now = _clock();
    return FaceLivenessResult(
      passed: _isCompleted && !_isFailed,
      completedChallenges: _completedIds,
      durationMs: now.difference(_startTime).inMilliseconds,
      failureReason: _failureReason,
    );
  }

  /// Factory to generate a randomized sequence of challenges (1 or 2 challenges).
  static FaceLivenessSession createRandom({
    int count = 2,
    int timeLimitPerChallenge = 7,
    math.Random? random,
    DateTime Function()? clock,
  }) {
    final rand = random ?? math.Random();
    final allTypes = [
      FaceLivenessChallengeType.turnLeft,
      FaceLivenessChallengeType.turnRight,
      FaceLivenessChallengeType.blink,
    ];
    allTypes.shuffle(rand);
    final chosen = allTypes.take(count.clamp(1, 3)).map(FaceLivenessChallenge.new).toList();
    return FaceLivenessSession(
      challenges: chosen,
      timeLimitPerChallengeSeconds: timeLimitPerChallenge,
      clock: clock,
    );
  }
}
