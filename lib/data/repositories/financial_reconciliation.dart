part of 'reports_repository.dart';

// This replaces the former audit calculations. It reads existing contracts only;
// it is not a second ledger and never repairs or writes source documents.
extension _FinancialReconciliationEngine on ReportsRepository {
  Future<ReportReadSnapshot> _reportRead(
    List<ReportReadQuery> queries,
    String token,
  ) async {
    final source = firestore;
    if (source is FinancialReportSnapshotReader) {
      return (source as FinancialReportSnapshotReader).readReportSnapshot(
        queries,
        token: token,
      );
    }
    final documents = <String, List<Map<String, dynamic>>>{};
    final coverage = <String, Map<String, Object?>>{};
    for (final query in queries) {
      try {
        documents[query.key] = await source.queryDocuments(
          collection: query.collection,
          filters: query.filters,
          idToken: token,
        );
        coverage[query.key] = {
          'status': 'NOT_VERIFIED',
          'reason': 'No local synchronization evidence',
        };
      } catch (e) {
        documents[query.key] = [];
        coverage[query.key] = {
          'status': 'NOT_VERIFIED',
          'reason': 'Source unavailable: ${e.runtimeType}',
        };
      }
    }
    return ReportReadSnapshot(documents, coverage);
  }

  Future<
    ({
      String uid,
      bool isOwner,
      Map<String, dynamic>? employee,
      List<ReportReadQuery> queries,
      ReportReadSnapshot authorization,
    })
  >
  _financialAuthorization(String tenantId, String token) async {
    final claims = AuthSession(
      idToken: token,
      refreshToken: '',
      uid: '',
      email: '',
      expiresAt: DateTime.now(),
    ).tokenClaims;
    final uid = claims?['sub'];
    if (uid is! String ||
        uid.isEmpty ||
        claims?['aud'] != EnvironmentConfig.projectId) {
      throw StateError(
        'An authenticated account is required for financial reporting.',
      );
    }
    final authQueries = [
      ReportReadQuery('user', 'user', [FirestoreFilter('uid', 'EQUAL', uid)]),
      ReportReadQuery('employee', 'employees', [
        FirestoreFilter('uid', 'EQUAL', uid),
      ]),
      ReportReadQuery('business', 'businesses', [
        FirestoreFilter('ownerUid', 'EQUAL', tenantId),
      ]),
      ReportReadQuery('outlet', 'outlets', [
        FirestoreFilter('ownerUid', 'EQUAL', tenantId),
      ]),
      ReportReadQuery('outletTenant', 'outlets', [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
      ]),
      const ReportReadQuery('roles', 'roles', []),
      const ReportReadQuery('permissionDefinitions', 'permissions', []),
    ];
    final authorization = await _reportRead(authQueries, token);
    final users = _decoded(authorization, 'user');
    final user = users
        .where((r) => r['uid'] == uid && r['isActive'] == true)
        .firstOrNull;
    if (user == null) {
      throw StateError(
        'Active reporting authorization is unavailable offline.',
      );
    }
    final isOwner = user['accountType'] == 'owner' && uid == tenantId;
    final employee = _decoded(authorization, 'employee')
        .where(
          (r) =>
              r['uid'] == uid &&
              r['ownerUid'] == tenantId &&
              '${r['status']}'.toUpperCase() == 'ACTIVE',
        )
        .firstOrNull;
    final roleIds = {
      ...?employee?['roleIds'] as List?,
      if (employee?['roleId'] != null) employee!['roleId'],
    };
    final permissions = <String>{
      ...((employee?['permissionIds'] as List?) ?? []).whereType<String>(),
      for (final role in _decoded(authorization, 'roles'))
        if (role['isActive'] != false &&
            roleIds.contains(role['roleId'] ?? role['_id']) &&
            '${role['status']}'.toUpperCase() != 'INACTIVE')
          ...((role['permissionIds'] ?? role['permissions']) as List? ?? [])
              .whereType<String>(),
    };
    final permissionDefinitions = _decoded(
      authorization,
      'permissionDefinitions',
    );
    if (!isOwner) {
      final activePermissions = permissionDefinitions
          .where(
            (p) =>
                p['isActive'] == true ||
                '${p['status']}'.toUpperCase() == 'ACTIVE',
          )
          .map(
            (p) => PermissionIdMatcher.normalize(
              '${p['permissionId'] ?? p['_id']}',
            ),
          )
          .toSet();
      permissions.removeWhere(
        (p) => !activePermissions.contains(PermissionIdMatcher.normalize(p)),
      );
    }
    if (!isOwner &&
        (employee == null ||
            !PermissionCatalog.allows('reports', permissions.toList()))) {
      throw StateError(
        'You do not have permission to generate this financial report.',
      );
    }
    return (
      uid: uid,
      isOwner: isOwner,
      employee: employee,
      queries: authQueries,
      authorization: authorization,
    );
  }

  Future<AuditScopeOptions> _financialScopeOptions(
    String tenantId,
    String token,
  ) async {
    final access = await _financialAuthorization(tenantId, token);
    final businessRows = _decoded(access.authorization, 'business');
    final outletRows = {
      for (final o in [
        ..._decoded(access.authorization, 'outlet'),
        ..._decoded(access.authorization, 'outletTenant'),
      ])
        o['_id']: o,
    }.values;
    final businesses = <AuditScopeOption>[
      for (final b in businessRows)
        if (access.isOwner ||
            (access.employee?['businessIds'] as List? ?? []).contains(
              b['businessId'] ?? b['_id'],
            ))
          AuditScopeOption(
            '${b['businessId'] ?? b['_id']}',
            '${b['businessName']}',
            '${b['businessId'] ?? b['_id']}',
            b['isActive'] != false &&
                '${b['status']}'.toUpperCase() != 'INACTIVE',
          ),
    ];
    final businessIds = businesses.map((b) => b.id).toSet();
    final outlets = <AuditScopeOption>[
      for (final o in outletRows)
        if (businessIds.contains(o['businessId']) &&
            (access.isOwner ||
                (access.employee?['outletIds'] as List? ?? []).contains(
                  o['outletId'] ?? o['_id'],
                )))
          AuditScopeOption(
            '${o['outletId'] ?? o['_id']}',
            '${o['outletName']}',
            '${o['businessId']}',
            o['isActive'] != false &&
                '${o['status']}'.toUpperCase() != 'INACTIVE',
          ),
    ];
    return AuditScopeOptions(businesses, outlets);
  }

