import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(String file) =>
    jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final runbook = File(
    'docs/phase10j-production-deployment-runbook.md',
  ).readAsStringSync();
  final checklist = _json('docs/phase10j-go-no-go-checklist.json');
  final phase10i = _json('docs/phase10i-production-clone-rehearsal.json');
  final phase10ib = _json('docs/phase10ib-business-write-closure.json');
  final phase10f = _json('docs/phase10f-migration-approval-manifest.json');
  final phase10l = _json('docs/phase10l-legacy-retention-policy.json');
  final phase10o2 = _json('docs/phase10o2-deployment-authorization.json');
  final phase10e = File('phase10e.md').readAsStringSync();

  test('runbook expected counts match approved clone evidence', () {
    final release =
        phase10i['migrationAndImport'] as Map<String, dynamic>;
    final release4 = release['release4'] as Map<String, dynamic>;
    final invariants = release['invariants'] as Map<String, dynamic>;

    expect(release4['catalogueId'], 'PAINT_V1');
    expect(release4['catalogueVersion'], 4);
    expect(release4['schemaRevision'], 1);
    expect(release4['compilerRevision'], 6);
    expect(release4['candidateSelectors'], 137);
    expect(release4['resolvedSelectors'], 137);
    expect(release4['formsReadyAndValid'], 137);
    expect(invariants['productsPreserved'], 4);
    expect(invariants['variantsPreserved'], 7);
    expect(invariants['syncQueriesPreserved'], 195);
    expect(invariants['protectedQueriesPreserved'], 10);
    expect(release['legacyArchive']['rows'], 3903);
    expect(runbook, contains('137/137 forms READY'));
    expect(runbook, contains('195 sync queries'));
    expect(runbook, contains('3,903'));
  });

  test('Release 4 fingerprint agrees across evidence and checklist', () {
    final release4 =
        ((phase10i['migrationAndImport'] as Map<String, dynamic>)['release4'])
            as Map<String, dynamic>;
    final fingerprint =
        release4['installedLocalCatalogueFingerprint'] as String;
    final writeEvidence =
        phase10ib['release4'] as Map<String, dynamic>;
    final checklistRelease =
        checklist['releaseExpected'] as Map<String, dynamic>;

    expect(fingerprint, writeEvidence['fingerprint']);
    expect(fingerprint, checklistRelease['catalogueFingerprint']);
    expect(runbook, contains(fingerprint));
    expect(phase10e, contains('3f02fef8f5ce368757f28c0b64ab797f'));
  });

  test('O5 candidate packet preserves rollback and execution gates', () {
    final sections = (checklist['sections'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      sections.map((section) => section['id']).toSet(),
      {
        'code_readiness',
        'test_readiness',
        'backup_readiness',
        'database_preimage_readiness',
        'maintenance_mode_readiness',
        'release_artifact_readiness',
        'rollback_readiness',
        'operator_approval',
        'business_operator_approval',
      },
    );
    for (final section in sections) {
      final items = (section['items'] as List).cast<Map<String, dynamic>>();
      expect(items, isNotEmpty, reason: '${section['id']} has no gates');
      for (final item in items) {
        expect(item['mandatory'], isTrue);
        expect(item['answer'], anyOf('YES', 'NO'), reason: '${item['id']} must be explicit');
        expect(item.containsKey('evidence'), isTrue);
      }
    }
      expect(checklist['decision'], anyOf('STOP', 'DEPLOYMENT_CANDIDATE_READY'));
      expect(checklist['phase'], 'PHASE_10O5_IMMUTABLE_CANDIDATE_COMMIT_AND_POSTCOMMIT_FULL_SUITE');
      expect(checklist['status'], anyOf('STOP_CANDIDATE_COMMIT_AND_FULL_TESTS_PENDING', 'DEPLOYMENT_CANDIDATE_READY'));
      expect(checklist['productionExecutionAuthorized'], isTrue);
      expect(checklist['authorizationOverlay'], 'docs/phase10o2-deployment-authorization.json');
      expect(phase10o2['status'], anyOf('STOP_CANDIDATE_COMMIT_AND_FULL_TESTS_PENDING', 'DEPLOYMENT_CANDIDATE_READY'));
      expect(phase10o2['authorizationScope']['installationOnly'], isTrue);
      expect(phase10o2['authorizationScope']['productionMigrationExecutionInThisPhase'], isFalse);
      expect(phase10o2['approvals']['businessOperator']['authorization'],
        'I authorize the controlled production deployment, provided every preflight and backup gate passes.');
      expect(phase10o2['approvals']['independentVerifier']['name'], 'Arnab');
      expect(phase10o2['approvals']['independentVerifier']['role'], 'Senior Developer');
      expect(phase10o2['approvals']['independentVerifier']['approval'],
        'I independently reviewed the Release 4 deployment evidence and approve proceeding with the controlled production deployment, subject to all pre-write and post-deployment verification gates passing.');
      expect(phase10o2['approvals']['independentVerifier']['signature'], isNull);
      expect(phase10o2['approvals']['independentVerifier']['timestamp'], isNull);
        final maintenance = sections
          .singleWhere((section) => section['id'] == 'maintenance_mode_readiness');
        final writerBarrier = (maintenance['items'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((item) => item['id'] == 'single_writer_barrier_verified');
        expect(writerBarrier['answer'], 'YES');
        expect(phase10o2['validationState']['writerFreeze'], 'VERIFIED_OPERATOR_ATTESTATION_AND_LOCAL_OBSERVATIONS');
        expect(phase10o2['validationState']['finalDeploymentGoPacket'],
          anyOf('STOP: CANDIDATE_COMMIT_AND_FULL_TESTS_PENDING', 'DEPLOYMENT_CANDIDATE_READY'));
        final rollback = sections.singleWhere((section) => section['id'] == 'rollback_readiness');
        expect((rollback['items'] as List).cast<Map<String, dynamic>>()
          .singleWhere((item) => item['id'] == 'paired_backup_restore_rehearsed')['answer'], 'YES');
          expect(checklist['phase10O4Evidence']['finalManifestState'], 'COMPLETE');
          expect(checklist['phase10O4Evidence']['productionTargetsModified'], isFalse);
          expect(checklist['phase10O4Evidence']['productionMigrationOrDryRunExecuted'], isFalse);
      expect(phase10o2['phase10O3Evidence']['roleCombination']['result'], 'VALID');
      expect(phase10o2['phase10O3Evidence']['rollbackAuthorization']['signature'], isNull);
      expect(phase10o2['phase10O3Evidence']['semanticDeploymentApproval']['scope'],
        contains('row-level migration/retirement approvals remain false'));
      expect(checklist['hardBlockers'], isA<List<dynamic>>());
    expect(checklist['approvals'], isA<Map<String, dynamic>>());
    expect(phase10f['status'], 'RETENTION_POLICY_APPROVED_EXECUTION_BLOCKED');
    expect(phase10f['decision'], contains('NO_MIGRATION_NO_RETIREMENT'));
    expect(phase10f['preapprovedMappings'], isEmpty);

    final retentionApproval =
        phase10f['phase10lRetentionPolicyApproval'] as Map<String, dynamic>;
    expect(retentionApproval['retentionPolicyApproved'], isTrue);
    expect(retentionApproval['executionAuthorized'], isFalse);
    expect(retentionApproval['migrationApproved'], isFalse);
    expect(retentionApproval['retirementApproved'], isFalse);
    expect(retentionApproval['approvalDecision'], 'APPROVE_RETENTION_ONLY');

    expect(phase10l['phase'], 'PHASE_10L_LEGACY_RETENTION_POLICY_APPROVAL');
    expect(phase10l['retentionPolicyApproved'], isTrue);
    expect(phase10l['executionAuthorized'], isFalse);
    expect(phase10l['migrationApproved'], isFalse);
    expect(phase10l['retirementApproved'], isFalse);
    expect(phase10l['productionInstallationApproved'], isFalse);

    final coveredRows = (phase10l['coveredDispositionRows'] as Map)
        .cast<String, dynamic>();
    final retentionDispositions =
        (coveredRows['classifications'] as List).cast<Map<String, dynamic>>();
    expect(
      retentionDispositions.every(
        (disposition) =>
            disposition['migrationApproved'] == false &&
            disposition['retirementApproved'] == false,
      ),
      isTrue,
    );

    final identityActions =
        (phase10f['identityReviewActions'] as List)
            .cast<Map<String, dynamic>>();
    expect(identityActions, isNotEmpty);
    expect(
      identityActions.every(
        (action) =>
            action['targetId'] == null &&
            action['migrationApproved'] == false &&
            action['retirementApproved'] == false,
      ),
      isTrue,
    );
    expect(runbook, anyOf(
      contains('**STOP; CANDIDATE COMMIT NOT READY.**'),
      contains('**STOP; O5 CANDIDATE COMMIT AND FULL SUITE PENDING.**'),
      contains('**DEPLOYMENT CANDIDATE READY; PRODUCTION MIGRATION NOT EXECUTED.**'),
    ));
  });

  test('rollback runbook includes paired restore and identity proof', () {
    final requiredSteps = [
      'Keep every app client and sync worker frozen.',
      'Stop the runner and close all app, SQLite, sync and maintenance handles.',
      'Create a separate, access-controlled forensic copy',
      'Verify the selected paired backup set has one timestamp/backup ID',
      'Restore both account and public-config from that same verified backup set',
      'With explicit rollback authorization recorded',
      'Re-run read-only hashes, sizes/mtime, sidecar scan, integrity checks',
      'Resume app writers only after release commander',
    ];
    final positions = requiredSteps.map(runbook.indexOf).toList();
    expect(positions.every((position) => position >= 0), isTrue);
    expect(positions, orderedEquals([...positions]..sort()));
    expect(runbook, contains('Rollback is a paired database restore'));
  });

  test('production verification is read-only and has no executable migration', () {
    expect(runbook, contains('sqlite3 -readonly'));
    expect(runbook, contains('shasum -a 256'));
    expect(runbook, contains('Do not invoke `--execute` in Phase 10O5'));
    expect(runbook, contains('must not run a production migration or repeat the production dry-run'));
    expect(checklist['productionWritesPerformedByPhase10J'], isFalse);
    expect(checklist['firestoreAccessedByPhase10J'], isFalse);
    expect(phase10ib['safety']['productionDatabasesOpenedWritable'], isFalse);
    expect(phase10ib['safety']['firestoreAccessedByRehearsal'], isFalse);
    expect(runbook, contains('zero Firestore requests and zero production writes'));
  });
}
