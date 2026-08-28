import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/app_user.dart';
import '../../data/user_repository.dart';
import '../widgets/app_bar_bits.dart';
import 'user_editor.dart';

/// Manage the application users stored in the Firestore `Users` collection:
/// add, edit, delete, with a live list that updates across devices. Unlike the
/// rest of the app (local-first sqflite), this screen talks straight to
/// Firestore — the users live in the cloud so they can be managed centrally.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _repo = UserRepository();

  Future<void> _edit(AppUser? existing) async {
    final draft = await showModalBottomSheet<UserDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => UserEditor(user: existing),
    );
    if (draft == null || !mounted) return;

    try {
      // Guard against two users sharing an email.
      final clash = await _repo.emailTaken(draft.user.email,
          exceptId: existing?.id);
      if (clash) {
        _toast('A user with that email already exists');
        return;
      }

      if (existing == null) {
        final withPin =
            draft.user.copyWith(pinHash: AppUser.hashPin(draft.rawPin));
        await _repo.add(withPin);
        _toast('User added');
      } else if (draft.rawPin.isEmpty) {
        // Blank PIN on edit = keep the stored one.
        await _repo.updateKeepingPin(draft.user);
        _toast('User updated');
      } else {
        await _repo
            .update(draft.user.copyWith(pinHash: AppUser.hashPin(draft.rawPin)));
        _toast('User updated');
      }
    } catch (e) {
      _toast('Save failed: $e');
    }
  }

  Future<void> _toggleActive(AppUser user, bool active) async {
    if (user.id == null) return;
    // Admins can't be deactivated — guard here too, not just in the UI.
    if (!active && user.role == UserRole.admin) {
      _toast("Admins can't be deactivated");
      return;
    }
    try {
      await _repo.setActive(user.id!, active);
      _toast(active ? 'User activated' : 'User deactivated');
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  Future<void> _resetPin(AppUser user) async {
    if (user.id == null) return;
    final pin = await _promptPin(user);
    if (pin == null || !mounted) return;
    try {
      await _repo.setPinHash(user.id!, AppUser.hashPin(pin));
      _toast('PIN updated for ${user.name}');
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  /// A small dialog that collects a new PIN (4–8 digits) for [user].
  Future<String?> _promptPin(AppUser user) {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset PIN — ${user.name}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'New PIN',
              helperText: '4–8 digits',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 4) ? 'At least 4 digits' : null,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: const Text('Update PIN'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('Remove "${user.name}" from the Users collection?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || user.id == null || !mounted) return;
    try {
      await _repo.delete(user.id!);
      _toast('User deleted');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add user'),
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: _repo.watchAll(),
        builder: (context, snap) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                backgroundColor: translucentBarColor(context),
                flexibleSpace: frostedFlexibleSpace(),
                leading: mobileBrandLeading(context),
                leadingWidth: 58,
                automaticallyImplyLeading: false,
                titleSpacing:
                    mobileBrandLeading(context) == null ? 20 : 4,
                title: const Text('Users'),
              ),
              ..._buildBody(context, snap),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildBody(
      BuildContext context, AsyncSnapshot<List<AppUser>> snap) {
    if (snap.hasError) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(
            icon: Icons.cloud_off_outlined,
            title: "Can't reach the Users database",
            detail:
                'Firestore is unavailable on this platform or there is no '
                'connection.\n\n${snap.error}',
          ),
        ),
      ];
    }
    if (!snap.hasData) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final users = snap.data!;
    if (users.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(
            icon: Icons.group_outlined,
            title: 'No users yet',
            detail: 'Tap "Add user" to create the first one.',
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text('${users.length} user(s)',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        sliver: SliverList.separated(
          itemCount: users.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _UserCard(
            user: users[i],
            onEdit: () => _edit(users[i]),
            onDelete: () => _delete(users[i]),
            onResetPin: () => _resetPin(users[i]),
            onToggleActive: (v) => _toggleActive(users[i], v),
          ),
        ),
      ),
    ];
  }
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onResetPin;
  final ValueChanged<bool> onToggleActive;
  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onResetPin,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial =
        user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase();
    // Inactive users are dimmed so they read as disabled at a glance.
    final dim = user.active ? 1.0 : 0.5;
    // Admins can't be deactivated — lock the toggle for them.
    final canToggle = user.role != UserRole.admin;
    return Card(
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Opacity(
                opacity: dim,
                child: CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  foregroundColor: scheme.primary,
                  child: Text(initial,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: dim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name.isEmpty ? '(no name)' : user.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(user.email,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (user.phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(user.phone,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _RoleTag(role: user.role),
                          if (!user.active) ...[
                            const SizedBox(width: 6),
                            _InactiveTag(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Quick active/inactive toggle, mirroring the Sources screen.
              // Disabled for admins, who can't be deactivated.
              Tooltip(
                message: canToggle
                    ? (user.active ? 'Deactivate' : 'Activate')
                    : "Admins can't be deactivated",
                child: Switch(
                  value: user.active,
                  onChanged: canToggle ? onToggleActive : null,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      onEdit();
                    case 'pin':
                      onResetPin();
                    case 'toggle':
                      onToggleActive(!user.active);
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                      value: 'pin', child: Text('Reset PIN')),
                  if (canToggle)
                    PopupMenuItem(
                        value: 'toggle',
                        child:
                            Text(user.active ? 'Deactivate' : 'Activate')),
                  const PopupMenuItem(
                      value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InactiveTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('Inactive',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant)),
    );
  }
}

class _RoleTag extends StatelessWidget {
  final UserRole role;
  const _RoleTag({required this.role});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (role) {
      UserRole.admin => scheme.error,
      UserRole.manager => scheme.primary,
      UserRole.viewer => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(role.label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _Message(
      {required this.icon, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(detail,
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
