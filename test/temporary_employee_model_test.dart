import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/employee_model.dart';

void main() {
  test('temporary worker reuses employee identity without application login credentials', () {
    final employee = EmployeeModel.fromData('EMP-TEMP-1', {
      'employeeId': 'EMP-TEMP-1',
      'uid': '',
      'email': '',
      'ownerUid': 'OWNER-1',
      'name': 'Daily worker',
      'status': 'active',
      'loginEnabled': false,
      'employmentType': 'TEMPORARY',
      'businessIds': ['BUS-1'],
      'outletIds': ['OUT-1'],
    });
    expect(employee.employeeId, 'EMP-TEMP-1');
    expect(employee.isTemporaryWorker, isTrue);
    expect(employee.loginEnabled, isFalse);
    expect(employee.businessIds, ['BUS-1']);
  });
}
