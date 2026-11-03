import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/chapter.dart';

class OutputUnitsSection extends StatelessWidget {
  const OutputUnitsSection({
    required this.strings,
    required this.units,
    required this.checkedIndices,
    required this.selectedIndex,
    required this.busy,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onToggle,
    required this.onTap,
    super.key,
  });

  final AppStrings strings;
  final List<Chapter> units;
  final Set<int> checkedIndices;
  final int? selectedIndex;
  final bool busy;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final void Function(int index, bool checked) onToggle;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              strings.get('outputUnits'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: busy || units.isEmpty ? null : onSelectAll,
            child: Text(strings.get('selectAll')),
          ),
          TextButton(
            onPressed: busy || units.isEmpty ? null : onDeselectAll,
            child: Text(strings.get('deselectAll')),
          ),
        ],
      ),
      if (units.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(strings.get('outputUnitsEmpty')),
        )
      else
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: units.length,
          itemBuilder: (context, index) => ListTile(
            selected: selectedIndex == index,
            leading: Checkbox(
              value: checkedIndices.contains(index),
              onChanged: busy
                  ? null
                  : (checked) => onToggle(index, checked == true),
            ),
            title: Text(units[index].title),
            subtitle: Text(
              '${units[index].text.length} ${strings.get('characters')}',
            ),
            onTap: () => onTap(index),
          ),
        ),
    ],
  );
}
