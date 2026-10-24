import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/data/models/quantity_discount_slab.dart';
import 'package:testflutter/domain/billing/bill_calculator.dart';
import 'package:testflutter/domain/billing/billing_models.dart';

void main() {
  group('QuantityDiscountSlab Unit Tests', () {
    test('matches quantity within range', () {
      const slab = QuantityDiscountSlab(
        minQty: 50,
        maxQty: 100,
        discountType: 'PERCENTAGE',
        discountValue: 5.0,
      );

      expect(slab.matches(49), isFalse);
      expect(slab.matches(50), isTrue);
      expect(slab.matches(75), isTrue);
      expect(slab.matches(100), isTrue);
      expect(slab.matches(101), isFalse);
    });

    test('matches open-ended upper limit (maxQty == null)', () {
      const slab = QuantityDiscountSlab(
        minQty: 151,
        maxQty: null,
        discountType: 'PERCENTAGE',
        discountValue: 12.0,
      );

      expect(slab.matches(150), isFalse);
      expect(slab.matches(151), isTrue);
      expect(slab.matches(500), isTrue);
      expect(slab.matches(10000), isTrue);
    });

    test('calculates percentage discount accurately in paise', () {
      // 5% discount on 60 items @ ₹100.00 each (10,000 paise each)
      // Gross = 60 * 10,000 = 600,000 paise (₹6,000)
      // Discount = 5% of 600,000 = 30,000 paise (₹300.00)
      const slab = QuantityDiscountSlab(
        minQty: 50,
        maxQty: 100,
        discountType: 'PERCENTAGE',
        discountValue: 5.0,
      );

      final discountPaise = slab.calculateDiscountPaise(
        quantity: 60,
        unitPricePaise: 10000,
      );
      expect(discountPaise, 30000);
    });

    test('calculates flat discount per unit accurately in paise', () {
      // Flat ₹10 off per unit on 80 items
      // Discount = 80 * (₹10 * 100) = 80 * 1,000 paise = 80,000 paise (₹800.00)
      const slab = QuantityDiscountSlab(
        minQty: 50,
        maxQty: 100,
        discountType: 'FLAT_PER_UNIT',
        discountValue: 10.0,
      );

      final discountPaise = slab.calculateDiscountPaise(
        quantity: 80,
        unitPricePaise: 25000,
      );
      expect(discountPaise, 80000);
    });

    test('serialization toMap and fromData round-trip preserves values', () {
      const original = QuantityDiscountSlab(
        minQty: 101,
        maxQty: 150,
        discountType: 'PERCENTAGE',
        discountValue: 8.5,
      );

      final map = original.toMap();
      expect(map['minQty'], 101);
      expect(map['maxQty'], 150);
      expect(map['discountType'], 'PERCENTAGE');
      expect(map['discountValue'], 8.5);

      final restored = QuantityDiscountSlab.fromData(map);
      expect(restored, equals(original));
    });
  });

  group('ProductModel & ProductVariantModel Slab Integration Tests', () {
    test('ProductModel preserves quantitySlabs in toData and fromData', () {
      const slab1 = QuantityDiscountSlab(
        minQty: 50,
        maxQty: 100,
        discountValue: 5.0,
      );
      const slab2 = QuantityDiscountSlab(
        minQty: 101,
        discountValue: 10.0,
      );

      final product = ProductModel(
        productId: 'prod-1',
        tenantId: 'tenant-1',
        businessId: 'biz-1',
        name: 'Asian Paints Apex 20L',
        status: 'ACTIVE',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        quantitySlabs: const [slab1, slab2],
      );

      final data = product.toData();
      expect(data['quantitySlabs'], isNotNull);
      expect((data['quantitySlabs'] as List).length, 2);

      final loaded = ProductModel.fromData(data);
      expect(loaded.quantitySlabs.length, 2);
      expect(loaded.quantitySlabs[0].minQty, 50);
      expect(loaded.quantitySlabs[0].discountValue, 5.0);
      expect(loaded.quantitySlabs[1].minQty, 101);
      expect(loaded.quantitySlabs[1].maxQty, isNull);
    });

    test('ProductVariantModel preserves quantitySlabs in fromData and copyWith', () {
      const slab = QuantityDiscountSlab(
        minQty: 25,
        maxQty: 50,
        discountValue: 4.0,
      );

      final variant = ProductVariantModel.fromData('var-1', {
        'name': 'Brilliant White',
        'sellingPrice': 50000,
        'quantitySlabs': [slab.toMap()],
      });

      expect(variant.quantitySlabs.length, 1);
      expect(variant.quantitySlabs.first.minQty, 25);
      expect(variant.quantitySlabs.first.discountValue, 4.0);

      final updated = variant.copyWith(name: 'Super White');
      expect(updated.quantitySlabs.length, 1);
      expect(updated.name, 'Super White');
    });
  });

  group('Billing Tier Selection & Calculation Simulation Tests', () {
    final slabs = [
      const QuantityDiscountSlab(minQty: 50, maxQty: 100, discountValue: 5.0),
      const QuantityDiscountSlab(minQty: 101, maxQty: 150, discountValue: 8.0),
      const QuantityDiscountSlab(minQty: 151, discountValue: 12.0),
    ];

    int computeDiscount(int qty, int unitPrice) {
      for (final slab in slabs) {
        if (slab.matches(qty)) {
          return slab.calculateDiscountPaise(
            quantity: qty,
            unitPricePaise: unitPrice,
          );
        }
      }
      return 0;
    }

    test('Customer buys below minimum tier (20 units) -> ₹0 discount', () {
      final discount = computeDiscount(20, 10000); // 20 units @ ₹100
      expect(discount, 0);
    });

    test('Customer buys in Tier 1 (75 units) -> 5% discount automatically', () {
      // 75 units @ ₹100 = ₹7,500 (750,000 paise)
      // 5% discount = 37,500 paise (₹375.00)
      final discount = computeDiscount(75, 10000);
      expect(discount, 37500);
    });

    test('Customer buys in Tier 2 (120 units) -> 8% discount automatically', () {
      // 120 units @ ₹100 = ₹12,000 (1,200,000 paise)
      // 8% discount = 96,000 paise (₹960.00)
      final discount = computeDiscount(120, 10000);
      expect(discount, 96000);
    });

    test('Customer buys in Tier 3 (200 units) -> 12% discount automatically', () {
      // 200 units @ ₹100 = ₹20,000 (2,000,000 paise)
      // 12% discount = 240,000 paise (₹2,400.00)
      final discount = computeDiscount(200, 10000);
      expect(discount, 240000);
    });

    test('Quantity reduction from 80 to 20 clears discount to ₹0', () {
      var qty = 80;
      var discount = computeDiscount(qty, 10000);
      expect(discount, 40000); // 5% of 800,000 paise = 40,000 paise

      // Cashier reduces qty to 20
      qty = 20;
      discount = computeDiscount(qty, 10000);
      expect(discount, 0);
    });

    test('BillCalculator accurately computes GST over Net amount after Slab Discount', () {
      // 100 units @ ₹100 = ₹10,000 gross (1,000,000 paise)
      // 5% slab discount = 50,000 paise (₹500.00)
      // Net Taxable = ₹9,500 (950,000 paise)
      // 18% GST (1800 bps) = 18% of 950,000 = 171,000 paise (₹1,710.00)
      // Grand Total = 950,000 + 171,000 = 1,121,000 paise (₹11,210.00)
      const calculator = BillCalculator();
      final lineInput = BillLineInput(
        variantId: 'var-1',
        sku: 'SKU-001',
        name: 'Bulk Product Test',
        hsn: '3208',
        quantity: 100,
        unitPricePaise: 10000,
        gstRateBps: 1800,
        priceIncludesTax: false,
        discountPaise: 50000, // Applied 5% slab discount
      );

      final bill = calculator.calculate(
        lines: [lineInput],
        taxMode: BillingTaxMode.gst,
        taxStructure: TaxStructure.intraState,
      );

      expect(bill.subtotalPaise, 1000000); // Gross ₹10,000
      expect(bill.totalDiscountPaise, 50000); // Discount ₹500
      expect(bill.taxableTotalPaise, 950000); // Net Taxable ₹9,500
      expect(bill.taxTotalPaise, 171000); // 18% GST ₹1,710
      expect(bill.cgstPaise, 85500); // 9% CGST ₹855
      expect(bill.sgstPaise, 85500); // 9% SGST ₹855
      expect(bill.grandTotalPaise, 1121000); // ₹11,210
    });
  });
}
