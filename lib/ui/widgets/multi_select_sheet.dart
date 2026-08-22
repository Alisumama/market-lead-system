import 'package:flutter/material.dart';

/// A searchable, multi-select bottom sheet. Returns the chosen set (an empty
/// set means "all"), or null if dismissed.
class MultiSelectSheet extends StatefulWidget {
  final String title;
  final String searchHint;
  final String allLabel;
  final List<String> options;
  final Set<String> selected;
  const MultiSelectSheet({
    super.key,
    required this.title,
    required this.searchHint,
    required this.allLabel,
    required this.options,
    required this.selected,
  });

  @override
  State<MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<MultiSelectSheet> {
  late final Set<String> _sel = {...widget.selected};
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where((c) => c.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final maxH = MediaQuery.sizeOf(context).height * 0.8;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(widget.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (_sel.isNotEmpty)
                    TextButton(
                        onPressed: () => setState(_sel.clear),
                        child: Text('Clear (${_sel.length})')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _q = '');
                          }),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No matches',
                          style: Theme.of(context).textTheme.bodySmall))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final on = _sel.contains(c);
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          title: Text(c),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (_) => setState(
                              () => on ? _sel.remove(c) : _sel.add(c)),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, <String>{}),
                      child: Text(widget.allLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _sel),
                      child: Text(
                          _sel.isEmpty ? 'Apply' : 'Apply (${_sel.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