  Future<FinancialAuditReportData> _loadFinancialReconciliation({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
    required bool includeSalaryData,
    required AuditScopeSelection scope,
    String? gstin,
    String? tradeName,
    String? legalName,
    String? address,
    String? phone,
    String? email,
  }) async {
    final access = await _financialAuthorization(tenantId, token);
    final uid = access.uid;
    final isOwner = access.isOwner;
    final employee = access.employee;
    final authQueries = access.queries;
    final authorization = access.authorization;
    final start = _indiaDay(dateRange.start);
    final end = _indiaDay(dateRange.end).add(const Duration(days: 1));
    if (!end.isAfter(start)) throw ArgumentError('Invalid reporting period.');
    // Individual salary grants can be employee-specific in this architecture.
    // Business financial reports expose payroll aggregates to the owner only.
    final salaryAllowed = isOwner && includeSalaryData;
    final businesses = _decoded(authorization, 'business');
    final outlets = {
      for (final o in [
        ..._decoded(authorization, 'outlet'),
        ..._decoded(authorization, 'outletTenant'),
      ])
        o['_id']: o,
    }.values.toList();
    final requestedBusinesses =
        scope.mode == AuditScopeMode.combinedAuthorizedBusinesses
        ? scope.outletsByBusiness.keys.toSet()
        : {businessId};
    if (requestedBusinesses.isEmpty) {
      throw ArgumentError('Explicitly select the businesses to combine.');
    }
    final selected = <Map<String, dynamic>>[];
    final inclusionRows = <List<String>>[];
    final identities = <String>{};
    for (final bid in requestedBusinesses) {
      final b = businesses
          .where((r) => (r['businessId'] ?? r['_id']) == bid)
          .firstOrNull;
      if (b == null ||
          (!isOwner &&
              !(employee!['businessIds'] as List? ?? []).contains(bid))) {
        throw StateError('Business $bid is outside your authorized scope.');
      }
      if ((b['currency'] ?? 'INR') != 'INR') {
        throw StateError('Only compatible INR books can be consolidated.');
      }
      identities.add('${b['gstin'] ?? 'NOT_VERIFIED'}'.trim().toUpperCase());
      final requestedOutlets = switch (scope.mode) {
        AuditScopeMode.selectedOutlet => [outletId],
        AuditScopeMode.allOutletsInBusiness => <String>[],
        _ => scope.outletsByBusiness[bid] ?? <String>[],
      };
      if (scope.mode == AuditScopeMode.selectedOutletsInBusiness &&
          requestedOutlets.isEmpty) {
        throw ArgumentError('Explicitly select at least one outlet.');
      }
      final available = outlets.where((o) => o['businessId'] == bid).toList();
      for (final requested in requestedOutlets) {
        if (!available.any((o) => (o['outletId'] ?? o['_id']) == requested)) {
          throw StateError(
            'Outlet $requested is unavailable or outside business $bid.',
          );
        }
      }
      for (final o in available) {
        final oid = '${o['outletId'] ?? o['_id']}';
        final permitted =
            isOwner || (employee!['outletIds'] as List? ?? []).contains(oid);
        final wanted =
            requestedOutlets.isEmpty || requestedOutlets.contains(oid);
        final included = permitted && wanted;
        inclusionRows.add([
          bid,
          '${b['businessName']}',
          oid,
          '${o['outletName']}',
          included
              ? 'INCLUDED'
              : (permitted
                    ? 'EXCLUDED: not selected'
                    : 'EXCLUDED: no permission'),
          o['isActive'] == false || '${o['status']}'.toUpperCase() == 'INACTIVE'
              ? 'Historical / inactive'
              : 'Active',
        ]);
        if (included) selected.add({...o, 'outletId': oid, 'businessId': bid});
        if (wanted && !permitted && requestedOutlets.isNotEmpty) {
          throw StateError(
            'Outlet $oid is outside your permitted outlet scope.',
          );
        }
      }
    }
    if (selected.isEmpty) {
      throw StateError(
        'No authorized outlets are available for this selection.',
      );
    }
    final issues = <List<String>>[];
    final evidence = <List<String>>[];
    final coverageRows = <List<String>>[];
    final allQueries = <ReportReadQuery>[...authQueries];
    const outletCollections = [
      'invoices',
      'purchase_bills',
      'stock_balances',
      'stock_movements',
      'inventory_batches',
      'inventory_batch_movements',
      'inventory_transactions',
      'goods_receipts',
      'purchase_returns',
      'purchase_corrections',
      'supplier_payments',
      'supplier_refunds',
      'financial_transactions',
      'customer_balances',
      'customer_ledger_entries',
      'supplier_ledger_entries',
    ];
    for (final o in selected) {
      for (final collection in outletCollections) {
        // Financial events can contain confidential payroll. Read them only with payroll authority.
        if (collection == 'financial_transactions' && !salaryAllowed) continue;
        allQueries.add(
          ReportReadQuery(
            '${o['businessId']}/${o['outletId']}/$collection',
            collection,
            [
              FirestoreFilter('tenantId', 'EQUAL', tenantId),
              FirestoreFilter('businessId', 'EQUAL', o['businessId'] as String),
              FirestoreFilter('outletId', 'EQUAL', o['outletId'] as String),
            ],
          ),
        );
      }
    }
    for (final bid in requestedBusinesses) {
      if (salaryAllowed) {
        allQueries.add(
          ReportReadQuery('$bid/staff', 'employees', [
            FirestoreFilter('ownerUid', 'EQUAL', tenantId),
            FirestoreFilter('businessIds', 'ARRAY_CONTAINS', bid),
          ]),
        );
      }
      for (final collection in [
        'expenses',
        'invoice_items',
        'payments',
        'purchase_bill_items',
        if (salaryAllowed) ...[
          'salary_periods',
          'staff_khata_transactions',
          'employee_salary_profiles',
          'employee_outlet_allocations',
        ],
      ]) {
        // Legacy payments lack scope; use only explicitly authorized invoice joins below.
        allQueries.add(
          ReportReadQuery(
            '$bid/$collection',
            collection,
            collection == 'payments'
                ? []
                : [
                    FirestoreFilter('tenantId', 'EQUAL', tenantId),
                    FirestoreFilter('businessId', 'EQUAL', bid),
                  ],
          ),
        );
      }
    }
    final snapshot = await _reportRead(allQueries, token);
    for (final query in authQueries) {
      if (snapshot.documents[query.key].toString() !=
          authorization.documents[query.key].toString()) {
        throw StateError(
          'Reporting authorization changed while reading the snapshot. Retry.',
        );
      }
    }
    bool ready(String key) =>
        snapshot.coverage[key]?['status'] == 'LOCAL_SNAPSHOT';
    var pending = 0;
    var syncComplete = true;
    for (final q in allQueries) {
      final c = snapshot.coverage[q.key] ?? {};
      final p = (c['pending'] as num?)?.toInt() ?? 0;
      final conflicts = (c['conflicts'] as num?)?.toInt() ?? 0;
      pending += p;
      if (c['status'] != 'LOCAL_SNAPSHOT' || p > 0 || conflicts > 0) {
        syncComplete = false;
      }
      coverageRows.add([
        q.key,
        '${snapshot.documents[q.key]?.length ?? 0}',
        '${c['status'] ?? 'NOT_VERIFIED'}',
        '${c['lastSyncedAt'] ?? 'No completed download'}',
        '$p / $conflicts',
      ]);
    }
    void issue(String scopeId, String code, String details) =>
        issues.add([scopeId, code, details]);
    final results = <_OutletReview>[];
    final salaryLiabilities = <String, int>{};
    final gstRows = <String, _TaxReview>{};
    final hsnRows = <String, _TaxReview>{};
    final inventoryRows = <List<String>>[];
    final debtorRows = <List<String>>[];
    final creditorRows = <List<String>>[];
    final cashRows = <List<String>>[];
    final payrollRows = <List<String>>[];
    final expenseRows = <List<String>>[];
    final transferRows = <List<String>>[];
    var taxInvalid = false;
    var inventoryInvalid = false;
    var salesInvalid = false;
    var purchaseInvalid = false;
    var salaryInvalid = !salaryAllowed;
    var expenseInvalid = false;
    var directInvalid = false;
    var cashInvalid = false;
    final invoiceNumbers = <String>{};
    final knownPaymentIds = <String>{};
    final knownFinancialIds = <String>{};
    final countedCashReferences = <String>{};
    bool wasCashCounted(String business, Object? id) =>
        id != null && countedCashReferences.contains('$business/$id');
    final monthly = <String, List<int>>{};
    for (final o in selected) {
      final bid = o['businessId'] as String;
      final oid = o['outletId'] as String;
      final scopeId = '$bid/$oid';
      final r = _OutletReview(bid, oid, '${o['outletName']}');
      results.add(r);
      if (!ready('$scopeId/invoices')) {
        salesInvalid = true;
        r.salesValid = false;
        taxInvalid = true;
      }
      if (!ready('$scopeId/purchase_bills') ||
          !ready('$scopeId/purchase_returns')) {
        purchaseInvalid = true;
        r.purchasesValid = false;
      }
      if (!ready('$bid/expenses')) {
        expenseInvalid = true;
        directInvalid = true;
      }
      if (salaryAllowed &&
          (!ready('$bid/salary_periods') ||
              !ready('$bid/staff_khata_transactions'))) {
        salaryInvalid = true;
      }

      List<Map<String, dynamic>> rows(String col) =>
          _decoded(snapshot, '$scopeId/$col');
      List<Map<String, dynamic>> businessRows(String col) =>
          _decoded(snapshot, '$bid/$col');
      bool inPeriod(Map<String, dynamic> d, List<String> fields, String col) {
        final dt = _dateFields(d, fields);
        if (dt == null) {
          if (col == 'invoices') {
            salesInvalid = true;
            r.salesValid = false;
            taxInvalid = true;
          }
          if (col.startsWith('purchase')) {
            purchaseInvalid = true;
            r.purchasesValid = false;
          }
          if (col == 'expenses') {
            expenseInvalid = true;
            if (['DIRECT_INWARD', 'UNCLASSIFIED'].contains(_expenseClass(d)))
              directInvalid = true;
          }
          if (col == 'payments' ||
              col == 'financial_transactions' ||
              col == 'supplier_payments') {
            cashInvalid = true;
          }
          issue(
            scopeId,
            'MISSING_DATE',
            '$col/${d['_id']}: no supported transaction date',
          );
          return false;
        }
        return !dt.isBefore(start) && dt.isBefore(end);
      }

      void trace(String col, Map<String, dynamic> d, String field, int amount) {
        evidence.add([
          scopeId,
          '$col/${d['_id']}',
          field,
          FinancialReconciliation.money(amount),
          '${_dateFields(d, ['invoiceDate', 'expenseDate', 'transactionDate', 'periodEnd', 'createdAt']) ?? 'Date unavailable'}',
          '${d['_sync'] ?? 'NOT_VERIFIED'}',
        ]);
      }

      if (rows('invoices').any((i) => _active(i) && !_postedInvoice(i))) {
        salesInvalid = true;
        r.salesValid = false;
        issue(
          scopeId,
          'UNSUPPORTED_INVOICE_STATUS',
          'Unrecognized invoice posting status; review source before treating as revenue.',
        );
      }
      if (rows('purchase_bills').any(
        (b) => _active(b) && '${b['status']}'.toUpperCase() != 'APPROVED',
      )) {
        purchaseInvalid = true;
        r.purchasesValid = false;
        issue(
          scopeId,
          'UNSUPPORTED_PURCHASE_STATUS',
          'Purchase status is not an approved accounting posting.',
        );
      }
      for (final invoice in rows('invoices')) {
        final originalDate = _dateFields(invoice, ['invoiceDate', 'createdAt']);
        final changed = _dateFields(invoice, ['cancelledAt', 'updatedAt']);
        if (originalDate != null &&
            originalDate.isBefore(end) &&
            changed != null &&
            !changed.isBefore(end)) {
          salesInvalid = true;
          r.salesValid = false;
          taxInvalid = true;
          issue(
            scopeId,
            'POST_PERIOD_INVOICE_CHANGE',
            'invoices/${invoice['_id']}: changed after the reporting boundary; historical amounts require the original revision/cancellation trail.',
          );
        }
      }
      final invoices = rows('invoices').where(_postedInvoice).toList();
      final allInvoiceIds = <String, Map<String, dynamic>>{};
      for (final inv in rows('invoices')) {
        for (final id in _invoiceAliases(inv)) {
          allInvoiceIds[id] = inv;
        }
      }
      for (final inv in invoices) {
        if (!inPeriod(inv, ['invoiceDate', 'createdAt'], 'invoices')) continue;
        final internalSale = _internal(inv);
        if (internalSale) {
          transferRows.add([
            scopeId,
            'invoices/${inv['_id']}',
            'Excluded internal transfer',
            'Financial transfer amount not external revenue',
          ]);
        }
        final taxable = _integer(inv, ['taxablePaise']);
        final cgst = _integer(inv, ['cgstPaise']);
        final sgst = _integer(inv, ['sgstPaise']);
        final igst = _integer(inv, ['igstPaise']);
        final cess =
            _integer(inv, ['cessPaise']) ??
            0; // Existing billing schema has no cess field.
        final grand = _integer(inv, ['grandTotalPaise']);
        final discount = _integer(inv, ['discountPaise']);
        final sign =
            '${inv['documentType'] ?? inv['type']}'.toUpperCase() ==
                'SALES_RETURN'
            ? -1
            : 1;
        if (taxable == null ||
            grand == null ||
            cgst == null ||
            sgst == null ||
            igst == null) {
          salesInvalid = true;
          taxInvalid = true;
          r.salesValid = false;
          issue(
            scopeId,
            'SALES_FIELDS_MISSING',
            'invoices/${inv['_id']}: taxable/grand/tax component snapshot incomplete',
          );
        }
        if (!internalSale) {
          r.sales += sign * (taxable ?? 0);
        } else {
          r.internalTaxable += sign * (taxable ?? 0);
        }
        if (!internalSale && sign == -1) r.salesReturns += taxable ?? 0;
        if (!internalSale) r.gross += sign * (grand ?? 0);
        if (!internalSale) r.discounts += discount ?? 0;
        r.outputTax += sign * ((cgst ?? 0) + (sgst ?? 0) + (igst ?? 0) + cess);
        if (taxable != null) {
          trace(
            'invoices',
            inv,
            'taxablePaise (after discount, excludes GST)',
            sign * taxable,
          );
        }
        if (grand != null &&
            taxable != null &&
            cgst != null &&
            sgst != null &&
            igst != null &&
            grand !=
                taxable +
                    cgst +
                    sgst +
                    igst +
                    cess +
                    (_integer(inv, ['roundOffPaise']) ?? 0)) {
          salesInvalid = true;
          r.salesValid = false;
          issue(
            scopeId,
            'INVOICE_TOTAL_MISMATCH',
            'invoices/${inv['_id']} gross != taxable + tax + rounding',
          );
        }
        final sequence = '$bid/${inv['invoiceNumber']}';
        if (inv['invoiceNumber'] == null || !invoiceNumbers.add(sequence)) {
          salesInvalid = true;
          r.salesValid = false;
          issue(
            scopeId,
            'INVOICE_NUMBER',
            'Missing or duplicate invoice number: $sequence',
          );
        }
        final embedded = inv['items'];
        final aliases = _invoiceAliases(inv);
        final lines = embedded is List && embedded.isNotEmpty
            ? embedded
                  .whereType<Map>()
                  .map((v) => Map<String, dynamic>.from(v))
                  .toList()
            : businessRows('invoice_items')
                  .where(
                    (l) =>
                        aliases.contains(l['invoiceId']) &&
                        (l['outletId'] == null || l['outletId'] == oid),
                  )
                  .toList();
        var lineTaxable = 0, lineTax = 0;
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final value = _integer(line, ['taxablePaise', 'taxableAmount']);
          final rate = _integer(line, ['gstRateBps']);
          final lc = _integer(line, ['cgstPaise']),
              ls = _integer(line, ['sgstPaise']),
              li = _integer(line, ['igstPaise']);
          // The billing contract explicitly splits intrastate tax and omits zero IGST on lines.
          // Do not manufacture interstate components where legacy lines split them incorrectly.
          final inter = inv['taxMode'] == 'interState' || (igst ?? 0) > 0;
          final actualIgst =
              li ?? (!inter && lc != null && ls != null ? 0 : null);
          final lineCess = _integer(line, ['cessPaise']) ?? 0;
          final snapshotTax = _integer(line, ['taxPaise', 'taxAmount']);
          final hsn = '${line['hsn'] ?? line['hsnCode'] ?? ''}'.trim();
          final uqc = '${line['unit'] ?? line['uqc'] ?? ''}'.trim();
          final qty = line['quantity'] is num
              ? (line['quantity'] as num).toDouble()
              : null;
          final classification =
              '${line['taxClassification'] ?? (rate != null && rate > 0 ? 'TAXABLE' : 'UNCLASSIFIED')}'
                  .toUpperCase();
          if (value == null ||
              rate == null ||
              lc == null ||
              ls == null ||
              actualIgst == null ||
              !const [
                'TAXABLE',
                'ZERO_RATED',
                'NIL_RATED',
                'EXEMPT',
                'NON_GST',
                'OUT_OF_SCOPE',
              ].contains(classification) ||
              hsn.isEmpty ||
              uqc.isEmpty ||
              qty == null) {
            taxInvalid = true;
            issue(
              scopeId,
              'GST_HSN_INCOMPLETE',
              'invoices/${inv['_id']}/items/$i: missing or ambiguous rate, classification, HSN, UQC, quantity or tax components',
            );
          }
          if (value != null) lineTaxable += sign * value;
          final components = lc != null && ls != null && actualIgst != null
              ? lc + ls + actualIgst + lineCess
              : null;
          if (components != null) lineTax += sign * components;
          if (snapshotTax != null &&
              components != null &&
              components != snapshotTax) {
            taxInvalid = true;
            issue(
              scopeId,
              'LINE_TAX_MISMATCH',
              'invoices/${inv['_id']}/items/$i component sum differs from saved tax',
            );
          }
          final supply =
              '${internalSale ? 'INTERNAL_TRANSFER / ' : ''}${inter ? 'INTER_STATE' : 'INTRA_STATE'}';
          if (value != null &&
              rate != null &&
              components != null &&
              ((value * rate + 5000) ~/ 10000) != components - lineCess) {
            taxInvalid = true;
            issue(
              scopeId,
              'GST_RATE_AMOUNT_MISMATCH',
              'invoices/${inv['_id']}/items/$i saved rate does not match saved tax.',
            );
          }
          if (inter && ((lc ?? 0) != 0 || (ls ?? 0) != 0)) {
            taxInvalid = true;
            issue(
              scopeId,
              'INTERSTATE_COMPONENT_CONFLICT',
              'invoices/${inv['_id']}/items/$i has CGST/SGST with an interstate header; source requires correction.',
            );
          }
          final key = '$bid|$classification|$supply|${rate ?? 'UNKNOWN'}';
          final g = gstRows.putIfAbsent(
            key,
            () => _TaxReview(bid, '$classification / $supply', rate, '', ''),
          );
          final h = hsnRows.putIfAbsent(
            '$key|$hsn|$uqc',
            () => _TaxReview(
              bid,
              '$classification / $supply',
              rate,
              hsn.isEmpty ? 'MISSING' : hsn,
              uqc.isEmpty ? 'MISSING' : uqc,
            ),
          );
          for (final bucket in [g, h]) {
            bucket.add(
              sign * (value ?? 0),
              lc == null ? null : sign * lc,
              ls == null ? null : sign * ls,
              actualIgst == null ? null : sign * actualIgst,
              sign * lineCess,
              sign * (qty ?? 0),
              '${inv['_id']}',
            );
            if (value == null) bucket.valueValid = false;
            if (qty == null) bucket.quantityValid = false;
          }
        }
        if (lines.isEmpty ||
            lineTaxable != sign * (taxable ?? 0) ||
            lineTax !=
                sign * ((cgst ?? 0) + (sgst ?? 0) + (igst ?? 0) + cess)) {
          taxInvalid = true;
          issue(
            scopeId,
            'GST_TOTAL_MISMATCH',
            'invoices/${inv['_id']}: line taxable/tax ${FinancialReconciliation.money(lineTaxable)}/${FinancialReconciliation.money(lineTax)} versus saved header ${FinancialReconciliation.money(sign * (taxable ?? 0))}/${FinancialReconciliation.money(sign * ((cgst ?? 0) + (sgst ?? 0) + (igst ?? 0) + cess))}; missing lines or mismatch',
          );
        }
        final dt = _dateFields(inv, [
          'invoiceDate',
          'createdAt',
        ])!.add(const Duration(minutes: 330));
        final month = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        if (!internalSale) {
          (monthly.putIfAbsent(month, () => [0, 0, 0]))[0] +=
              sign * (taxable ?? 0);
        }
      }
      // Outstanding amounts are current snapshots. Never backdate mutable balances.
      for (final inv in invoices) {
        if (_internal(inv)) continue;
        final dt = _dateFields(inv, ['invoiceDate', 'createdAt']);
        final due = _integer(inv, ['dueAmount']);
        if (dt == null || !dt.isBefore(end) || due == null || due <= 0) {
          continue;
        }
        final days = end
            .subtract(const Duration(microseconds: 1))
            .difference(dt)
            .inDays;
        debtorRows.add([
          scopeId,
          '${inv['_id']}',
          '${inv['customerName'] ?? inv['customerId'] ?? 'Unspecified'}',
          FinancialReconciliation.money(due),
          days <= 30
              ? '0-30'
              : days <= 60
              ? '31-60'
              : days <= 90
              ? '61-90'
              : days <= 180
              ? '91-180'
              : '>180',
          'CURRENT balance; historical receipts not fully linked',
        ]);
        r.debtors += due;
      }
      for (final bill in rows(
        'purchase_bills',
      ).where((b) => '${b['status']}'.toUpperCase() == 'APPROVED')) {
        if (!inPeriod(bill, [
          'invoiceDate',
          'purchaseDate',
        ], 'purchase_bills')) {
          continue;
        }
        final internalPurchase = _internal(bill);
        if (internalPurchase) {
          transferRows.add([
            scopeId,
            'purchase_bills/${bill['_id']}',
            'Excluded internal transfer',
            'Not external purchase',
          ]);
        }
        final taxable = _integer(bill, ['taxableAmount']);
        final cgst = _integer(bill, ['cgstAmount']),
            sgst = _integer(bill, ['sgstAmount']),
            igst = _integer(bill, ['igstAmount']);
        final grand = _integer(bill, ['grandTotal']);
        if (taxable == null ||
            cgst == null ||
            sgst == null ||
            igst == null ||
            grand == null) {
          purchaseInvalid = true;
          r.purchasesValid = false;
          issue(
            scopeId,
            'PURCHASE_FIELDS_MISSING',
            'purchase_bills/${bill['_id']}: approved bill totals incomplete',
          );
        }
        if (!internalPurchase) r.purchases += taxable ?? 0;
        r.inputTax += (cgst ?? 0) + (sgst ?? 0) + (igst ?? 0);
        r.direct += _integer(bill, ['chargesAmount']) ?? 0;
        if (taxable != null) {
          trace('purchase_bills', bill, 'taxableAmount; GST excluded', taxable);
        }
        if (grand != null &&
            taxable != null &&
            cgst != null &&
            sgst != null &&
            igst != null &&
            grand !=
                taxable +
                    cgst +
                    sgst +
                    igst +
                    (_integer(bill, ['chargesAmount']) ?? 0) +
                    (_integer(bill, ['roundOff']) ?? 0)) {
          purchaseInvalid = true;
          r.purchasesValid = false;
          issue(
            scopeId,
            'PURCHASE_TOTAL_MISMATCH',
            'purchase_bills/${bill['_id']} total mismatch',
          );
        }
      }
      for (final bill in rows(
        'purchase_bills',
      ).where((b) => '${b['status']}'.toUpperCase() == 'APPROVED')) {
        if (_internal(bill)) continue;
        final dt = _dateFields(bill, ['invoiceDate']);
        final due = _integer(bill, ['outstandingAmount']);
        if (dt == null || !dt.isBefore(end) || due == null || due <= 0) {
          continue;
        }
        r.creditors += due;
        creditorRows.add([
          scopeId,
          '${bill['_id']}',
          '${bill['supplierName'] ?? bill['supplierId'] ?? 'NOT_VERIFIED'}',
          FinancialReconciliation.money(due),
          '${end.difference(_dateFields(bill, ['dueDate']) ?? dt).inDays}',
          'Current snapshot; MSME NOT_VERIFIED',
        ]);
      }
      for (final ret in rows('purchase_returns')) {
        if (!_active(ret) ||
            !inPeriod(ret, [
              'returnDate',
              'approvedAt',
              'createdAt',
            ], 'purchase_returns')) {
          continue;
        }
        // No universal taxable credit-note contract exists in the inspected writer.
        final value = _integer(ret, ['taxableAmountPaise', 'taxableAmount']);
        if (value == null || '${ret['status']}'.toUpperCase() != 'APPROVED') {
          purchaseInvalid = true;
          r.purchasesValid = false;
          issue(
            scopeId,
            'PURCHASE_RETURN_UNVERIFIED',
            'purchase_returns/${ret['_id']}: missing approved taxable credit snapshot',
          );
        } else {
          r.purchaseReturns += value;
          final rc = _integer(ret, ['cgstAmount', 'cgstPaise']);
          final rs = _integer(ret, ['sgstAmount', 'sgstPaise']);
          final ri = _integer(ret, ['igstAmount', 'igstPaise']);
          if (rc == null || rs == null || ri == null) {
            purchaseInvalid = true;
            r.purchasesValid = false;
            issue(
              scopeId,
              'RETURN_TAX_UNVERIFIED',
              'purchase_returns/${ret['_id']}: missing tax credit components',
            );
          } else {
            r.inputTax -= rc + rs + ri;
          }
          trace('purchase_returns', ret, 'taxableAmount', -value);
        }
      }
      final batchReview = _inventoryReview(
        rows('inventory_batches'),
        rows('inventory_batch_movements'),
        rows('stock_balances'),
        rows('stock_movements'),
        rows('purchase_bills'),
        rows('purchase_corrections'),
        start,
        end,
        scopeId,
        issue,
      );
      if ([
        'inventory_batches',
        'inventory_batch_movements',
        'stock_balances',
        'stock_movements',
      ].any((col) => !ready('$scopeId/$col'))) {
        batchReview.valid = false;
        batchReview.opening = null;
        batchReview.closing = null;
        batchReview.cogs = null;
        issue(
          scopeId,
          'INVENTORY_SYNC_INCOMPLETE',
          'Historical inventory scope has no completed covering synchronization checkpoint.',
        );
      }
      if (invoices.any(
            (i) => inPeriod(i, ['invoiceDate', 'createdAt'], 'invoices'),
          ) &&
          rows('inventory_batches').isEmpty) {
        batchReview.valid = false;
        batchReview.opening = null;
        batchReview.closing = null;
        batchReview.cogs = null;
        issue(
          scopeId,
          'SALES_COST_UNSUPPORTED',
          'Sales exist without a supported item/batch cost history.',
        );
      }
      for (final movement in rows(
        'inventory_batch_movements',
      ).where((m) => m['status'] == 'POSTED')) {
        final type = '${movement['movementType']}';
        if (type == 'SALE' || type == 'SALE_RETURN') {
          if (!invoices.any(
            (inv) =>
                _invoiceAliases(inv).contains('${movement['referenceId']}'),
          )) {
            batchReview.valid = false;
            issue(
              scopeId,
              'ORPHAN_SALE_REFERENCE',
              'Movement ${movement['_id']} has no authorized persisted sales invoice reference.',
            );
          }
        } else if (type == 'PURCHASE_RECEIPT' &&
            !rows('goods_receipts').any(
              (g) =>
                  (g['goodsReceiptId'] ?? g['_id']) == movement['referenceId'],
            )) {
          batchReview.valid = false;
          issue(
            scopeId,
            'ORPHAN_RECEIPT_REFERENCE',
            'Movement ${movement['_id']} has no persisted goods receipt.',
          );
        }
      }
      for (final inv in invoices.where(
        (inv) =>
            inPeriod(inv, ['invoiceDate', 'createdAt'], 'invoices') &&
            !_internal(inv),
      )) {
        final lines = inv['items'];
        if (lines is! List) continue;
        final expected = <String, int>{};
        for (final line in lines.whereType<Map>().where(
          (l) => l['trackStock'] != false,
        )) {
          final base = line['quantityBase'];
          final variant = line['variantId'];
          if (base is! num ||
              !base.isFinite ||
              variant is! String ||
              variant.isEmpty ||
              base * 1000 != (base * 1000).roundToDouble()) {
            batchReview.valid = false;
            issue(
              scopeId,
              'LINE_UNIT_SNAPSHOT_MISSING',
              'invoices/${inv['_id']}: persisted base quantity/variant is unavailable; no scale heuristic used.',
            );
          } else {
            expected[variant] =
                (expected[variant] ?? 0) + (base * 1000).round();
          }
        }
        final aliases = _invoiceAliases(inv);
        final returnInvoice =
            '${inv['documentType'] ?? inv['type']}'.toUpperCase() ==
            'SALES_RETURN';
        for (final entry in expected.entries) {
          final moved = rows('inventory_batch_movements')
              .where(
                (m) =>
                    m['status'] == 'POSTED' &&
                    m['movementType'] ==
                        (returnInvoice ? 'SALE_RETURN' : 'SALE') &&
                    m['variantId'] == entry.key &&
                    aliases.contains(m['referenceId']),
              )
              .fold<int>(0, (sum, m) => sum + (_integer(m, ['quantity']) ?? 0));
          if (moved != entry.value) {
            batchReview.valid = false;
            issue(
              scopeId,
              'SALES_BATCH_QUANTITY_MISMATCH',
              'invoices/${inv['_id']}/${entry.key}: snapshot base qty ${entry.value} thousandths != linked batch qty $moved.',
            );
          }
        }
      }
      if (!batchReview.valid) {
        batchReview.opening = null;
        batchReview.closing = null;
        batchReview.cogs = null;
      }
      inventoryRows.addAll(batchReview.rows);
      evidence.addAll(batchReview.evidence);
      transferRows.addAll(batchReview.transfers);
      r.opening = batchReview.opening;
      r.closing = batchReview.closing;
      r.costOfSales = batchReview.cogs;
      inventoryInvalid |= !batchReview.valid;
      for (final event in rows('financial_transactions')) {
        if ('${event['status']}'.toUpperCase() != 'POSTED' ||
            !inPeriod(event, ['transactionDate'], 'financial_transactions')) {
          continue;
        }
        if (!knownFinancialIds.add('${event['_id']}')) continue;
        final mode = '${event['paymentMode']}'.toUpperCase();
        final type = '${event['transactionType']}'.toUpperCase();
        if (mode.contains('NON_CASH') ||
            mode == 'ADVANCE' ||
            _internal(event)) {
          continue;
        }
        if (!_cashMode(mode)) {
          cashInvalid = true;
          issue(
            scopeId,
            'CASH_MODE_UNVERIFIED',
            'financial_transactions/${event['_id']}: missing or unsupported actual payment mode',
          );
          continue;
        }
        final amount = _integer(event, ['amount']);
        if (amount == null || !['IN', 'OUT'].contains(event['direction'])) {
          cashInvalid = true;
          issue(
            scopeId,
            'CASH_EVENT_INVALID',
            'financial_transactions/${event['_id']} invalid amount/direction',
          );
          continue;
        }
        final signed = event['direction'] == 'IN' ? amount : -amount;
        r.cashMovement += signed;
        for (final ref in [
          event['_id'],
          event['transactionId'],
          event['referenceId'],
        ]) {
          if (ref != null) countedCashReferences.add('$bid/$ref');
        }
        cashRows.add([
          scopeId,
          'financial_transactions/${event['_id']}',
          type,
          mode,
          FinancialReconciliation.money(signed),
        ]);
        trace(
          'financial_transactions',
          event,
          'amount; actual cash/bank event',
          signed,
        );
      }
      for (final payment in businessRows('payments')) {
        if (!_active(payment)) continue;
        final inv = allInvoiceIds['${payment['invoiceId']}'];
        if (inv == null ||
            _internal(inv) ||
            !inPeriod(payment, ['transactionDate', 'createdAt'], 'payments')) {
          continue;
        }
        if (!knownPaymentIds.add('${payment['_id']}')) continue;
        final mode = '${payment['mode'] ?? payment['paymentMode']}'
            .toUpperCase();
        if ([
          'ADVANCE',
          'NON_CASH',
          'SALARY_OFFSET',
          'STORE_CREDIT_ADJUSTMENT',
        ].contains(mode)) {
          continue;
        }
        final amount = _integer(payment, ['amountPaise']);
        if (amount == null || !_cashMode(mode)) {
          cashInvalid = true;
          issue(
            scopeId,
            'PAYMENT_MODE_UNVERIFIED',
            'payments/${payment['_id']} unknown mode or amount',
          );
          continue;
        }
        if (wasCashCounted(bid, payment['paymentId'] ?? payment['_id'])) {
          continue;
        }
        // StaffSalaryRepository persists PAY-SP-<request> and FIN-SPAY-<request>
        // for the same real store-purchase collection. Reuse that exact saved identity contract.
        final paymentId = '${payment['paymentId'] ?? payment['_id']}';
        if (paymentId.startsWith('PAY-SP-') &&
            wasCashCounted(bid, 'FIN-SPAY-${paymentId.substring(7)}')) {
          final finance = rows('financial_transactions')
              .where(
                (f) =>
                    (f['transactionId'] ?? f['_id']) ==
                    'FIN-SPAY-${paymentId.substring(7)}',
              )
              .firstOrNull;
          if (finance == null ||
              finance['amount'] != amount ||
              finance['referenceId'] != payment['invoiceId']) {
            cashInvalid = true;
            issue(
              scopeId,
              'STAFF_REPAYMENT_CASH_MISMATCH',
              'payments/$paymentId disagrees with its persisted FIN-SPAY event.',
            );
          }
          continue;
        }
        // Payments are authoritative for customer collections; never also use invoice.paidPaise.
        r.cashMovement += amount;
        if (mode == 'CASH') {
          r.cashCollections += amount;
        } else {
          r.digitalCollections += amount;
        }
        cashRows.add([
          scopeId,
          'payments/${payment['_id']}',
          'CUSTOMER_COLLECTION',
          mode,
          FinancialReconciliation.money(amount),
        ]);
        trace('payments', payment, 'amountPaise', amount);
      }
      for (final payment in rows('supplier_payments')) {
        if ('${payment['status']}'.toUpperCase() != 'POSTED' ||
            !inPeriod(payment, [
              'paymentDate',
              'createdAt',
            ], 'supplier_payments')) {
          continue;
        }
        if (wasCashCounted(bid, payment['paymentId'] ?? payment['_id'])) {
          continue;
        }
        final amount = _integer(payment, ['amount']);
        if (amount == null) {
          cashInvalid = true;
          continue;
        }
        r.cashMovement -= amount;
        cashRows.add([
          scopeId,
          'supplier_payments/${payment['_id']}',
          'SUPPLIER_PAYMENT',
          '${payment['paymentMode']}',
          FinancialReconciliation.money(-amount),
        ]);
        trace('supplier_payments', payment, 'amount', -amount);
      }
      for (final refund in rows('supplier_refunds')) {
        if (refund['status'] != 'POSTED' ||
            !inPeriod(refund, ['refundDate'], 'supplier_refunds')) {
          continue;
        }
        if (wasCashCounted(bid, refund['financialTransactionId']) ||
            wasCashCounted(bid, refund['refundId'] ?? refund['_id'])) {
          continue;
        }
        final amount = _integer(refund, ['amount']);
        if (amount == null || !_cashMode('${refund['paymentMode']}')) {
          cashInvalid = true;
          issue(
            scopeId,
            'REFUND_CASH_UNVERIFIED',
            'Supplier refund ${refund['_id']} has unsupported amount/mode.',
          );
          continue;
        }
        r.cashMovement += amount;
        cashRows.add([
          scopeId,
          'supplier_refunds/${refund['_id']}',
          'SUPPLIER_REFUND',
          '${refund['paymentMode']}',
          FinancialReconciliation.money(amount),
        ]);
        trace('supplier_refunds', refund, 'amount', amount);
      }
      // Legacy active expense documents are the expense system's payment record.
      // Accrual-only/linked payroll entries are excluded; matching financial events are counted once.
      for (final exp in businessRows(
        'expenses',
      ).where((e) => e['outletId'] == oid)) {
        if (!_active(exp) || !inPeriod(exp, ['expenseDate'], 'expenses')) {
          continue;
        }
        final amount = _integer(exp, ['amountPaise']);
        final classification = _expenseClass(exp);
        if (classification == 'UNCLASSIFIED' ||
            (classification == 'DIRECT_INWARD' && amount == null))
          directInvalid = true;
        if (!salaryAllowed && classification == 'PAYROLL') {
          expenseInvalid = true;
          continue;
        }
        if (amount == null ||
            ![
              'OPERATING',
              'DIRECT_INWARD',
              'CAPITAL',
              'DRAWINGS',
              'NON_OPERATING',
              'PAYROLL',
            ].contains(classification)) {
          expenseInvalid = true;
          issue(
            scopeId,
            'EXPENSE_CLASSIFICATION',
            'expenses/${exp['_id']}: recorded expense needs operating/capital/direct/drawings classification',
          );
        }
        if (classification == 'DIRECT_INWARD') {
          r.direct += amount ?? 0;
        } else if (classification == 'OPERATING')
          r.operating += amount ?? 0;
        if (classification == 'NON_OPERATING') r.nonOperating += amount ?? 0;
        if (classification == 'PAYROLL' && exp['salaryPeriodId'] == null) {
          expenseInvalid = true;
          issue(
            scopeId,
            'LEGACY_PAYROLL_EXPENSE',
            'expenses/${exp['_id']}: wages not linked to an approved salary period; duplicate/accrual coverage requires review.',
          );
        }
        final financialMatch = wasCashCounted(
          bid,
          exp['expenseId'] ?? exp['_id'],
        );
        final mode = '${exp['paymentMode'] ?? ''}'.toUpperCase();
        if (!financialMatch &&
            amount != null &&
            ['CASH', 'UPI', 'BANK_TRANSFER', 'CHEQUE', 'CARD'].contains(mode) &&
            classification != 'PAYROLL' &&
            exp['recognitionBasis'] != 'ACCRUAL') {
          r.cashMovement -= amount;
          cashRows.add([
            scopeId,
            'expenses/${exp['_id']}',
            'EXPENSE_PAYMENT',
            mode,
            FinancialReconciliation.money(-amount),
          ]);
        }
        // Linked payroll expenses are excluded: approved salary periods recognize wages once.
        expenseRows.add([
          scopeId,
          'expenses/${exp['_id']}',
          '${exp['category']}',
          FinancialReconciliation.money(amount),
          classification.isEmpty
              ? 'UNCLASSIFIED - excluded pending review'
              : classification,
        ]);
        if (amount != null) {
          trace(
            'expenses',
            exp,
            'amountPaise; classification=$classification',
            amount,
          );
        }
      }
      if (salaryAllowed) {
        if (!ready('$bid/staff') || !ready('$bid/employee_salary_profiles'))
          salaryInvalid = true;
        for (final staff in businessRows('staff').where(_active)) {
          final employeeId = staff['employeeId'] ?? staff['_id'];
          if (!businessRows('employee_salary_profiles').any(
                (p) =>
                    p['employeeId'] == employeeId &&
                    _active(p) &&
                    _dateFields(p, ['effectiveFrom'])?.isBefore(end) == true &&
                    (_dateFields(p, ['effectiveTo']) == null ||
                        _dateFields(p, ['effectiveTo'])!.isAfter(start)),
              ) &&
              !businessRows('salary_periods').any(
                (p) =>
                    p['employeeId'] == employeeId &&
                    [
                      'APPROVED',
                      'PARTIALLY_PAID',
                      'PAID',
                      'SETTLED',
                    ].contains(p['status']) &&
                    _dateFields(p, ['periodStart'])?.isBefore(end) == true &&
                    _dateFields(p, ['periodEnd'])?.isBefore(start) == false,
              )) {
            salaryInvalid = true;
            issue(
              scopeId,
              'STAFF_PAYROLL_COVERAGE',
              'Assigned staff have no salary profile or approved accrual evidence for this period; zero payroll cannot be verified.',
            );
          }
        }
        for (final profile in businessRows(
          'employee_salary_profiles',
        ).where(_active)) {
          final effectiveFrom = _dateFields(profile, ['effectiveFrom']);
          final effectiveTo = _dateFields(profile, ['effectiveTo']);
          if (effectiveFrom == null) {
            salaryInvalid = true;
            issue(
              scopeId,
              'PROFILE_DATE_UNAVAILABLE',
              'Salary profile effective date is missing.',
            );
          }
          if (effectiveFrom == null ||
              !effectiveFrom.isBefore(end) ||
              (effectiveTo != null && !effectiveTo.isAfter(start))) {
            continue;
          }
          if (!businessRows('salary_periods').any(
            (p) =>
                p['profileId'] == (profile['profileId'] ?? profile['_id']) &&
                _dateFields(p, ['periodEnd'])?.isBefore(start) == false &&
                _dateFields(p, ['periodStart'])?.isBefore(end) == true &&
                [
                  'APPROVED',
                  'PARTIALLY_PAID',
                  'PAID',
                  'SETTLED',
                ].contains('${p['status']}'.toUpperCase()),
          )) {
            salaryInvalid = true;
            issue(
              scopeId,
              'SALARY_ACCRUAL_COVERAGE',
              'An effective salary profile lacks an approved earning-period accrual in this reporting interval.',
            );
          }
        }
        final events = businessRows('staff_khata_transactions')
            .where((e) => '${e['status']}'.toUpperCase() == 'POSTED')
            .toList();
        for (final period in businessRows('salary_periods').where(
          (p) => [
            'APPROVED',
            'PARTIALLY_PAID',
            'PAID',
            'SETTLED',
          ].contains('${p['status']}'.toUpperCase()),
        )) {
          final periodStart = _dateFields(period, ['periodStart']);
          final periodEnd = _dateFields(period, ['periodEnd']);
          final allocations = period['outletExpensesPaise'];
          if (periodStart == null || periodEnd == null || allocations is! Map) {
            salaryInvalid = true;
            issue(
              scopeId,
              'SALARY_ALLOCATION_MISSING',
              'salary_periods/${period['_id']}: period dates/allocation snapshot unavailable',
            );
            continue;
          }
          final allocated = allocations[oid];
          if (allocated is! num) continue;
          final expenseTotal = _integer(period, ['expenseAmountPaise']);
          final allocatedTotal = allocations.values.fold<int>(
            0,
            (s, v) => s + (v is num ? v.toInt() : 0),
          );
          if (expenseTotal == null || allocatedTotal != expenseTotal) {
            salaryInvalid = true;
            issue(
              scopeId,
              'SALARY_ALLOCATION_MISMATCH',
              'salary_periods/${period['_id']} allocations != expenseAmountPaise',
            );
            continue;
          }
          if (periodEnd.isBefore(end) && !periodEnd.isBefore(start)) {
            if (periodStart.isBefore(start)) {
              salaryInvalid = true;
              issue(
                scopeId,
                'SALARY_PERIOD_OVERLAP',
                'salary_periods/${period['_id']}: earning period crosses reporting boundary; no saved daily accrual split',
              );
            } else {
              r.salary += allocated.toInt();
              trace(
                'salary_periods',
                period,
                'outletExpensesPaise.$oid',
                allocated.toInt(),
              );
            }
          } else if (periodStart.isBefore(end) && !periodEnd.isBefore(end)) {
            salaryInvalid = true;
            issue(
              scopeId,
              'SALARY_PERIOD_OVERLAP',
              'salary_periods/${period['_id']}: partial earning period requires supported accrual split',
            );
          }
          if (!periodEnd.isBefore(end)) continue;
          final net = _integer(period, ['netEarnedPaise']);
          final periodEvents = events.where(
            (e) =>
                e['periodId'] == (period['periodId'] ?? period['_id']) &&
                _dateFields(e, ['transactionDate'])?.isBefore(end) == true,
          );
          final settled = periodEvents
              .where(
                (e) => [
                  'SALARY_PAYMENT',
                  'ADVANCE_ADJUSTMENT',
                  'STORE_CREDIT_ADJUSTMENT',
                ].contains(e['transactionType']),
              )
              .fold<int>(0, (s, e) => s + (_integer(e, ['amountPaise']) ?? 0));
          final liability = net == null ? null : net - settled;
          if (liability == null || liability < 0) {
            salaryInvalid = true;
            issue(
              scopeId,
              'SALARY_LIABILITY_UNVERIFIED',
              'salary_periods/${period['_id']}: negative or missing net liability',
            );
          } else {
            salaryLiabilities['$bid/${period['_id']}'] = liability;
          }
          // Liability allocations are not inferred from expense proportions.
          payrollRows.add([
            bid,
            'salary_periods/${period['_id']}',
            oid,
            FinancialReconciliation.money(allocated.toInt()),
            FinancialReconciliation.money(liability),
            'Business liability; not an outlet liability allocation',
          ]);
        }
        for (final e in events.where(
          (e) =>
              e['outletId'] == oid &&
              _dateFields(e, ['transactionDate'])?.isBefore(end) == true,
        )) {
          final amount = _integer(e, ['amountPaise']);
          if (amount == null) {
            salaryInvalid = true;
            continue;
          }
          if ([
            'CASH_ADVANCE',
            'UPI_ADVANCE',
            'BANK_ADVANCE',
          ].contains(e['transactionType'])) {
            r.advances += amount;
          }
          if (e['transactionType'] == 'ADVANCE_ADJUSTMENT') {
            r.advances -= amount;
          }
          if (e['paymentMode'] != 'NON_CASH' &&
              [
                'SALARY_PAYMENT',
                'CASH_ADVANCE',
                'UPI_ADVANCE',
                'BANK_ADVANCE',
              ].contains(e['transactionType']) &&
              !rows('financial_transactions').any(
                (f) =>
                    (f['transactionId'] ?? f['_id']) ==
                    e['financialTransactionId'],
              )) {
            salaryInvalid = true;
            cashInvalid = true;
            issue(
              scopeId,
              'PAYROLL_CASH_LINK_MISSING',
              'staff_khata_transactions/${e['_id']}: missing financial cash event',
            );
          }
          trace(
            'staff_khata_transactions',
            e,
            'amountPaise; ${e['transactionType']}',
            amount,
          );
          if (e['transactionType'] == 'STORE_CREDIT_ADJUSTMENT') {
            issue(
              scopeId,
              'STAFF_OFFSET_REVIEW',
              'staff_khata_transactions/${e['_id']}: noncash offset; POS receivable linkage requires verification',
            );
          }
        }
      }
    }
    // Business-level overheads are included once only for a full-business scope.
    var unallocated = 0;
    var unallocatedDirect = 0;
    var unallocatedNonOperating = 0;
    var businessCashMovement = 0;
    for (final bid in requestedBusinesses) {
      final includedIds = selected
          .where((o) => o['businessId'] == bid)
          .map((o) => o['outletId'])
          .toSet();
      final allIds = outlets
          .where((o) => o['businessId'] == bid)
          .map((o) => o['outletId'] ?? o['_id'])
          .toSet();
      final fullBusiness = includedIds.containsAll(allIds);
      for (final exp in _decoded(
        snapshot,
        '$bid/expenses',
      ).where((e) => e['outletId'] == null || e['outletId'] == '')) {
        final dt = _dateFields(exp, ['expenseDate']);
        if (_active(exp) && dt == null) {
          expenseInvalid = true;
          if (['DIRECT_INWARD', 'UNCLASSIFIED'].contains(_expenseClass(exp)))
            directInvalid = true;
          issue(
            bid,
            'MISSING_EXPENSE_DATE',
            'expenses/${exp['_id']}: business expense date unavailable',
          );
        }
        if (!_active(exp) ||
            dt == null ||
            dt.isBefore(start) ||
            !dt.isBefore(end)) {
          continue;
        }
        final amount = _integer(exp, ['amountPaise']);
        final cls = _expenseClass(exp);
        if (cls == 'UNCLASSIFIED' ||
            (cls == 'DIRECT_INWARD' && (!fullBusiness || amount == null)))
          directInvalid = true;
        if (!salaryAllowed && cls == 'PAYROLL') {
          expenseInvalid = true;
          continue;
        }
        expenseRows.add([
          bid,
          'expenses/${exp['_id']}',
          '${exp['category']}',
          FinancialReconciliation.money(amount),
          fullBusiness
              ? 'Unallocated business expense: $cls'
              : 'Not allocated to selected outlets',
        ]);
        if (fullBusiness &&
            amount != null &&
            cls != 'PAYROLL' &&
            exp['recognitionBasis'] != 'ACCRUAL' &&
            _cashMode('${exp['paymentMode']}')) {
          final hasFinancial = selected
              .where((o) => o['businessId'] == bid)
              .any(
                (o) =>
                    _decoded(
                      snapshot,
                      '$bid/${o['outletId']}/financial_transactions',
                    ).any(
                      (f) =>
                          f['status'] == 'POSTED' &&
                          f['referenceId'] == (exp['expenseId'] ?? exp['_id']),
                    ),
              );
          if (!hasFinancial) {
            businessCashMovement -= amount;
            cashRows.add([
              bid,
              'expenses/${exp['_id']}',
              'BUSINESS_EXPENSE_PAYMENT',
              '${exp['paymentMode']}',
              FinancialReconciliation.money(-amount),
            ]);
          }
        }
        if (amount != null) {
          evidence.add([
            bid,
            'expenses/${exp['_id']}',
            'amountPaise; unallocated business expense',
            FinancialReconciliation.money(amount),
            '$dt',
            '${exp['_sync']}',
          ]);
        }
        if (fullBusiness && cls == 'OPERATING' && amount != null) {
          unallocated += amount;
        } else if (fullBusiness && cls == 'DIRECT_INWARD' && amount != null) {
          unallocatedDirect += amount;
        } else if (fullBusiness && cls == 'NON_OPERATING' && amount != null) {
          unallocatedNonOperating += amount;
        } else if (fullBusiness &&
            ['CAPITAL', 'DRAWINGS', 'PAYROLL'].contains(cls) &&
            amount != null) {
          /* separated from operating expense */
        } else {
          expenseInvalid = true;
          issue(
            bid,
            'UNALLOCATED_BUSINESS_EXPENSE',
            'expenses/${exp['_id']}: no saved allocation or supported accounting class',
          );
        }
      }
    }
    int sum(int Function(_OutletReview) field) =>
        results.fold(0, (s, r) => s + field(r));
    int? nullableSum(int? Function(_OutletReview) field) =>
        results.any((r) => field(r) == null) ? null : sum((r) => field(r)!);
    final opening = nullableSum((r) => r.opening),
        closing = nullableSum((r) => r.closing),
        cogs = nullableSum((r) => r.costOfSales);
    final sales = salesInvalid ? null : sum((r) => r.sales);
    final purchases = purchaseInvalid
        ? null
        : sum((r) => r.purchases - r.purchaseReturns);
    final direct = sum((r) => r.direct) + unallocatedDirect;
    final directValue = directInvalid || purchaseInvalid ? null : direct;
    final inventoryEquation =
        opening == null ||
            closing == null ||
            purchases == null ||
            directValue == null
        ? null
        : opening + purchases + directValue - closing;
    final cogsDifference = inventoryEquation == null || cogs == null
        ? null
        : inventoryEquation - cogs;
    if (cogsDifference != null && cogsDifference != 0) {
      issue(
        'CONSOLIDATED',
        'COGS_NOT_RECONCILED',
        'Opening + net purchases + direct costs - closing differs from batch cost of sales by ${FinancialReconciliation.money(cogsDifference)}. Transfers/adjustments and unmatched receipts require review.',
      );
    }
    final grossProfit =
        sales == null || cogs == null || inventoryInvalid || cogsDifference != 0
        ? null
        : sales - cogs;
    final operating = expenseInvalid
        ? null
        : sum((r) => r.operating) + unallocated;
    final salary = salaryAllowed && !salaryInvalid
        ? sum((r) => r.salary)
        : null;
    final profit = grossProfit == null || operating == null || salary == null
        ? null
        : grossProfit - operating - salary;
    final limitations = [
      'Combined business totals are an explicitly selected management view. GST schedules remain separated by business; no cross-registration ITC settlement or unsupported inter-business balance elimination is performed.',
      'Internal automated review only. Not a statutory audit, CA certification, tax advice or filing approval.',
      'INR integer paise; inclusive India calendar dates (UTC+05:30), exclusive next-day boundary. Sales: invoiceDate/createdAt. Purchases: invoiceDate. Expenses: expenseDate. Cash: transactionDate. Salary: saved earning-period allocations.',
      'Current customer/supplier balances are shown as observed snapshots, not asserted historical balances. Aging uses report end. Complete receipt allocation and opening balances are unavailable.',
      'Historical fixed assets, depreciation, opening cash/bank, capital, drawings and retained earnings are not established by existing contracts. Balance sheet and closing cash remain INSUFFICIENT DATA.',
      'Batch costing uses immutable batch movements and approved bill taxable cost plus allocated bill charges, quantities in thousandths. Current catalogue selling prices are never inventory costs. Legacy stock without consistent units/cost history is unavailable.',
      'Input GST is observed purchase tax, not verified eligible ITC. Statutory cash thresholds, MSME rules, 44AD eligibility and invoice continuity require independent review.',
      'Business overheads are included once when every business outlet is selected; no allocation is invented. Payroll liability is business-level unless saved settlement allocations support outlet liabilities.',
      salaryAllowed
          ? 'Salary information is owner-authorized with historical allocation and settlement evidence; employee names are omitted.'
          : 'Salary and confidential financial event data are excluded by permission; expense and cash coverage is incomplete.',
      'Local snapshot completeness is limited to displayed sync checkpoints; it does not prove the absence of newer remote transactions. Report reads never initiate synchronization.',
    ];
    final checks = <AuditValidation>[
      AuditValidation(
        'Sales reconciliation',
        salesInvalid
            ? (issues.any(
                    (i) => [
                      'INVOICE_TOTAL_MISMATCH',
                      'INVOICE_NUMBER',
                    ].contains(i[1]),
                  )
                  ? 'FAIL'
                  : 'NOT_VERIFIED')
            : 'PASS',
        10,
        'Saved net taxable revenue versus header totals; no second discount deduction.',
      ),
      AuditValidation(
        'Purchases reconciliation',
        purchaseInvalid
            ? (issues.any((i) => i[1] == 'PURCHASE_TOTAL_MISMATCH')
                  ? 'FAIL'
                  : 'NOT_VERIFIED')
            : 'PASS',
        10,
        'Approved bills only, actual purchase GST components; returns require approved credit evidence.',
      ),
      AuditValidation(
        'COGS and stock reconciliation',
        inventoryInvalid || cogsDifference != 0
            ? (cogsDifference == null &&
                      !issues.any(
                        (i) => [
                          'STOCK_BATCH_QUANTITY_MISMATCH',
                          'DUPLICATE_MOVEMENT',
                          'ORPHAN_BATCH',
                          'NEGATIVE_STOCK_HISTORY',
                        ].contains(i[1]),
                      )
                  ? 'NOT_VERIFIED'
                  : 'FAIL')
            : 'PASS',
        15,
        'Batch movement cost versus opening + purchases + inward costs - closing. Difference: ${FinancialReconciliation.money(cogsDifference)}',
      ),
      AuditValidation(
        'Trading account balance',
        grossProfit == null ? 'NOT_VERIFIED' : 'PASS',
        10,
        'No balancing profit is invented. Missing historical inventory blocks trading conclusion.',
      ),
      const AuditValidation(
        'Balance sheet completeness',
        'NOT_VERIFIED',
        10,
        'Opening trial balance, assets, capital and bank evidence unavailable.',
      ),
      AuditValidation(
        'Cash and bank reconciliation',
        'NOT_VERIFIED',
        10,
        cashInvalid
            ? 'Invalid or missing dated cash events; opening/closing balances unavailable.'
            : 'Actual supported events shown; opening and closing balances unavailable.',
      ),
      AuditValidation(
        'GST and HSN completeness',
        taxInvalid
            ? (issues.any(
                    (i) => [
                      'GST_TOTAL_MISMATCH',
                      'GST_RATE_AMOUNT_MISMATCH',
                      'LINE_TAX_MISMATCH',
                      'INTERSTATE_COMPONENT_CONFLICT',
                    ].contains(i[1]),
                  )
                  ? 'FAIL'
                  : 'NOT_VERIFIED')
            : 'PASS',
        10,
        'All invoice snapshots must reconcile with HSN/rate/component schedules. Unknown classification is not zero GST.',
      ),
      const AuditValidation(
        'Customer and supplier balances',
        'NOT_VERIFIED',
        5,
        'Current observations cannot prove historical as-of reconciliations.',
      ),
      AuditValidation(
        'Salary and expense coverage',
        salaryInvalid || expenseInvalid ? 'NOT_VERIFIED' : 'PASS',
        10,
        'Saved salary allocations; unclassified expenses and partial salary periods block complete coverage.',
      ),
      AuditValidation(
        'Outlet and synchronization coverage',
        syncComplete ? 'PASS' : 'NOT_VERIFIED',
        10,
        'Each source must have a completed covering local query, no pending records and no unresolved conflicts. Observed pending=$pending.',
      ),
    ];
    final metrics = <String, int?>{
      'Net revenue excluding GST': sales,
      'Sales returns excluding GST': salesInvalid
          ? null
          : sum((r) => r.salesReturns),
      'Invoice discounts already netted in revenue': salesInvalid
          ? null
          : sum((r) => r.discounts),
      'Purchase returns excluding GST': purchaseInvalid
          ? null
          : sum((r) => r.purchaseReturns),
      'Net purchases excluding GST': purchases,
      'Opening inventory': opening,
      'Direct inward costs': directValue,
      'Closing inventory': closing,
      'Batch cost of sales': cogs,
      'Periodic inventory equation': inventoryEquation,
      'COGS reconciliation difference': cogsDifference,
      'Gross profit / loss': grossProfit,
      'Operating expenses': operating,
      'Accrued salary expense': salary,
      'Unallocated business overhead included once': expenseInvalid
          ? null
          : unallocated,
      'Supported operating result before unsupported adjustments': profit,
      'Non-operating expenses': expenseInvalid
          ? null
          : sum((r) => r.nonOperating) + unallocatedNonOperating,
      'Non-operating income': null,
      'Tax liabilities': null,
      'Depreciation': null,
      'Profit before tax': null,
      'Accrued salary payable (business scope only)':
          salaryAllowed &&
              !salaryInvalid &&
              scope.mode != AuditScopeMode.selectedOutlet &&
              scope.mode != AuditScopeMode.selectedOutletsInBusiness
          ? salaryLiabilities.values.fold<int>(0, (s, v) => s + v)
          : null,
      'Internal transfer taxable bases excluded from revenue': sum(
        (r) => r.internalTaxable,
      ),
      'Observed output GST': taxInvalid ? null : sum((r) => r.outputTax),
      'Observed purchase GST (not eligible ITC)': purchaseInvalid
          ? null
          : sum((r) => r.inputTax),
      'Eligible ITC': null,
      'Historical trade receivables': null,
      'Historical supplier payables': null,
      'Employee advance receivables (observed events)': salaryAllowed
          ? sum((r) => r.advances)
          : null,
      'Fixed assets': null,
      'Capital and retained earnings': null,
      'Total balance sheet assets': null,
      'Total liabilities and equity': null,
      'Balance sheet difference': null,
      'Opening cash and bank': null,
      'Observed cash / bank net movement':
          sum((r) => r.cashMovement) + businessCashMovement,
      'Closing cash and bank': null,
    };
    final schedules = <AuditSchedule>[
      AuditSchedule('Business and outlet inclusion', const [
        'Business ID',
        'Business',
        'Outlet ID',
        'Outlet',
        'Inclusion',
        'Lifecycle',
      ], inclusionRows),
      AuditSchedule(
        'Business tax identities',
        const [
          'Business ID',
          'Business name',
          'Recorded GSTIN',
          'Currency',
          'Identity evidence',
        ],
        [
          for (final b in businesses)
            if (requestedBusinesses.contains(b['businessId'] ?? b['_id']))
              [
                '${b['businessId'] ?? b['_id']}',
                '${b['businessName']}',
                '${b['gstin'] ?? 'MISSING - NOT_VERIFIED'}',
                '${b['currency'] ?? 'INR (existing paise contract)'}',
                b['gstinVerified'] == true
                    ? 'Recorded verification; historical identity still requires invoice snapshots'
                    : 'NOT_VERIFIED',
              ],
        ],
        note: 'Tax amounts remain grouped by business. Current business GST metadata is not a historical GST registration certification and input tax is not automatically eligible ITC.',
      ),
      AuditSchedule(
        'Executive financial summary',
        const ['Metric', 'Amount / status'],
        metrics.entries
            .map((e) => [e.key, FinancialReconciliation.money(e.value)])
            .toList(),
      ),
      AuditSchedule(
        'Outlet financial comparison',
        const [
          'Business / outlet',
          'Net revenue',
          'Net purchases',
          'Batch COGS',
          'Salary accrual',
          'Operating',
        ],
        results
            .map(
              (r) => [
                '${r.businessId}/${r.outletId}\n${r.name}',
                FinancialReconciliation.money(r.salesValid ? r.sales : null),
                FinancialReconciliation.money(
                  r.purchasesValid ? r.purchases - r.purchaseReturns : null,
                ),
                FinancialReconciliation.money(r.costOfSales),
                FinancialReconciliation.money(
                  salaryAllowed && !salaryInvalid ? r.salary : null,
                ),
                FinancialReconciliation.money(
                  expenseInvalid ? null : r.operating,
                ),
              ],
            )
            .toList()
          ..addAll([
            [
              'Unallocated business overhead',
              '-',
              '-',
              '-',
              '-',
              FinancialReconciliation.money(
                expenseInvalid ? null : unallocated,
              ),
            ],
            [
              'CONSOLIDATED TOTAL',
              FinancialReconciliation.money(sales),
              FinancialReconciliation.money(purchases),
              FinancialReconciliation.money(cogs),
              FinancialReconciliation.money(salary),
              FinancialReconciliation.money(operating),
            ],
          ]),
        note: 'Business expenses remain separately unallocated; the consolidated total equals outlets plus displayed unallocated business expenses.',
      ),
      AuditSchedule(
        'Trading account and profit and loss',
        const ['Particular', 'Amount / status'],
        [
          for (final key in [
            'Opening inventory',
            'Net purchases excluding GST',
            'Direct inward costs',
            'Closing inventory',
            'Batch cost of sales',
            'Periodic inventory equation',
            'COGS reconciliation difference',
            'Net revenue excluding GST',
            'Gross profit / loss',
            'Operating expenses',
            'Accrued salary expense',
            'Supported operating result before unsupported adjustments',
            'Non-operating expenses',
            'Non-operating income',
            'Depreciation',
            'Profit before tax',
          ])
            [key, FinancialReconciliation.money(metrics[key])],
        ],
        note: 'Return amounts are deducted once from purchases. A nonzero COGS difference prevents a reconciled profit statement.',
      ),
      AuditSchedule(
        'Balance sheet - supported components and missing balances',
        const ['Component', 'Amount / status'],
        [
          for (final key in [
            'Fixed assets',
            'Closing inventory',
            'Historical trade receivables',
            'Employee advance receivables (observed events)',
            'Opening cash and bank',
            'Closing cash and bank',
            'Historical supplier payables',
            'Accrued salary payable (business scope only)',
            'Tax liabilities',
            'Capital and retained earnings',
            'Total balance sheet assets',
            'Total liabilities and equity',
            'Balance sheet difference',
          ])
            [key, FinancialReconciliation.money(metrics[key])],
        ],
        note: 'INSUFFICIENT DATA: this is a partial component schedule. Assets = liabilities + equity is NOT RECONCILED without a supported opening trial balance and complete transaction history. No capital plug or estimated asset/cash figure is used.',
      ),
      AuditSchedule(
        'Cash-flow observed events',
        const ['Scope', 'Source', 'Event', 'Mode', 'Inflow / (outflow)'],
        cashRows,
        note: 'Actual collections and disbursements only. Advances, payroll settlements and expenses are not counted again from their parent documents. Noncash offsets are excluded. Opening/closing cash is unavailable.',
      ),
      AuditSchedule(
        'GST rate and classification reconciliation',
        const [
          'Business / class',
          'Rate',
          'Taxable',
          'CGST',
          'SGST',
          'IGST',
          'Cess',
        ],
        _taxScheduleRows(gstRows.values),
        note: 'Missing rates stay UNKNOWN; nil, exempt, non-GST and out-of-scope require an explicit snapshot classification.',
      ),
      AuditSchedule(
        'HSN / SAC reconciliation',
        const [
          'Business / class',
          'HSN / UQC / quantity',
          'Taxable',
          'CGST',
          'SGST',
          'IGST',
          'Cess',
        ],
        _taxScheduleRows(hsnRows.values, hsn: true),
        note: 'Quantities are saved invoice-line commercial quantities in their saved UQC; HSN and UQC are never copied from current catalogue data.',
      ),
      AuditSchedule('Item and outlet inventory audit', const [
        'Scope / batch / variant',
        'Opening qty',
        'Inward qty',
        'Outward qty',
        'Closing qty',
        'Opening / closing value',
        'Status',
      ], inventoryRows),
      AuditSchedule(
        'Inventory movement source detail',
        const [
          'Scope / variant',
          'Movement source',
          'Type / reference',
          'Inward base qty',
          'Outward base qty',
        ],
        [
          for (final o in selected)
            for (final m in _decoded(
              snapshot,
              '${o['businessId']}/${o['outletId']}/inventory_batch_movements',
            ))
              if (m['status'] == 'POSTED' &&
                  _dateFields(m, ['occurredAt'])?.isBefore(start) == false &&
                  _dateFields(m, ['occurredAt'])?.isBefore(end) == true)
                [
                  '${o['businessId']}/${o['outletId']}/${m['variantId']}',
                  'inventory_batch_movements/${m['_id']}',
                  '${m['movementType']} / ${m['referenceId'] ?? 'MISSING'}',
                  m['direction'] == 'IN' && m['quantity'] is num
                      ? '${(m['quantity'] as num) / 1000}'
                      : '0',
                  m['direction'] == 'OUT' && m['quantity'] is num
                      ? '${(m['quantity'] as num) / 1000}'
                      : '0',
                ],
        ],
        note: 'Posted batch quantities use thousandths. Purchases, sales, returns, adjustments and transfers remain separately identifiable; unknown historical costs are not invented.',
      ),
      AuditSchedule(
        'Internal transfer eliminations',
        const ['Scope', 'Source', 'Treatment', 'Evidence / limitation'],
        transferRows,
        note: 'Only explicit internal events are excluded. A complete inter-outlet receivable/payable ledger is unavailable; no hypothetical elimination is inserted.',
      ),
      AuditSchedule('Customer receivables and aging', const [
        'Scope',
        'Invoice',
        'Customer',
        'Observed due',
        'Days bucket',
        'Basis',
      ], debtorRows),
      AuditSchedule('Supplier payables and aging', const [
        'Scope',
        'Bill',
        'Supplier',
        'Observed due',
        'Days past due',
        'Basis',
      ], creditorRows),
      AuditSchedule(
        'Salary Khata and allocation snapshots',
        const [
          'Business',
          'Period',
          'Outlet',
          'Saved expense',
          'Business net liability',
          'Basis',
        ],
        payrollRows,
        note: 'The same business liability may be referenced by several outlet allocation rows: do not sum repeated references. Dated settlement events determine the liability; salary advances are receivables, never salary expense.',
      ),
      AuditSchedule('Operating expenses and unallocated overhead', const [
        'Scope',
        'Source',
        'Category',
        'Recorded amount',
        'Treatment',
      ], expenseRows),
      AuditSchedule(
        'Actual monthly activity',
        const ['India calendar month', 'Net revenue'],
        monthly.entries
            .map((e) => [e.key, FinancialReconciliation.money(e.value[0])])
            .toList(),
        note: 'Only actual invoice months in the requested period are shown; no synthetic annual extrapolation.',
      ),
      AuditSchedule(
        'Automated validation and scoring',
        const ['Check', 'Status', 'Weight / 100', 'Evidence criterion'],
        checks.map((c) => [c.id, c.status, '${c.weight}', c.details]).toList(),
        note: 'Only PASS earns its disclosed weight. Missing evidence earns zero. Score is internal data quality and cannot imply statutory certification.',
      ),
      const AuditSchedule(
        'Statutory validation checklist',
        ['Check', 'Status', 'Missing evidence'],
        [
          [
            'Cash threshold / aggregation checks',
            'NOT_VERIFIED',
            'Full party/day/event aggregation and current legal applicability',
          ],
          [
            'Invoice sequence continuity',
            'NOT_VERIFIED',
            'Complete series, cancellations and sequence registers',
          ],
          [
            'MSME payment obligations',
            'NOT_VERIFIED',
            'Verified supplier MSME classification and contractual terms',
          ],
          [
            'Presumptive taxation / audit exemption',
            'NOT_VERIFIED',
            'Taxpayer, profession, receipts, exclusions and current law',
          ],
          [
            'GST filing / eligible ITC',
            'NOT_VERIFIED',
            'Portal reconciliation, eligibility and complete statutory evidence',
          ],
        ],
      ),
      AuditSchedule('Exceptions and unresolved differences', const [
        'Scope',
        'Code',
        'Evidence / action',
      ], issues),
      AuditSchedule('Data completeness and sync checkpoints', const [
        'Source scope',
        'Records',
        'Coverage',
        'Last sync UTC',
        'Pending / conflicts',
      ], coverageRows),
      AuditSchedule('Source evidence index', const [
        'Scope',
        'Persisted document',
        'Field / basis',
        'Amount',
        'Transaction date UTC',
        'Sync state',
      ], evidence),
      AuditSchedule('Accounting assumptions and limitations', const [
        'Limitation',
      ], limitations.map((s) => [s]).toList()),
    ];
    final review = FinancialReconciliation(
      scopeLabel: scope.mode.label,
      generatedBy: uid,
      metrics: metrics,
      schedules: schedules,
      checks: checks,
      limitations: limitations,
    );
    final fyStart = dateRange.start.month >= 4
        ? dateRange.start.year
        : dateRange.start.year - 1;
    final g = identities.length == 1
        ? identities.single
        : 'MULTIPLE GST IDENTITIES - see business schedules';
    // Legacy field names remain compatible, with null for unsupported amounts.
    // Every report surface consumes the evidence schedules and nullable metrics.
    return FinancialAuditReportData(
      businessId: requestedBusinesses.join(','),
      outletId: selected.map((o) => o['outletId']).join(','),
      businessName: requestedBusinesses.length > 1
          ? businesses
                .where(
                  (b) =>
                      requestedBusinesses.contains(b['businessId'] ?? b['_id']),
                )
                .map((b) => '${b['businessName']}')
                .join(' + ')
          : businessName,
      outletName: selected.map((o) => o['outletName']).join(', '),
      tradeName: tradeName ?? businessName,
      legalName: legalName ?? businessName,
      gstin: g,
      pan: RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]$').hasMatch(g)
          ? g.substring(2, 12)
          : 'NOT_VERIFIED',
      stateCode: RegExp(r'^\d{2}').hasMatch(g)
          ? g.substring(0, 2)
          : 'NOT_VERIFIED',
      address: address ?? '',
      phone: phone ?? '',
      email: email ?? '',
      dateRange: dateRange,
      financialYearLabel: 'FY $fyStart-${fyStart + 1}',
      assessmentYearLabel: 'AY ${fyStart + 1}-${fyStart + 2}',
      generatedAt: DateTime.now().toUtc(),
      auditHealthScore: review.score,
      auditReadiness: review.status,
      auditorExecutiveSummary:
          'Automated data quality ${review.score}/100. ${review.status}. No professional audit opinion is provided.',
      hasHighRiskFlags: review.status != 'RECONCILED',
      grossSalesPaise: salesInvalid ? null : sum((r) => r.gross),
      salesReturnsDiscountsPaise: salesInvalid ? null : sum((r) => r.discounts),
      netTurnoverPaise: sales,
      openingStockPaise: opening,
      purchasesPaise: purchases,
      directExpensesPaise: directValue,
      closingStockPaise: closing,
      cogsPaise: cogs,
      grossProfitPaise: grossProfit,
      grossProfitMarginPct: grossProfit != null && sales != null && sales != 0
          ? grossProfit * 100 / sales
          : null,
      indirectExpensesPaise: operating,
      netProfitBeforeTaxPaise: null,
      netProfitMarginPct: null,
      presumptiveSection44AdProfitPaise: null,
      isEligibleForSection44Ad: null,
      ownersCapitalPaise: null,
      retainedEarningsPaise: null,
      sundryCreditorsPaise: null,
      statutoryDuesPaise: null,
      totalLiabilitiesPaise: null,
      fixedAssetsPaise: null,
      closingInventoryPaise: closing,
      sundryDebtorsPaise: null,
      cashInHandPaise: null,
      bankBalancesPaise: null,
      totalAssetsPaise: null,
      workingCapitalPaise: null,
      currentRatio: null,
      totalOutputTaxPaise: taxInvalid ? null : sum((r) => r.outputTax),
      totalInputTaxCreditPaise: null,
      netGstPayablePaise: null,
      b2bSalesPaise: null,
      b2cSalesPaise: null,
      digitalCollectionPaise: sum((r) => r.digitalCollections),
      cashCollectionPaise: sum((r) => r.cashCollections),
      creditCollectionDuePaise: null,
      gstRateBuckets: const [],
      hsnItems: const [],
      monthlyTrends: const [],
      stockAuditItems: const [],
      riskChecks: const [],
      debtorAgingList: const [],
      creditorAgingList: const [],
      expenseBreakdown: const {},
      reconciliation: review,
    );
  }
}

