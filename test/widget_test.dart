import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/utils/validators.dart';
import 'package:testflutter/data/services/gst_verification_service.dart';
import 'package:testflutter/data/models/storage_location_model.dart';
import 'package:testflutter/theme/app_theme.dart';

void main() {
  test('application theme uses Material 3', () {
    expect(AppTheme.light.useMaterial3, isTrue);
  });

  test('business names normalize case and repeated whitespace', () {
    expect(
      AppValidators.normalizeBusinessName('  SUMAN   Hardware  '),
      'suman hardware',
    );
    expect(AppValidators.businessName('   '), isNotNull);
    expect(AppValidators.businessName('A' * 121), isNotNull);
  });

  test('email and Indian mobile validation normalize common input', () {
    expect(AppValidators.email(' owner@example.in '), isNull);
    expect(AppValidators.email('not-an-email'), isNotNull);
    expect(AppValidators.indianPhone('98765 43210'), isNull);
    expect(AppValidators.normalizeIndianPhone('09876543210'), '+919876543210');
    expect(AppValidators.indianPhone('12345'), isNotNull);
  });

  test(
    'GSTIN validation checks shape but does not assert provider verification',
    () {
      const gstin = '27AAPFU0939F1ZV';
      expect(AppValidators.gstin(gstin), isNull);
      expect(AppValidators.gstin('123456789012345'), isNotNull);
      expect(AppValidators.gstin('27 AAPFU0939F1ZV'), isNull);
      expect(AppValidators.normalizeGstin(' 27 AAPFU0939F1ZV '), gstin);
      expect(AppValidators.gstin('bad'), isNotNull);
    },
  );

  test('Rack documents decode as Outlet or Godown children and legacy Godown Racks remain readable', () {
    final outletRack = StorageLocationModel.fromData('RACK-1', {
      'rackId': 'RACK-1',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'parentLocationType': 'OUTLET',
      'parentLocationId': 'OUT-1',
      'rackNumber': 1,
      'rackCode': 'RACK-001',
      'name': 'Rack 01',
      'status': 'ACTIVE',
    }, type: StorageLocationType.rack);
    expect(outletRack.parentLocationType, 'OUTLET');
    expect(outletRack.parentLocationId, 'OUT-1');
    expect(outletRack.rackNumber, 1);

    final legacyRack = StorageLocationModel.fromData('RACK-2', {
      'rackId': 'RACK-2',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'godownId': 'GDN-1',
      'name': 'Old Rack',
      'code': 'OLD-1',
      'status': 'ACTIVE',
    }, type: StorageLocationType.rack);
    expect(legacyRack.parentLocationType, 'GODOWN');
    expect(legacyRack.parentLocationId, 'GDN-1');
  });

  test(
    'unconfigured GST provider never reports verification success',
    () async {
      final result = await UnconfiguredGSTVerificationService().verifyGSTIN(
        '27AAPFU0939F1ZV',
      );
      expect(result.success, isFalse);
      expect(result.verifiedAt, isNull);
    },
  );
}
