import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/face_capture_processor.dart';
import 'package:testflutter/data/services/face_liveness_service.dart';

void main() {
  FaceCaptureAssessment makeAssessment({
    bool faceDetected = true,
    double yaw = 0.0,
    double pitch = 0.0,
    double roll = 0.0,
    double? leftEye,
    double? rightEye,
  }) {
    return FaceCaptureAssessment(
      faceDetected ? 'Face detected' : 'No face',
      faceDetected: faceDetected,
      pitch: pitch,
      yaw: yaw,
      roll: roll,
      leftEyeOpenProbability: leftEye,
      rightEyeOpenProbability: rightEye,
    );
  }

  group('FaceLivenessChallenge - Turn Left & Right', () {
    test('turnLeft completes only when yaw exceeds 16 degrees', () {
      final challenge = FaceLivenessChallenge(FaceLivenessChallengeType.turnLeft);

      // Facing straight
      expect(challenge.update(makeAssessment(yaw: 2.0)), isFalse);
      expect(challenge.isCompleted, isFalse);

      // Slight angle (< 16)
      expect(challenge.update(makeAssessment(yaw: 12.0)), isFalse);
      expect(challenge.isCompleted, isFalse);

      // Turn left (> 16)
      expect(challenge.update(makeAssessment(yaw: 18.5)), isTrue);
      expect(challenge.isCompleted, isTrue);
    });

    test('turnRight completes only when yaw is below -16 degrees', () {
      final challenge = FaceLivenessChallenge(FaceLivenessChallengeType.turnRight);

      // Facing straight
      expect(challenge.update(makeAssessment(yaw: 0.0)), isFalse);
      expect(challenge.isCompleted, isFalse);

      // Slight angle (> -16)
      expect(challenge.update(makeAssessment(yaw: -10.0)), isFalse);
      expect(challenge.isCompleted, isFalse);

      // Turn right (< -16)
      expect(challenge.update(makeAssessment(yaw: -21.0)), isTrue);
      expect(challenge.isCompleted, isTrue);
    });
  });

  group('FaceLivenessChallenge - Blink State Machine', () {
    test('blink challenge completes full 3-phase cycle (open -> closed -> open)', () {
      final challenge = FaceLivenessChallenge(FaceLivenessChallengeType.blink);

      // Phase 1: Eyes open (> 0.65)
      expect(challenge.update(makeAssessment(leftEye: 0.85, rightEye: 0.90)), isFalse);
      expect(challenge.isCompleted, isFalse);

      // Phase 2: Eyes closed (< 0.25)
      expect(challenge.update(makeAssessment(leftEye: 0.10, rightEye: 0.15)), isFalse);
      expect(challenge.isCompleted, isFalse);

      // Phase 3: Eyes reopened (> 0.65)
      expect(challenge.update(makeAssessment(leftEye: 0.88, rightEye: 0.82)), isTrue);
      expect(challenge.isCompleted, isTrue);
    });

    test('blink challenge does not complete without eye closure', () {
      final challenge = FaceLivenessChallenge(FaceLivenessChallengeType.blink);

      // Always open
      challenge.update(makeAssessment(leftEye: 0.9, rightEye: 0.9));
      challenge.update(makeAssessment(leftEye: 0.7, rightEye: 0.7));
      challenge.update(makeAssessment(leftEye: 0.85, rightEye: 0.85));

      expect(challenge.isCompleted, isFalse);
    });

    test('blink challenge does not complete if eyes remain closed', () {
      final challenge = FaceLivenessChallenge(FaceLivenessChallengeType.blink);

      // Open then closed
      challenge.update(makeAssessment(leftEye: 0.9, rightEye: 0.9));
      challenge.update(makeAssessment(leftEye: 0.05, rightEye: 0.05));
      challenge.update(makeAssessment(leftEye: 0.1, rightEye: 0.1));

      expect(challenge.isCompleted, isFalse);
    });
  });

  group('FaceLivenessSession - Multi-Challenge Progression & Timeout', () {
    test('progresses through sequential challenges until completion', () {
      var currentTime = DateTime.utc(2026, 10, 22, 10, 0, 0);
      final challenges = [
        FaceLivenessChallenge(FaceLivenessChallengeType.turnLeft),
        FaceLivenessChallenge(FaceLivenessChallengeType.turnRight),
      ];

      final session = FaceLivenessSession(
        challenges: challenges,
        timeLimitPerChallengeSeconds: 7,
        clock: () => currentTime,
      );

      expect(session.currentIndex, equals(0));
      expect(session.activeChallenge?.id, equals('TURN_LEFT'));

      // Complete challenge 1: Turn Left
      session.processFrame(makeAssessment(yaw: 22.0));
      expect(session.currentIndex, equals(1));
      expect(session.activeChallenge?.id, equals('TURN_RIGHT'));
      expect(session.completedChallengeIds, contains('TURN_LEFT'));
      expect(session.isCompleted, isFalse);

      // Complete challenge 2: Turn Right
      session.processFrame(makeAssessment(yaw: -20.0));
      expect(session.isCompleted, isTrue);
      expect(session.isFailed, isFalse);
      expect(session.completedChallengeIds, equals(['TURN_LEFT', 'TURN_RIGHT']));

      final result = session.toResult();
      expect(result.passed, isTrue);
      expect(result.completedChallenges, equals(['TURN_LEFT', 'TURN_RIGHT']));
      expect(result.securityNote, contains('not reliable protection against replay videos'));
    });

    test('session fails when time limit per challenge expires', () {
      var currentTime = DateTime.utc(2026, 10, 22, 10, 0, 0);
      final session = FaceLivenessSession(
        challenges: [FaceLivenessChallenge(FaceLivenessChallengeType.turnLeft)],
        timeLimitPerChallengeSeconds: 6,
        clock: () => currentTime,
      );

      // 3 seconds in: not timed out
      currentTime = currentTime.add(const Duration(seconds: 3));
      session.processFrame(makeAssessment(yaw: 0.0));
      expect(session.isFailed, isFalse);

      // 7 seconds in: timed out (>= 6s limit)
      currentTime = currentTime.add(const Duration(seconds: 4));
      session.processFrame(makeAssessment(yaw: 0.0));
      expect(session.isFailed, isTrue);
      expect(session.failureReason, contains('timed out'));

      final result = session.toResult();
      expect(result.passed, isFalse);
      expect(result.failureReason, contains('timed out'));
    });

    test('createRandom produces randomized challenges within requested bounds', () {
      final session = FaceLivenessSession.createRandom(count: 2);
      expect(session.totalChallenges, equals(2));
      expect(session.challenges.length, equals(2));
      expect(session.challenges[0].id, isNotEmpty);
      expect(session.challenges[1].id, isNotEmpty);
    });
  });
}