DateTime _indiaDay(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).subtract(const Duration(minutes: 330));
DateTime? _dateFields(Map<String, dynamic> d, List<String> fields) {
  for (final field in fields) {
    final v = d[field];
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      // Legacy date-only / timezone-free strings represent India local time.
      final dt = DateTime.tryParse(v);
      if (dt != null) {
        return RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(v)
            ? dt.toUtc()
            : DateTime.utc(
                dt.year,
                dt.month,
                dt.day,
                dt.hour,
                dt.minute,
                dt.second,
                dt.millisecond,
                dt.microsecond,
              ).subtract(const Duration(minutes: 330));
      }
    }
  }
  return null;
}

int? _integer(Map d, List<String> fields) {
  for (final field in fields) {
    final v = d[field];
    if (v is num && v.isFinite && v == v.roundToDouble()) return v.toInt();
  }
  return null;
}

List<Map<String, dynamic>> _decoded(ReportReadSnapshot s, String key) => [
  for (final d in s.documents[key] ?? <Map<String, dynamic>>[])
    {
      ...FirestoreRestService.decodeFields(d['fields']),
      '_id': '${d['name'] ?? ''}'.split('/').last,
      '_sync': d['localSyncStatus'],
    },
];
bool _active(Map<String, dynamic> d) =>
    ![
      'VOID',
      'CANCELLED',
      'DRAFT',
      'DELETED',
      'INACTIVE',
    ].contains('${d['status']}'.toUpperCase()) &&
    d['isDeleted'] != true;
