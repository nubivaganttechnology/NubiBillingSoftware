class PurchaseCorrectionModel {
  const PurchaseCorrectionModel({
    required this.correctionId,
    required this.purchaseId,
    required this.correctionNumber,
    required this.reason,
    required this.correctedByUid,
    required this.correctedAt,
    required this.changedFields,
    required this.beforeSnapshot,
    required this.afterSnapshot,
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String correctionId, purchaseId, reason, correctedByUid;
  final int correctionNumber;
  final DateTime correctedAt, createdAt, updatedAt;
  final List<String> changedFields;
  final Map<String, dynamic> beforeSnapshot, afterSnapshot;
  final String tenantId, businessId, outletId;

  factory PurchaseCorrectionModel.fromData(
    String id,
    Map<String, dynamic> data,
  ) {
    DateTime parse(dynamic value) => value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return PurchaseCorrectionModel(
      correctionId: data['correctionId'] as String? ?? id,
      purchaseId: data['purchaseId'] as String? ?? '',
      correctionNumber: (data['correctionNumber'] as num?)?.toInt() ?? 0,
      reason: data['reason'] as String? ?? '',
      correctedByUid: data['correctedByUid'] as String? ?? '',
      correctedAt: parse(data['correctedAt']),
      changedFields: (data['changedFields'] as List? ?? const [])
          .map((v) => v.toString())
          .toList(),
      beforeSnapshot: Map<String, dynamic>.from(
        data['beforeSnapshot'] as Map? ?? const {},
      ),
      afterSnapshot: Map<String, dynamic>.from(
        data['afterSnapshot'] as Map? ?? const {},
      ),
      tenantId: data['tenantId'] as String? ?? '',
      businessId: data['businessId'] as String? ?? '',
      outletId: data['outletId'] as String? ?? '',
      createdAt: parse(data['createdAt']),
      updatedAt: parse(data['updatedAt']),
    );
  }

  Map<String, dynamic> toData() => {
    'correctionId': correctionId,
    'purchaseId': purchaseId,
    'correctionNumber': correctionNumber,
    'reason': reason,
    'correctedByUid': correctedByUid,
    'correctedAt': correctedAt,
    'changedFields': changedFields,
    'beforeSnapshot': beforeSnapshot,
    'afterSnapshot': afterSnapshot,
    'tenantId': tenantId,
    'businessId': businessId,
    'outletId': outletId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
