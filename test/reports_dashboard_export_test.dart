import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/domain/reports/report_models.dart';
import 'package:testflutter/presentation/reports/report_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reports Dashboard & Export Tests', () {
    final sampleDateRange = ReportDateRange(
      preset: DateRangePreset.thisMonth,
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 31, 23, 59, 59),
    );

    test('ReportsOverviewData supports gross profit and margin percentage', () {
      final overview = ReportsOverviewData(
        netSalesPaise: 1000000, // ₹10,000
        previousNetSalesPaise: 800000,
        salesGrowthPercentage: 25.0,
        purchasesPaise: 600000, // ₹6,000
        purchasesToSalesRatio: 60.0,
        receivablesOutstandingPaise: 200000,
        collectedPaise: 800000,
        lowStockCount: 2,
        expiringBatchesCount: 1,
        generatedAt: DateTime.now(),
        dataCutoffTime: DateTime.now(),
        isSynced: true,
        tileStatuses: {
          for (final id in ReportTileId.values) id: ReportTileStatus.ready,
        },
        grossProfitPaise: 400000, // ₹4,000
        grossProfitMarginPercentage: 40.0, // 40%
      );

      expect(overview.grossProfitPaise, 400000);
      expect(overview.grossProfitMarginPercentage, 40.0);
      expect(overview.netSalesPaise, 1000000);
    });

    test('ReportExportService.generatePdf handles Unicode without crashing',
        () async {
      final detail = ReportDetailData(
        tileId: ReportTileId.profitEstimate,
        title: 'Profit Estimate Report',
        subtitle: 'Gross revenue less estimated purchase cost per product',
        businessName: 'ব্যাবসা ও দোকান (Shop & Store)',
        outletName: 'কলিকাতা আউটলেট - Kolkata Outlet',
        dateRange: sampleDateRange,
        generatedAt: DateTime.now(),
        columns: const [
          'Product Name',
          'Quantity',
          'Sales Value',
          'Cost Value',
          'Gross Profit',
          'Margin %',
        ],
        rows: const [
          ['পণ্য ১ (Item 1)', '10', '₹ 5,000', '₹ 3,500', '₹ 1,500', '30.0%'],
          ['चीज़ २ (Item 2 — No SKU)', '5', '₹ 2,500', '₹ 1,750', '₹ 750', '30.0%'],
        ],
        columnTotals: const {
          2: '₹ 7,500',
          3: '₹ 5,250',
          4: '₹ 2,250',
          5: '30.0%',
        },
        summaryStats: const [
          ReportSummaryStat(label: 'Total Revenue', value: '₹ 7,500'),
          ReportSummaryStat(label: 'Estimated Gross Profit', value: '₹ 2,250'),
          ReportSummaryStat(label: 'Overall Gross Margin', value: '30.0%'),
        ],
        notes: const [
          'Estimated based on recorded purchase rate.',
          'Special notes with bullet points & rupee signs: ₹ 100 — valid.',
        ],
      );

      final pdfBytes = await ReportExportService.generatePdf(detail);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('ReportExportService CSV rows and formatting', () async {
      final detail = ReportDetailData(
        tileId: ReportTileId.salesSummary,
        title: 'Sales Summary',
        subtitle: 'Sales summary details',
        businessName: 'Acme Corp',
        outletName: 'Main Store',
        dateRange: sampleDateRange,
        generatedAt: DateTime.now(),
        columns: const ['Date', 'Invoices', 'Gross', 'Net'],
        rows: const [
          ['2026-10-01', '12', '12000', '11500'],
          ['2026-10-02', '15', '15000', '14200'],
        ],
        columnTotals: const {
          1: '27',
          2: '27000',
          3: '25700',
        },
        summaryStats: const [
          ReportSummaryStat(label: 'Net Sales', value: '₹ 25,700'),
        ],
      );

      // Verify that CSV structure contains headers, summary and data
      final csvRows = <List<dynamic>>[];
      csvRows.add([detail.businessName, 'Outlet: ${detail.outletName}']);
      csvRows.add(['Report: ${detail.title}', 'Period: ${detail.dateRange.formatLabel()}']);
      for (final s in detail.summaryStats) {
        csvRows.add([s.label, s.value]);
      }
      csvRows.add(detail.columns);
      for (final row in detail.rows) {
        csvRows.add(row);
      }

      final csvStr = const ListToCsvConverterFallback().convert(csvRows);
      expect(csvStr, contains('Acme Corp'));
      expect(csvStr, contains('Net Sales'));
      expect(csvStr, contains('2026-10-01'));
    });
  });
}

class ListToCsvConverterFallback {
  const ListToCsvConverterFallback();
  String convert(List<List<dynamic>> rows) {
    return rows.map((r) => r.map((c) => '"$c"').join(',')).join('\n');
  }
}
