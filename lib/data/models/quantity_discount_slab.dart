class QuantityDiscountSlab {
  final int minQty;
  final int? maxQty; // null represents open-ended range (e.g. 150+)
  final String discountType; // 'PERCENTAGE' or 'FLAT_PER_UNIT'
  final double discountValue; // percentage (e.g. 5 for 5%) or rupees per unit (e.g. 10 for ₹10)

  const QuantityDiscountSlab({
    required this.minQty,
    this.maxQty,
    this.discountType = 'PERCENTAGE',
    required this.discountValue,
  });

  bool matches(int quantity) {
    if (quantity < minQty) return false;
    if (maxQty != null && quantity > maxQty!) return false;
    return true;
  }

  int calculateDiscountPaise({
    required int quantity,
    required int unitPricePaise,
  }) {
    if (!matches(quantity)) return 0;
    if (discountType == 'FLAT_PER_UNIT') {
      final perUnitPaise = (discountValue * 100).round();
      return perUnitPaise * quantity;
    } else {
      // PERCENTAGE
      final grossPaise = quantity * unitPricePaise;
      return ((grossPaise * discountValue) / 100).round();
    }
  }

  Map<String, dynamic> toMap() => {
    'minQty': minQty,
    if (maxQty != null) 'maxQty': maxQty,
    'discountType': discountType,
    'discountValue': discountValue,
  };

  factory QuantityDiscountSlab.fromData(Map<String, dynamic> data) {
    return QuantityDiscountSlab(
      minQty: (data['minQty'] as num?)?.toInt() ?? 1,
      maxQty: (data['maxQty'] as num?)?.toInt(),
      discountType: data['discountType'] as String? ?? 'PERCENTAGE',
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0.0,
    );
  }

  QuantityDiscountSlab copyWith({
    int? minQty,
    int? maxQty,
    String? discountType,
    double? discountValue,
  }) {
    return QuantityDiscountSlab(
      minQty: minQty ?? this.minQty,
      maxQty: maxQty ?? this.maxQty,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuantityDiscountSlab &&
          runtimeType == other.runtimeType &&
          minQty == other.minQty &&
          maxQty == other.maxQty &&
          discountType == other.discountType &&
          discountValue == other.discountValue;

  @override
  int get hashCode =>
      minQty.hashCode ^
      maxQty.hashCode ^
      discountType.hashCode ^
      discountValue.hashCode;

  @override
  String toString() =>
      'QuantityDiscountSlab(min: $minQty, max: $maxQty, type: $discountType, val: $discountValue)';
}