bool _postedInvoice(Map<String, dynamic> d) =>
    _active(d) &&
    [
      'PAID',
      'PENDING',
      'POSTED',
      'APPROVED',
      'PARTIALLY_PAID',
    ].contains('${d['status']}'.toUpperCase());
bool _internal(Map<String, dynamic> d) =>
    d['isInternalTransfer'] == true ||
    ['TRANSFER', 'TRANSFER_IN', 'TRANSFER_OUT', 'INTERNAL_TRANSFER'].contains(
      '${d['transactionType'] ?? d['referenceType'] ?? d['documentType']}'
          .toUpperCase(),
    );
Set<String> _invoiceAliases(Map<String, dynamic> d) => {
  '${d['_id']}',
  if (d['invoiceId'] != null) '${d['invoiceId']}',
  if (d['requestId'] != null) ...['${d['requestId']}', 'REQ_${d['requestId']}'],
};

class _OutletReview {
  _OutletReview(this.businessId, this.outletId, this.name);
  final String businessId, outletId, name;
  int sales = 0,
      salesReturns = 0,
      internalTaxable = 0,
      gross = 0,
      discounts = 0,
      purchases = 0,
      purchaseReturns = 0,
      direct = 0,
      operating = 0,
      nonOperating = 0,
      salary = 0,
      outputTax = 0,
      inputTax = 0,
      debtors = 0,
      creditors = 0,
      cashMovement = 0,
      cashCollections = 0,
      digitalCollections = 0,
      advances = 0;
  int? opening, closing, costOfSales;
  bool salesValid = true, purchasesValid = true;
}

