import 'package:flutter/material.dart';

/// Shows a blocking modal progress dialog with animated steps to inform the user
/// during save, upload to server, and offline sync operations.
Future<T?> showSyncTaskDialog<T>({
  required BuildContext context,
  required String title,
  required Future<T> Function(void Function(String message) updateStatus) task,
}) async {
  final statusNotifier = ValueNotifier<String>('Starting...');
  final isDoneNotifier = ValueNotifier<bool>(false);
  final isErrorNotifier = ValueNotifier<bool>(false);
  bool dialogPopped = false;

  void closeDialogSafe([T? result]) {
    if (!dialogPopped && context.mounted) {
      dialogPopped = true;
      Navigator.of(context, rootNavigator: true).pop(result);
    }
  }

  showDialog<T>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: Dialog(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ValueListenableBuilder<bool>(
              valueListenable: isDoneNotifier,
              builder: (ctx, isDone, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: isErrorNotifier,
                  builder: (ctx, isError, _) {
                    return ValueListenableBuilder<String>(
                      valueListenable: statusNotifier,
                      builder: (ctx, statusText, _) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: isError
                                    ? Colors.red.shade50
                                    : isDone
                                        ? Colors.green.shade50
                                        : const Color(0xFF10263D)
                                            .withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: isError
                                  ? Icon(
                                      Icons.error_outline_rounded,
                                      color: Colors.red.shade600,
                                      size: 32,
                                    )
                                  : isDone
                                      ? Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.green.shade600,
                                          size: 32,
                                        )
                                      : const Center(
                                          child: SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                Color(0xFF10263D),
                                              ),
                                            ),
                                          ),
                                        ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: isError
                                    ? Colors.red.shade700
                                    : isDone
                                        ? Colors.green.shade700
                                        : const Color(0xFF64748B),
                                fontWeight: (isDone || isError)
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (!isDone && !isError) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: const SizedBox(
                                  width: 140,
                                  height: 3,
                                  child: LinearProgressIndicator(
                                    backgroundColor: Color(0xFFE2E8F0),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF10263D),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
    },
  );

  try {
    final result = await task((msg) {
      statusNotifier.value = msg;
    });
    isDoneNotifier.value = true;
    await Future.delayed(const Duration(milliseconds: 700));
    closeDialogSafe(result);
    return result;
  } catch (e) {
    isErrorNotifier.value = true;
    statusNotifier.value = 'Error: $e';
    await Future.delayed(const Duration(milliseconds: 900));
    closeDialogSafe(null);
    rethrow;
  }
}
