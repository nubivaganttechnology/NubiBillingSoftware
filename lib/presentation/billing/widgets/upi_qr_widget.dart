import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Helper and widgets for dynamic UPI QR code generation and payments.
class UpiQrWidget extends StatelessWidget {
  const UpiQrWidget({
    super.key,
    required this.amount,
    this.upiId = defaultUpiId,
    this.merchantName = defaultMerchantName,
    this.billNumber,
    this.customerName,
    this.note,
    this.size = 230,
  })  : data = '',
        amountPaise = null;

  /// Backwards-compatible constructor for existing callers
  const UpiQrWidget.legacy({
    super.key,
    required this.data,
    required this.amountPaise,
    this.size = 220,
  })  : amount = 0,
        upiId = defaultUpiId,
        merchantName = defaultMerchantName,
        billNumber = null,
        customerName = null,
        note = null;

  static const String defaultUpiId = '9035714708@upi';
  static const String defaultMerchantName = 'Nubivagant';

  final double amount;
  final String upiId;
  final String merchantName;
  final String? billNumber;
  final String? customerName;
  final String? note;
  final double size;

  // Legacy fields
  final String data;
  final int? amountPaise;

  /// Generates the standard UPI payment URI for any amount:
  /// upi://pay?pa=9035714708@upi&pn=Nubivagant&am=1250.00&cu=INR
  static String generateUpiUri({
    required double amount,
    String upiId = defaultUpiId,
    String merchantName = defaultMerchantName,
    String? transactionNote,
  }) {
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upiId,
        'pn': merchantName,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        if (transactionNote != null && transactionNote.trim().isNotEmpty)
          'tn': transactionNote.trim(),
      },
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    // If legacy constructor was used with raw data
    if (data.isNotEmpty) {
      final amt = amountPaise != null
          ? '₹${amountPaise! ~/ 100}.${(amountPaise! % 100).toString().padLeft(2, '0')}'
          : '';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: QrImageView(
              data: data,
              size: size,
              version: QrVersions.auto,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          if (amt.isNotEmpty)
            Text(
              amt,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          const SizedBox(height: 6),
          const Text(
            'Confirm UPI receipt manually before finalizing.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final computedUri = generateUpiUri(
      amount: amount,
      upiId: upiId,
      merchantName: merchantName,
      transactionNote: note ?? (billNumber != null ? 'Bill $billNumber' : null),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Scan to Pay',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (billNumber != null || customerName != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (billNumber != null) 'Bill: $billNumber',
              if (customerName != null) customerName,
            ].join(' • '),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: computedUri,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1B5E20), // Forest green
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Clipboard.setData(ClipboardData(text: upiId));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('UPI ID copied: $upiId'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'UPI ID: $upiId',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: const Text(
            'Pay using Google Pay, PhonePe, Paytm or BHIM',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            _appBadge('GPay', Colors.blue.shade700),
            _appBadge('PhonePe', const Color(0xFF5F259F)),
            _appBadge('Paytm', const Color(0xFF00B9F5)),
            _appBadge('BHIM', const Color(0xFF00796B)),
          ],
        ),
      ],
    );
  }

  Widget _appBadge(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// Helper function to show a standard UPI payment popup dialog.
/// Returns true if the user clicks "Payment Received / Done", false or null otherwise.
Future<bool?> showUpiPaymentDialog(
  BuildContext context, {
  required double amount,
  String? billNumber,
  String? customerName,
  String? note,
  String upiId = UpiQrWidget.defaultUpiId,
  String merchantName = UpiQrWidget.defaultMerchantName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_2, color: Colors.blue, size: 24),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'UPI Payment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: UpiQrWidget(
            amount: amount,
            upiId: upiId,
            merchantName: merchantName,
            billNumber: billNumber,
            customerName: customerName,
            note: note,
            size: 220,
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel / Close'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1B5E20),
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Payment Received'),
        ),
      ],
    ),
  );
}