class _TaxReview {
  _TaxReview(this.business, this.classification, this.rate, this.hsn, this.uqc);
  final String business, classification, hsn, uqc;
  final int? rate;
  int value = 0, cess = 0;
  int? cgst = 0, sgst = 0, igst = 0;
  double quantity = 0;
  bool valueValid = true, quantityValid = true;
  final Set<String> invoices = {};
  void add(int v, int? c, int? s, int? i, int ce, double q, String id) {
    value += v;
    cgst = cgst == null || c == null ? null : cgst! + c;
    sgst = sgst == null || s == null ? null : sgst! + s;
    igst = igst == null || i == null ? null : igst! + i;
    cess += ce;
    quantity += q;
    invoices.add(id);
  }

  List<String> row({bool hsn = false}) => [
    '$business / $classification',
    hsn
        ? '${this.hsn} / $uqc / ${quantityValid ? quantity : 'UNKNOWN'}'
        : rate == null
        ? 'UNKNOWN'
        : '${rate! / 100}%',
    FinancialReconciliation.money(valueValid ? value : null),
    FinancialReconciliation.money(cgst),
    FinancialReconciliation.money(sgst),
    FinancialReconciliation.money(igst),
    FinancialReconciliation.money(cess),
  ];
}

class _InventoryReview {
  int? opening = 0, closing = 0, cogs = 0;
  bool valid = true;
  final rows = <List<String>>[],
      transfers = <List<String>>[],
      evidence = <List<String>>[];
}

