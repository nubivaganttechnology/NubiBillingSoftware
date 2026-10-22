import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/customer_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class CustomerRepository {
  CustomerRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<List<CustomerModel>> search({
    required String tenantId,
    required String businessId,
    required String token,
    String? phone,
    String? nameLowerPrefix,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        if (phone != null) FirestoreFilter('phone', 'EQUAL', phone),
      ],
      orderBy: nameLowerPrefix == null ? 'nameLower' : null,
      idToken: token,
    );
    return [
      for (final doc in docs)
        CustomerModel.fromData(
          (doc['name'] as String? ?? '').split('/').last,
          FirestoreRestService.decodeFields(doc['fields']),
        ),
    ].where((customer) {
      final prefix = nameLowerPrefix?.toLowerCase();
      return prefix == null || customer.nameLower.startsWith(prefix);
    }).toList();
  }

  Future<CustomerModel> create({
    required String tenantId,
    required String businessId,
    required String token,
    required String name,
    required String phone,
    String? gstin,
    String? stateCode,
    String? address,
    int? creditLimitPaise,
    int openingBalancePaise = 0,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{10}$').hasMatch(normalizedPhone)) {
      throw const AppException('Enter a valid 10-digit phone number.');
    }
    final duplicates = await firestore.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('phone', 'EQUAL', normalizedPhone),
      ],
      idToken: token,
    );
    if (duplicates.isNotEmpty) {
      throw const AppException('A customer with this phone already exists.');
    }
    final id = IdGenerator.create('CUS');
    final customer = CustomerModel(
      customerId: id,
      businessId: businessId,
      name: name.trim(),
      phone: normalizedPhone,
      nameLower: name.trim().toLowerCase(),
      gstin: gstin,
      stateCode: stateCode,
      address: address,
      creditLimitPaise: creditLimitPaise,
      duePaise: openingBalancePaise > 0 ? openingBalancePaise : 0,
      advancePaise: openingBalancePaise < 0 ? -openingBalancePaise : 0,
    );
    await firestore.createDocument(FirebaseConstants.customers, id, {
      'customerId': id,
      'tenantId': tenantId,
      'businessId': businessId,
      'name': customer.name,
      'nameLower': customer.nameLower,
      'phone': customer.phone,
      'gstin': customer.gstin,
      'stateCode': customer.stateCode,
      'address': customer.address,
      'creditLimitPaise': customer.creditLimitPaise,
      'duePaise': customer.duePaise,
      'advancePaise': customer.advancePaise,
      'status': customer.status,
    }, idToken: token);
    return customer;
  }

  Future<CustomerModel> update({
    required String tenantId,
    required String businessId,
    required String token,
    required CustomerModel customer,
    required String name,
    required String phone,
    String? gstin,
    String? stateCode,
    String? address,
    int? creditLimitPaise,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{10}$').hasMatch(normalizedPhone)) {
      throw const AppException('Enter a valid 10-digit phone number.');
    }
    final duplicates = await firestore.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('phone', 'EQUAL', normalizedPhone),
      ],
      idToken: token,
    );
    if (duplicates.any((doc) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      final id = data['customerId'] as String? ?? '';
      return id != customer.customerId;
    })) {
      throw const AppException('A customer with this phone already exists.');
    }
    final updated = CustomerModel(
      customerId: customer.customerId,
      businessId: businessId,
      name: name.trim(),
      phone: normalizedPhone,
      nameLower: name.trim().toLowerCase(),
      gstin: gstin,
      stateCode: stateCode,
      address: address,
      creditLimitPaise: creditLimitPaise,
      duePaise: customer.duePaise,
      advancePaise: customer.advancePaise,
      status: customer.status,
    );
    await firestore.updateDocument(
      FirebaseConstants.customers,
      customer.customerId,
      {
        'customerId': updated.customerId,
        'tenantId': tenantId,
        'businessId': businessId,
        'name': updated.name,
        'nameLower': updated.nameLower,
        'phone': updated.phone,
        'gstin': updated.gstin,
        'stateCode': updated.stateCode,
        'address': updated.address,
        'creditLimitPaise': updated.creditLimitPaise,
        'duePaise': updated.duePaise,
        'advancePaise': updated.advancePaise,
        'status': updated.status,
      },
      idToken: token,
    );
    return updated;
  }
}
