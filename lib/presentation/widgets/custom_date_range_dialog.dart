import 'package:flutter/material.dart';

Future<DateTimeRange?> showCustomDateRangePicker({
  required BuildContext context,
  DateTime? initialStart,
  DateTime? initialEnd,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Custom Date Range',
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (ctx) => CustomDateRangeDialog(
      initialStart: initialStart,
      initialEnd: initialEnd,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class CustomDateRangeDialog extends StatefulWidget {
  const CustomDateRangeDialog({
    super.key,
    this.initialStart,
    this.initialEnd,
    this.firstDate,
    this.lastDate,
    this.title = 'Custom Date Range',
  });

  final DateTime? initialStart;
  final DateTime? initialEnd;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String title;

  @override
  State<CustomDateRangeDialog> createState() => _CustomDateRangeDialogState();
}

class _CustomDateRangeDialogState extends State<CustomDateRangeDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  int _activeStep = 1; // 1 = selecting From Date, 2 = selecting To Date

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final defaultLast = widget.lastDate ?? now;
    final defaultFirst = widget.firstDate ?? DateTime(2020);

    final start = widget.initialStart ?? now;
    final end = widget.initialEnd ?? now;

    _startDate = start.isAfter(defaultLast) ? defaultLast : (start.isBefore(defaultFirst) ? defaultFirst : start);
    _endDate = end.isAfter(defaultLast) ? defaultLast : (end.isBefore(_startDate) ? _startDate : end);
  }

  String _formatDateDisplay(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatShort(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final maxAllowedDate = widget.lastDate ?? DateTime.now();
    final minAllowedDate = widget.firstDate ?? DateTime(2020);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.white,
      elevation: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F7F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.date_range_rounded, size: 20, color: Color(0xFF0D9488)),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const Text(
                            'Step-by-step date selection',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Two step selection cards (From Date & To Date)
              Row(
                children: [
                  // From Date Card
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _activeStep = 1),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _activeStep == 1 ? const Color(0xFFE6F7F5) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _activeStep == 1 ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0),
                            width: _activeStep == 1 ? 2.0 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _activeStep == 1 ? const Color(0xFF0D9488) : const Color(0xFF94A3B8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '1. From Date',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatDateDisplay(_startDate),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _activeStep == 1 ? const Color(0xFF0F766E) : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF94A3B8)),
                  ),
                  // To Date Card
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _activeStep = 2),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _activeStep == 2 ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _activeStep == 2 ? const Color(0xFF4E45D5) : const Color(0xFFE2E8F0),
                            width: _activeStep == 2 ? 2.0 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _activeStep == 2 ? const Color(0xFF4E45D5) : const Color(0xFF94A3B8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '2. To Date',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatDateDisplay(_endDate),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _activeStep == 2 ? const Color(0xFF372ABF) : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Guided Step Prompt Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: _activeStep == 1 ? const Color(0xFFF0FDF4) : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _activeStep == 1 ? const Color(0xFFBBF7D0) : const Color(0xFFC7D2FE),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _activeStep == 1 ? Icons.touch_app_rounded : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: _activeStep == 1 ? const Color(0xFF16A34A) : const Color(0xFF4E45D5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _activeStep == 1
                            ? 'Step 1: Click calendar for START date (From)'
                            : 'Step 2: Click calendar for END date (To)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _activeStep == 1 ? const Color(0xFF15803D) : const Color(0xFF372ABF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Compact Calendar Picker
              Container(
                height: 310,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: CalendarDatePicker(
                  key: ValueKey(_activeStep),
                  initialDate: _activeStep == 1
                      ? (_startDate.isAfter(maxAllowedDate) ? maxAllowedDate : _startDate)
                      : (_endDate.isAfter(maxAllowedDate) ? maxAllowedDate : _endDate),
                  firstDate: _activeStep == 1 ? minAllowedDate : _startDate,
                  lastDate: maxAllowedDate,
                  onDateChanged: (picked) {
                    if (_activeStep == 1) {
                      setState(() {
                        _startDate = picked;
                        if (_endDate.isBefore(_startDate)) {
                          _endDate = _startDate;
                        }
                        // Guided auto-advance to step 2!
                        _activeStep = 2;
                      });
                    } else {
                      setState(() {
                        if (picked.isBefore(_startDate)) {
                          _startDate = picked;
                          _endDate = picked;
                        } else {
                          _endDate = picked;
                        }
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 18),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected: ${_formatShort(_startDate)} – ${_formatShort(_endDate)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(DateTimeRange(start: _startDate, end: _endDate));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Apply Range',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