_InventoryReview _inventoryReview(
  List<Map<String, dynamic>> batches,
  List<Map<String, dynamic>> movements,
  List<Map<String, dynamic>> stocks,
  List<Map<String, dynamic>> legacyMovements,
  List<Map<String, dynamic>> bills,
  List<Map<String, dynamic>> corrections,
  DateTime start,
  DateTime end,
  String scope,
  void Function(String, String, String) issue,
) {
  final result = _InventoryReview();
  void invalid(String code, String detail) {
    result.valid = false;
    issue(scope, code, detail);
  }

  final seen = <String>{};
  for (final m in movements) {
    if (!_active(m)) continue;
    if (!seen.add('${m['movementId'] ?? m['_id']}')) {
      invalid('DUPLICATE_MOVEMENT', 'Duplicate movement ${m['_id']}');
    }
    if (!batches.any((b) => (b['batchId'] ?? b['_id']) == m['batchId'])) {
      invalid('ORPHAN_BATCH', 'Movement ${m['_id']} has no batch');
    }
  }
  for (final b in batches.where(_active)) {
    final id = b['batchId'] ?? b['_id'];
    final moves = movements
        .where(
          (m) => m['batchId'] == id && m['status'] == 'POSTED' && _active(m),
        )
        .toList();
    final bill = bills
        .where(
          (p) =>
              (p['purchaseBillId'] ?? p['_id']) == b['purchaseId'] &&
              p['status'] == 'APPROVED',
        )
        .firstOrNull;
    final items = (bill?['items'] as List?)?.whereType<Map>() ?? <Map>[];
    final item = items
        .where(
          (i) =>
              i['goodsReceiptItemId'] == b['purchaseItemId'] ||
              (i['variantId'] == b['variantId'] &&
                  items.where((v) => v['variantId'] == b['variantId']).length ==
                      1),
        )
        .firstOrNull;
    final quantity = item == null
        ? null
        : _integer(item, ['baseQuantity']) ??
              (_integer(item, ['quantity']) != null &&
                      _integer(item, ['conversionFactor']) != null
                  ? ((_integer(item, ['quantity'])! *
                                _integer(item, ['conversionFactor'])! +
                            500) ~/
                        1000)
                  : null);
    final taxable = item == null ? null : _integer(item, ['taxableAmount']);
    final billTaxable = bill == null ? null : _integer(bill, ['taxableAmount']);
    final charges = bill == null ? null : _integer(bill, ['chargesAmount']);
    final totalCost =
        taxable == null ||
            charges == null ||
            billTaxable == null ||
            (charges != 0 && billTaxable == 0)
        ? null
        : taxable +
              (charges == 0
                  ? 0
                  : _roundedPaise(charges * taxable, billTaxable));
    var openingQty = 0,
        closingQty = 0,
        inward = 0,
        outward = 0,
        sold = 0,
        allQty = 0;
    var itemValid = quantity != null && quantity > 0 && totalCost != null;
    moves.sort(
      (a, b) => (_dateFields(a, ['occurredAt']) ?? DateTime(0)).compareTo(
        _dateFields(b, ['occurredAt']) ?? DateTime(0),
      ),
    );
    for (final m in moves) {
      final dt = _dateFields(m, ['occurredAt']);
      final qty = _integer(m, ['quantity']);
      final direction = m['direction'];
      if ('${m['referenceId'] ?? ''}'.isEmpty ||
          '${m['referenceType'] ?? ''}'.isEmpty) {
        itemValid = false;
        invalid(
          'ORPHAN_MOVEMENT_REFERENCE',
          'Movement ${m['_id']} lacks a persisted document reference.',
        );
      }
      if (dt == null ||
          qty == null ||
          qty <= 0 ||
          !['IN', 'OUT'].contains(direction)) {
        itemValid = false;
        continue;
      }
      final signed = direction == 'IN' ? qty : -qty;
      allQty += signed;
      if (allQty < 0) {
        itemValid = false;
        invalid(
          'NEGATIVE_STOCK_HISTORY',
          'Batch $id becomes negative at movement ${m['_id']}',
        );
      }
      if (dt.isBefore(start)) openingQty += signed;
      if (dt.isBefore(end)) closingQty += signed;
      if (!dt.isBefore(start) && dt.isBefore(end)) {
        if (signed > 0) {
          inward += qty;
        } else {
          outward += qty;
        }
        if (m['movementType'] == 'SALE') sold += qty;
        if (m['movementType'] == 'SALE_RETURN') sold -= qty;
        if ('${m['movementType']}'.startsWith('TRANSFER')) {
          result.transfers.add([
            scope,
            'inventory_batch_movements/${m['_id']}',
            'Internal quantity only, excluded revenue/purchases',
            '${m['movementType']} ${qty / 1000}; reference ${m['referenceId']}',
          ]);
          // Cross-batch transfer historical cost needs an explicit cost link.
          if (m['transferCostPaise'] == null) itemValid = false;
        }
      }
    }
    final received = _integer(b, ['receivedQty']);
    final receiptQuantity = moves
        .where((m) => m['movementType'] == 'PURCHASE_RECEIPT')
        .fold<int>(0, (sum, m) => sum + (_integer(m, ['quantity']) ?? 0));
    if (received != null && receiptQuantity != received) itemValid = false;
    if (moves.isEmpty ||
        allQty != _integer(b, ['availableQty']) ||
        openingQty < 0 ||
        closingQty < 0) {
      itemValid = false;
    }
    if (corrections.any((c) => c['purchaseBillId'] == b['purchaseId'])) {
      itemValid = false;
    }
    int? value(int q) =>
        itemValid ? _roundedPaise(totalCost! * q, quantity!) : null;
    final ov = value(openingQty), cv = value(closingQty), cost = value(sold);
    if (itemValid) {
      result.evidence.add([
        scope,
        'purchase_bills/${bill!['_id']} / inventory_batches/$id',
        'Batch receipt cost: taxable + allocated charges; base quantity ${quantity! / 1000}; sold net ${sold / 1000}',
        FinancialReconciliation.money(totalCost),
        '${_dateFields(bill, ['invoiceDate'])}',
        '${bill['_sync']}',
      ]);
    }
    if (!itemValid) {
      invalid(
        'INVENTORY_HISTORY_UNSUPPORTED',
        'Batch $id lacks consistent posted history, unit conversion, original cost, transfer-cost link, or has corrections requiring historical valuation.',
      );
    }
    result.opening = result.opening == null || ov == null
        ? null
        : result.opening! + ov;
    result.closing = result.closing == null || cv == null
        ? null
        : result.closing! + cv;
    result.cogs = result.cogs == null || cost == null
        ? null
        : result.cogs! + cost;
    result.rows.add([
      '$scope\n$id\n${b['variantId']}\n${item?['productName'] ?? 'Name not saved'}',
      '${openingQty / 1000}',
      '${inward / 1000}',
      '${outward / 1000}',
      '${closingQty / 1000}',
      '${FinancialReconciliation.money(ov)} / ${FinancialReconciliation.money(cv)}',
      itemValid ? 'Batch receipt cost; qty in base units' : 'INSUFFICIENT DATA',
    ]);
  }
  final batchVariantQty = <String, int>{};
  for (final b in batches.where(_active)) {
    final vid = '${b['variantId']}';
    batchVariantQty[vid] =
        (batchVariantQty[vid] ?? 0) + (_integer(b, ['availableQty']) ?? 0);
  }
  final stockVariantQty = <String, int>{};
  for (final stock in stocks) {
    final vid = '${stock['variantId'] ?? stock['productId']}';
    final qty = _integer(stock, ['quantityOnHand']);
    if (qty == null || qty < 0) {
      invalid(
        'STOCK_BATCH_QUANTITY_MISMATCH',
        'Stock ${stock['_id']} has missing or negative quantity.',
      );
    }
    stockVariantQty[vid] = (stockVariantQty[vid] ?? 0) + (qty ?? 0);
  }
  for (final vid in {...stockVariantQty.keys, ...batchVariantQty.keys}) {
    final qty = stockVariantQty[vid] ?? 0;
    if (qty != (batchVariantQty[vid] ?? 0)) {
      invalid(
        'STOCK_BATCH_QUANTITY_MISMATCH',
        'Variant $vid: current stock raw qty $qty differs from batch quantity ${batchVariantQty[vid] ?? 0}; no heuristic scale conversion applied.',
      );
      result.rows.add([
        '$scope\nvariant/$vid',
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN',
        '$qty raw',
        'INSUFFICIENT DATA',
        'Legacy/mixed unit history',
      ]);
    }
  }
  if (batches.isEmpty && (stocks.isNotEmpty || legacyMovements.isNotEmpty)) {
    invalid(
      'OPENING_STOCK_UNAVAILABLE',
      'No complete historical batch valuation; current stock is not period opening/closing stock.',
    );
  }
  if (!result.valid) {
    result.opening = null;
    result.closing = null;
    result.cogs = null;
  }
  return result;
}

