import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../painters/shapes/hardware_thumb_shape.dart';
import '../painters/shapes/hardware_tick_mark_shape.dart';
import '../painters/shapes/hardware_track_shape.dart';

class ClockModule extends StatelessWidget {
  /// Selectable clock speeds in Hz, on a 1-2-5 log scale.
  static const List<double> speeds = [
    0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000];

  /// Index into [speeds] closest to [hz], measured on a log scale.
  static int _speedIndex(double hz) {
    int best = 0;
    for (int i = 1; i < speeds.length; i++) {
      if ((math.log(speeds[i]) - math.log(hz)).abs() <
          (math.log(speeds[best]) - math.log(hz)).abs()) {
        best = i;
      }
    }
    return best;
  }

  static String _formatSpeed(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(0)} kHz';
    if (hz < 1) return '$hz Hz';
    return '${hz.toStringAsFixed(0)} Hz';
  }

  final bool clockHigh;
  final bool isRunning;
  final double speed;
  final bool manualMode;
  final VoidCallback onToggle;
  final VoidCallback onStep;
  final VoidCallback onReset;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<bool> onModeChanged;

  const ClockModule({
    super.key,
    required this.clockHigh,
    required this.isRunning,
    required this.speed,
    required this.manualMode,
    required this.onToggle,
    required this.onStep,
    required this.onReset,
    required this.onSpeedChanged,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.5),
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'CLOCK',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: clockHigh ? Colors.red : Colors.grey[800],
                  boxShadow: clockHigh
                      ? [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.6),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : null,
                ),
              ),
              if (!manualMode)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '(${_formatSpeed(speed)})',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
          IgnorePointer(
            ignoring: manualMode,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                thumbShape: const HardwareThumbShape(
                  enabledThumbRadius: 12,
                  disabledThumbRadius: 12,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                activeTrackColor: manualMode
                    ? Colors.grey[700]
                    : Colors.red.withValues(alpha: 0.8),
                inactiveTrackColor: Colors.grey[800],
                thumbColor: manualMode ? Colors.grey[600] : Colors.red,
                overlayColor: manualMode
                    ? Colors.grey.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.2),
                trackShape: const HardwareTrackShape(),
                tickMarkShape: const HardwareTickMarkShape(),
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: manualMode
                    ? Colors.grey[700]
                    : Colors.red.withValues(alpha: 0.3),
              ),
              child: Slider(
                value: _speedIndex(speed).toDouble(),
                min: 0,
                max: (speeds.length - 1).toDouble(),
                divisions: speeds.length - 1,
                onChanged: (position) =>
                    onSpeedChanged(speeds[position.round()]),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (!manualMode)
                Column(
                  children: [
                    _HardwareButton(
                      icon: isRunning
                          ? FluentIcons.pause_24_regular
                          : FluentIcons.play_24_regular,
                      onPressed: onToggle,
                    ),
                    const SizedBox(height: 8),
                    if (isRunning)
                      const Text('Pause', style: TextStyle(fontSize: 12))
                    else
                      const Text('Run', style: TextStyle(fontSize: 12)),
                  ],
                ),
              if (manualMode)
                Column(
                  children: [
                    _HardwareButton(
                      icon: FluentIcons.arrow_step_in_right_24_regular,
                      onPressed: onStep,
                    ),
                    const SizedBox(height: 8),
                    const Text('Step', style: TextStyle(fontSize: 12)),
                  ],
                ),
              Column(
                children: [
                  _HardwareButton(
                    icon: FluentIcons.arrow_clockwise_24_regular,
                    onPressed: onReset,
                  ),
                  const SizedBox(height: 8),
                  const Text('Reset', style: TextStyle(fontSize: 12)),
                ],
              ),
              Column(
                children: [
                  _HardwareToggleSwitch(
                    value: manualMode,
                    onChanged: onModeChanged,
                  ),
                  const SizedBox(height: 10),
                  const Text('Manual', style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HardwareButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _HardwareButton({required this.icon, required this.onPressed});

  @override
  State<_HardwareButton> createState() => _HardwareButtonState();
}

class _HardwareButtonState extends State<_HardwareButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _isPressed ? Colors.grey[900] : Colors.grey[850],
          border: Border.all(
            color: _isPressed
                ? Colors.red.withValues(alpha: 0.8)
                : Colors.grey[700]!,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              offset: _isPressed ? const Offset(0, 1) : const Offset(0, 3),
              blurRadius: _isPressed ? 2 : 6,
            ),
            if (_isPressed)
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
          ],
        ),
        child: Icon(
          widget.icon,
          color: _isPressed ? Colors.red : Colors.red.withValues(alpha: 0.9),
          size: 24,
        ),
      ),
    );
  }
}

class _HardwareToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _HardwareToggleSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[850],
          border: Border.all(
            color: value
                ? Colors.red.withValues(alpha: 0.8)
                : Colors.grey[700]!,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              offset: const Offset(0, 3),
              blurRadius: 6,
            ),
            if (value)
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
          ],
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.red : Colors.grey[700],
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.8),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
