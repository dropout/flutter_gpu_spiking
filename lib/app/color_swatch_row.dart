import 'package:flutter/material.dart';

class ColorSwatchRow extends StatelessWidget {
  const ColorSwatchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.swatches = defaultSwatches,
  });

  static const defaultSwatches = <Color>[
    Color(0xFF1E1954),
    Color(0xFF342B91),
    Color(0xFF0D75F8),
    Color(0xFFA81FE0),
    Color(0xFFFF2BD6),
    Color(0xFF00E5FF),
    Color(0xFFFFB300),
    Color(0xFF111111),
  ];

  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;
  final List<Color> swatches;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final color in swatches)
                  GestureDetector(
                    onTap: () => onChanged(color),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == value ? Colors.white : Colors.white24,
                          width: color == value ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
