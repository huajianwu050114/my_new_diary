// file: libs/check_in_dialog.dart
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';

class CheckInDialog extends StatefulWidget {
  const CheckInDialog({super.key});

  @override
  State<CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<CheckInDialog> {
  int _consecutiveDays = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchConsecutiveDays();
  }

  Future<void> _fetchConsecutiveDays() async {
    final days = await context.read<DiaryService>().getConsecutiveCheckInDays();
    if (mounted) {
      setState(() {
        _consecutiveDays = days;
        _isLoading = false;
      });
    }
  }

  void _performCheckIn() {
    context.read<DiaryService>().addCheckIn(DateTime.now());
    Navigator.of(context).pop(true); // 返回 true 表示签到成功
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: FadeInUp(
        duration: const Duration(milliseconds: 500),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF201E2E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/icons/diary_sprite.svg', // 替换成您的小精灵SVG
                height: 80,
              ),
              const SizedBox(height: 16),
              const Text(
                "今日份的约定，你好呀！",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontSize: 16, color: theme.textTheme.bodyMedium?.color, height: 1.5),
                  children: [
                    const TextSpan(text: "你已经连续记录了 "),
                    TextSpan(
                      text: '$_consecutiveDays',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const TextSpan(text: " 天\n继续加油，让每一天都闪闪发光！✨"),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _performCheckIn,
                child: const Text("立即签到", style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}