String _expenseClass(Map<String, dynamic> expense) {
  final explicit = '${expense['accountingClass'] ?? ''}'.toUpperCase();
  if (explicit.isNotEmpty) return explicit;
  if (expense['salaryPeriodId'] != null ||
      expense['category'] == 'Salaries & Wages') {
    return 'PAYROLL';
  }
  if (const [
    'Rent & Lease',
    'Electricity & Utilities',
    'Freight & Delivery',
    'Repairs & Maintenance',
    'Tea & Refreshments',
    'Packaging & Materials',
    'Office & Stationery',
    'Marketing & Ads',
  ].contains(expense['category'])) {
    return 'OPERATING';
  }
  return 'UNCLASSIFIED';
}

bool _cashMode(String mode) => const [
  'CASH',
  'UPI',
  'BANK',
  'BANK_TRANSFER',
  'NEFT',
  'RTGS',
  'CARD',
  'CHEQUE',
].contains(mode.toUpperCase());

int _roundedPaise(int numerator, int denominator) {
  if (denominator <= 0) {
    throw ArgumentError('A positive source quantity is required.');
  }
  final magnitude = (numerator.abs() + denominator ~/ 2) ~/ denominator;
  return numerator < 0 ? -magnitude : magnitude;
}

List<List<String>> _taxScheduleRows(
  Iterable<_TaxReview> values, {
  bool hsn = false,
}) {
  final buckets = values.toList();
  final rows = buckets.map((b) => b.row(hsn: hsn)).toList();
  if (buckets.isEmpty) return rows;
  int? total(int? Function(_TaxReview) field) =>
      buckets.any((b) => field(b) == null)
      ? null
      : buckets.fold<int>(0, (sum, b) => sum + field(b)!);
  rows.add([
    'OBSERVED LINE TOTAL',
    hsn ? 'Separate UQC quantities above' : 'All displayed classifications',
    FinancialReconciliation.money(total((b) => b.valueValid ? b.value : null)),
    FinancialReconciliation.money(total((b) => b.cgst)),
    FinancialReconciliation.money(total((b) => b.sgst)),
    FinancialReconciliation.money(total((b) => b.igst)),
    FinancialReconciliation.money(total((b) => b.cess)),
  ]);
  return rows;
}
