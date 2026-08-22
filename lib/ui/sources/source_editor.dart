import 'package:flutter/material.dart';

import '../../data/models/feed_source.dart';
import '../../data/models/lead.dart';

/// Add or edit a feed source. Kept deliberately simple: name, URL, type,
/// country, enabled. World Bank / built-in kinds are shown read-only.
class SourceEditor extends StatefulWidget {
  final FeedSource? source;
  const SourceEditor({super.key, this.source});

  @override
  State<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<SourceEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.source?.name ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.source?.url ?? '');
  late final TextEditingController _country =
      TextEditingController(text: widget.source?.country ?? 'global');
  late SourceKind _kind = widget.source?.kind ?? SourceKind.rss;
  late bool _enabled = widget.source?.enabled ?? true;

  bool get _isEdit => widget.source != null;
  bool get _isSpecialKind =>
      _kind == SourceKind.worldBank || _kind == SourceKind.other;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final base = widget.source;
    final result = (base ??
            const FeedSource(name: '', url: '', builtIn: false))
        .copyWith(
      name: _name.text.trim(),
      url: _url.text.trim(),
      kind: _kind,
      country: _country.text.trim().isEmpty ? 'global' : _country.text.trim(),
      enabled: _enabled,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEdit ? 'Edit source' : 'Add source',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.label_outline)),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _url,
                decoration: const InputDecoration(
                    labelText: 'Feed URL (RSS / Atom / Google News)',
                    prefixIcon: Icon(Icons.link)),
                keyboardType: TextInputType.url,
                readOnly: _isSpecialKind,
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Required';
                  if (!s.startsWith('http')) return 'Must start with http';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<SourceKind>(
                initialValue: _isSpecialKind ? _kind : _kind,
                decoration: const InputDecoration(
                    labelText: 'Type',
                    prefixIcon: Icon(Icons.category_outlined)),
                items: [
                  const DropdownMenuItem(
                      value: SourceKind.rss, child: Text('News (RSS/Atom)')),
                  const DropdownMenuItem(
                      value: SourceKind.googleAlert,
                      child: Text('Google Alert / News search')),
                  if (_kind == SourceKind.worldBank)
                    const DropdownMenuItem(
                        value: SourceKind.worldBank,
                        child: Text('World Bank (built-in)')),
                ],
                onChanged: _isSpecialKind
                    ? null
                    : (v) => setState(() => _kind = v ?? SourceKind.rss),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _country,
                decoration: const InputDecoration(
                    labelText: 'Country tag',
                    hintText: 'global, pk, tr, ng…',
                    prefixIcon: Icon(Icons.public)),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                subtitle: const Text('Included on the next refresh'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(_isEdit ? 'Save' : 'Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _country.dispose();
    super.dispose();
  }
}
