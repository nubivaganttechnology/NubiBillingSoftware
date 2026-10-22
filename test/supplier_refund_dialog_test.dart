import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/presentation/procurement/supplier_pages.dart';

void main() {
  testWidgets('refund form validates amount and required reason', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<dynamic>(
                context: context,
                builder: (_) =>
                    const SupplierRefundDialog(availableAdvance: 48160),
              ),
              child: const Text('Open refund'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open refund'));
    await tester.pumpAndSettle();

    final amountField = find.widgetWithText(TextField, 'Refund Amount (₹)');
    await tester.enterText(amountField, '500.00');
    await tester.tap(find.text('Record Refund'));
    await tester.pumpAndSettle();
    expect(
      find.text('Refund cannot exceed available advance.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(amountField, '481.60');
    await tester.tap(find.text('Record Refund'));
    await tester.pumpAndSettle();
    expect(find.text('Reason is required.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Reason *'),
      'Cash returned',
    );
    await tester.tap(find.text('Record Refund'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
