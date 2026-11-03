import 'package:flutter/material.dart';

/// Shared presentation of TTS speed, volume and pitch adjustment.
class AudioAdjustmentSlider extends StatelessWidget {
  const AudioAdjustmentSlider({
    required this.label,
    required this.value,
    required this.suffix,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final String suffix;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 64, child: Text(label)),
      Expanded(
        child: Slider(
          value: value,
          min: -50,
          max: 50,
          divisions: 100,
          onChanged: enabled ? onChanged : null,
        ),
      ),
      SizedBox(
        width: 58,
        child: Text(
          '${value >= 0 ? '+' : ''}${value.round()}$suffix',
          textAlign: TextAlign.end,
        ),
      ),
    ],
  );
}
