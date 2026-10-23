import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/salary_document_service.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/staff_salary/staff_salary_page.dart';

void main() {
  Widget buildTestWidget({
    required Widget child,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await showDialog<SalaryExportRequest>(
                  context: context,
                  builder: (context) => child,
                );
                // Store result in test key for inspection if needed
                (context as Element).markNeedsBuild();
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('SalaryDocumentExportDialog renders options and triggers Download in Bengali',
      (tester) async {
    SalaryExportRequest? capturedResult;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  capturedResult = await showDialog<SalaryExportRequest>(
                    context: context,
                    builder: (context) => const SalaryDocumentExportDialog(
                      title: 'Salary Slip (PDF)',
                      employeeName: 'Arun Kumar',
                      periodLabel: '01 Oct 2026 – 31 Oct 2026',
                      isSlip: true,
                      initialLanguage: SalaryDocumentLanguage.english,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open the export dialog
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify dialog content
    expect(find.text('Salary Slip (PDF)'), findsOneWidget);
    expect(find.text('Arun Kumar • 01 Oct 2026 – 31 Oct 2026'), findsOneWidget);
    expect(find.text('English (Default)'), findsOneWidget);
    expect(find.text('বাংলা (Bengali)'), findsOneWidget);
    expect(find.text('हिन्दी (Hindi)'), findsOneWidget);

    // Verify action buttons
    expect(find.text('Download PDF'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    expect(find.text('Share PDF'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Select Bengali language
    await tester.tap(find.text('বাংলা (Bengali)'));
    await tester.pumpAndSettle();

    // Tap Download PDF
    await tester.tap(find.text('Download PDF'));
    await tester.pumpAndSettle();

    // Verify dialog closed and returned download action with Bengali
    expect(capturedResult, isNotNull);
    expect(capturedResult!.action, SalaryExportAction.download);
    expect(capturedResult!.language, SalaryDocumentLanguage.bengali);
  });

  testWidgets('SalaryDocumentExportDialog triggers Print action', (tester) async {
    SalaryExportRequest? capturedResult;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  capturedResult = await showDialog<SalaryExportRequest>(
                    context: context,
                    builder: (context) => const SalaryDocumentExportDialog(
                      title: 'Salary Statement (PDF)',
                      employeeName: 'Priya Sharma',
                      periodLabel: '01 Sep 2026 – 30 Sep 2026',
                      isSlip: false,
                      initialLanguage: SalaryDocumentLanguage.hindi,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap Print
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(capturedResult, isNotNull);
    expect(capturedResult!.action, SalaryExportAction.print);
    expect(capturedResult!.language, SalaryDocumentLanguage.hindi);
  });

  testWidgets('SalaryDocumentExportDialog triggers Share action', (tester) async {
    SalaryExportRequest? capturedResult;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  capturedResult = await showDialog<SalaryExportRequest>(
                    context: context,
                    builder: (context) => const SalaryDocumentExportDialog(
                      title: 'Salary Slip (PDF)',
                      employeeName: 'Rahul Sen',
                      periodLabel: '01 Oct 2026 – 31 Oct 2026',
                      isSlip: true,
                      initialLanguage: SalaryDocumentLanguage.english,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap Share
    await tester.tap(find.text('Share PDF'));
    await tester.pumpAndSettle();

    expect(capturedResult, isNotNull);
    expect(capturedResult!.action, SalaryExportAction.share);
    expect(capturedResult!.language, SalaryDocumentLanguage.english);
  });
}
