import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/app_user.dart';

/// The result handed back from [UserEditor] when the form is saved. Carries the
/// assembled [user] plus the [rawPin] the admin typed (empty when editing and
/// left blank, meaning "keep the existing PIN"). Hashing is left to the caller
/// so the raw PIN never lingers in a model field.
class UserDraft {
  final AppUser user;
  final String rawPin;
  const UserDraft(this.user, this.rawPin);
}

/// Add or edit an application user: name, email, phone, role and PIN. Mirrors
/// SourceEditor — a scroll-safe bottom sheet with a Form and Cancel/Save.
class UserEditor extends StatefulWidget {
  final AppUser? user;
  const UserEditor({super.key, this.user});

  @override
  State<UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends State<UserEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.user?.name ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.user?.email ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.user?.phone ?? '');
  final _pin = TextEditingController();
  late UserRole _role = widget.user?.role ?? UserRole.viewer;
  late bool _active = widget.user?.active ?? true;
  bool _showPin = false;

  bool get _isEdit => widget.user != null;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final base = widget.user;
    final user = (base ?? const AppUser(name: '', email: '')).copyWith(
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      role: _role,
      active: _active,
    );
    Navigator.pop(context, UserDraft(user, _pin.text.trim()));
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
              Text(_isEdit ? 'Edit user' : 'Add user',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline)),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined)),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Required';
                  if (!_emailRe.hasMatch(s)) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone number',
                    prefixIcon: Icon(Icons.phone_outlined)),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return null; // optional
                  if (!RegExp(r'^[+0-9][0-9 ()-]{5,}$').hasMatch(s)) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.badge_outlined)),
                items: [
                  for (final r in UserRole.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setState(() {
                  _role = v ?? UserRole.viewer;
                  // Admins can't be deactivated, so promoting to admin forces
                  // the account active.
                  if (_role == UserRole.admin) _active = true;
                }),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pin,
                obscureText: !_showPin,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: _isEdit
                      ? 'PIN code (leave blank to keep current)'
                      : 'PIN code',
                  helperText: '4–8 digits',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_showPin
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPin = !_showPin),
                  ),
                ),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  // Editing: blank means keep the existing PIN.
                  if (_isEdit && s.isEmpty) return null;
                  if (s.length < 4) return 'At least 4 digits';
                  return null;
                },
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: Text(_role == UserRole.admin
                    ? 'Admins are always active'
                    : (_active
                        ? 'User is enabled'
                        : 'User is disabled — sign-in blocked')),
                value: _active,
                // Admins can't be deactivated.
                onChanged: _role == UserRole.admin
                    ? null
                    : (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
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
    _email.dispose();
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }
}
