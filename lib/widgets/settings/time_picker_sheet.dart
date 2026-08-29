import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';

import '../../theme/mode_theme.dart';

/// 日期/时间的五列纯数字滚轮：年 / 月 / 日 / 时 / 分，只显示数字、上下滑动
/// 直接选择。任一列变化都通过 [onChanged] 回调当前完成时间（自动回退到「此刻」，
/// 不能选未来）。不做标题、预览、取消/确定——「失去焦点即确定」由调用方实现。
class TimeMiniWheel extends StatefulWidget {
  const TimeMiniWheel({
    super.key,
    required this.mode,
    required this.initial,
    required this.onChanged,
  });

  final ModeTheme mode;
  final DateTime initial;
  final ValueChanged<DateTime> onChanged;

  @override
  State<TimeMiniWheel> createState() => _TimeMiniWheelState();
}

class _TimeMiniWheelState extends State<TimeMiniWheel> {
  late int _year = widget.initial.year;
  late int _month = widget.initial.month;
  late int _day = widget.initial.day;
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;

  late final FixedExtentScrollController _yearC =
      FixedExtentScrollController(initialItem: _year - 2000);
  late final FixedExtentScrollController _monthC =
      FixedExtentScrollController(initialItem: _month - 1);
  late final FixedExtentScrollController _dayC =
      FixedExtentScrollController(initialItem: _day - 1);
  late final FixedExtentScrollController _hourC =
      FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteC =
      FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _yearC.dispose();
    _monthC.dispose();
    _dayC.dispose();
    _hourC.dispose();
    _minuteC.dispose();
    super.dispose();
  }

  int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

  /// 当天数超出当月时收敛到月末（并同步滚轮位置）。
  int _clampDay() {
    final maxDay = _daysInMonth(_year, _month);
    if (_day <= maxDay) return _day;
    _day = maxDay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dayC.hasClients) _dayC.jumpToItem(maxDay - 1);
    });
    return _day;
  }

  void _emit() {
    var d = DateTime(_year, _month, _clampDay(), _hour, _minute);
    final now = DateTime.now();
    if (d.isAfter(now)) d = now;
    widget.onChanged(d);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  Widget _wheel({
    required int count,
    required String Function(int) label,
    required FixedExtentScrollController controller,
    required void Function(int index) onChanged,
  }) {
    final mode = widget.mode;
    return Expanded(
      // 列间留点水平空隙，数字不挤。
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: CupertinoPicker.builder(
          scrollController: controller,
          itemExtent: 38,
          diameterRatio: 1.9,
          squeeze: 1.12,
          backgroundColor: Colors.transparent,
          onSelectedItemChanged: onChanged,
          childCount: count,
          // 选中框：干净的圆角选中条（主题 chip 圆角 + 主色描边 + 主色淡填充）。
          // 不用 FoldShape 切角，避免折角的描边戳角在四角留下阴影/毛刺。
          selectionOverlay: Align(
            alignment: Alignment.center,
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: mode.primary.withValues(alpha: 0.10),
                borderRadius: mode.chipRadius,
                border: Border.all(
                  color: mode.primary.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            ),
          ),
          itemBuilder: (context, index) {
            final selected = index == controller.selectedItem;
            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label(index),
                  style: TextStyle(
                    fontFamily: mode.fontFamily,
                    fontFamilyFallback: mode.fontFamilyFallback,
                    fontSize: selected ? 14 : 12.5,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? mode.primary : mode.cardMuted,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowYear = DateTime.now().year;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _wheel(
          count: nowYear - 2000 + 1,
          controller: _yearC,
          label: (i) => '${2000 + i}',
          onChanged: (i) {
            setState(() => _year = 2000 + i);
            _emit();
          },
        ),
        _wheel(
          count: 12,
          controller: _monthC,
          label: (i) => _two(i + 1),
          onChanged: (i) {
            setState(() => _month = i + 1);
            _emit();
          },
        ),
        _wheel(
          count: _daysInMonth(_year, _month),
          controller: _dayC,
          label: (i) => _two(i + 1),
          onChanged: (i) {
            setState(() => _day = i + 1);
            _emit();
          },
        ),
        _wheel(
          count: 24,
          controller: _hourC,
          label: (i) => _two(i),
          onChanged: (i) {
            setState(() => _hour = i);
            _emit();
          },
        ),
        _wheel(
          count: 60,
          controller: _minuteC,
          label: (i) => _two(i),
          onChanged: (i) {
            setState(() => _minute = i);
            _emit();
          },
        ),
      ],
    );
  }
}