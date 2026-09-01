import 'package:flutter/material.dart';

class TagMemoryFieldV2 extends StatefulWidget {
  const TagMemoryFieldV2({
    required this.controller,
    required this.suggestions,
    this.hintText,
    super.key,
  });

  final TextEditingController controller;
  final Iterable<String> suggestions;
  final String? hintText;

  @override
  State<TagMemoryFieldV2> createState() => _TagMemoryFieldV2State();
}

class _TagMemoryFieldV2State extends State<TagMemoryFieldV2> {
  Set<String> get _selected => widget.controller.text
      .split(RegExp(r'[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final suggestions =
        widget.suggestions
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '标签',
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.tag),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('以前用过', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: suggestions
                .map(
                  (tag) => FilterChip(
                    label: Text(tag),
                    selected: selected.contains(tag),
                    onSelected: (_) => _toggle(tag),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  void _toggle(String tag) {
    final values = _selected;
    values.contains(tag) ? values.remove(tag) : values.add(tag);
    widget.controller.text = values.join(', ');
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    setState(() {});
  }
}
