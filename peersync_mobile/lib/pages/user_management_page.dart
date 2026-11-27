import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import '../core/utils/error_messages.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';


class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final _formKey = GlobalKey<FormState>();
  late Future<List<Map<String, dynamic>>> _usersFuture;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();
  final Set<String> _updatingUserIds = {};

  String _selectedRoleFilter = 'all';
  String _selectedStatusFilter = 'all';

  String _selectedRole = 'student';
  bool _isPasswordVisible = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _usersFuture = ApiService.getUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshUsers() {
    setState(() {
      _usersFuture = ApiService.getUsers();
    });
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() => _isCreating = true);

    try {
      final response = await ApiService.createUser(
        displayName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        role: _selectedRole,
      );

      if (!mounted) return;

      final user = response['user'] as Map<String, dynamic>;
      final createdName = user['displayName']?.toString() ?? 'User';
      final createdEmail = user['email']?.toString() ?? '';

      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();

      setState(() {
        _selectedRole = 'student';
        _isPasswordVisible = false;
        _usersFuture = ApiService.getUsers();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$createdName ($createdEmail) was registered successfully.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to create account: ${friendlyErrorMessage(error)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }


  Future<void> _confirmAndUpdateUserStatus(
    Map<String, dynamic> user,
  ) async {
    final uid = user['uid']?.toString() ?? '';
    final name = user['displayName']?.toString() ?? 'this user';
    final isCurrentlyActive = user['isActive'] == true;
    final newStatus = !isCurrentlyActive;

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to identify this user account.'),
        ),
      );
      return;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (!newStatus && uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot deactivate your own account.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            newStatus ? 'Activate account?' : 'Deactivate account?',
          ),
          content: Text(
            newStatus
                ? 'Are you sure you want to activate $name? '
                    'They will be able to sign in to PeerSync again.'
                : 'Are you sure you want to deactivate $name? '
                    'They will no longer be able to sign in to PeerSync.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(newStatus ? 'Activate' : 'Deactivate'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _updatingUserIds.add(uid));

    try {
      await ApiService.updateUserStatus(
        uid: uid,
        isActive: newStatus,
      );

      if (!mounted) return;

      _refreshUsers();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$name was ${newStatus ? 'activated' : 'deactivated'} successfully.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to update account: ${friendlyErrorMessage(error)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingUserIds.remove(uid));
      }
    }
  }


  String _formatCreatedAt(dynamic value) {
    if (value == null) return 'Date unavailable';

    final date = DateTime.tryParse(value.toString());

    if (date == null) return 'Date unavailable';

    final localDate = date.toLocal();

    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');

    return '$month/$day/${localDate.year}';
  }

  Widget _buildUserList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return InfoCard(
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 32,
                  color: Colors.red,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Unable to load user accounts.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _refreshUsers,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          );
        }

        final allUsers = snapshot.data ?? [];
        final users = _filterUsers(allUsers);

        if (users.isEmpty) {
          return InfoCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  allUsers.isEmpty
                      ? 'No registered accounts found.'
                      : 'No accounts match your search or filters.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return Column(
          children: users.map((user) {
            final name =
                user['displayName']?.toString() ?? 'Unnamed user';

            final email = user['email']?.toString() ?? '';

            final role =
                user['role']?.toString().toUpperCase() ?? 'UNKNOWN';

            final isActive = user['isActive'] == true;

            final createdAt = _formatCreatedAt(user['createdAt']);
            final uid = user['uid']?.toString() ?? '';
            final isCurrentUser = uid == FirebaseAuth.instance.currentUser?.uid;
            final isUpdating = _updatingUserIds.contains(uid);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      child: Text(
                        name.isNotEmpty
                            ? name[0].toUpperCase()
                            : '?',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Chip(
                                label: Text(role),
                                visualDensity: VisualDensity.compact,
                              ),
                              Chip(
                                label: Text(
                                  isActive ? 'Active' : 'Inactive',
                                ),
                                avatar: Icon(
                                  isActive
                                      ? Icons.check_circle_outline
                                      : Icons.cancel_outlined,
                                  size: 16,
                                  color: isActive
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          Text(
                            'Registered: $createdAt',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (isCurrentUser)
                                const Chip(
                                  avatar: Icon(Icons.person_outline, size: 16),
                                  label: Text('Current account'),
                                  visualDensity: VisualDensity.compact,
                                )
                              else
                                OutlinedButton.icon(
                                  onPressed: isUpdating
                                      ? null
                                      : () => _confirmAndUpdateUserStatus(user),
                                  icon: isUpdating
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          isActive
                                              ? Icons.block_outlined
                                              : Icons.check_circle_outline,
                                        ),
                                  label: Text(
                                    isUpdating
                                        ? 'Updating...'
                                        : isActive
                                            ? 'Deactivate'
                                            : 'Activate',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  List<Map<String, dynamic>> _filterUsers(
    List<Map<String, dynamic>> users,
  ) {
    final search = _searchController.text.trim().toLowerCase();

    return users.where((user) {
      final name = user['displayName']?.toString().toLowerCase() ?? '';
      final email = user['email']?.toString().toLowerCase() ?? '';
      final role = user['role']?.toString().toLowerCase() ?? '';
      final isActive = user['isActive'] == true;

      final matchesSearch =
          search.isEmpty || name.contains(search) || email.contains(search);

      final matchesRole =
          _selectedRoleFilter == 'all' || role == _selectedRoleFilter;

      final matchesStatus =
          _selectedStatusFilter == 'all' ||
          (_selectedStatusFilter == 'active' && isActive) ||
          (_selectedStatusFilter == 'inactive' && !isActive);

      return matchesSearch && matchesRole && matchesStatus;
    }).toList();
  }

  Widget _buildUserFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name or email',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedRoleFilter,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All roles')),
                  DropdownMenuItem(value: 'student', child: Text('Students')),
                  DropdownMenuItem(
                    value: 'professor',
                    child: Text('Professors'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRoleFilter = value);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedStatusFilter,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedStatusFilter = value);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PageBody(
      children: [
        const ScreenHeading(
          eyebrow: 'ACCOUNT MANAGEMENT',
          title: 'User management',
          detail: 'Create Student and Professor accounts for PeerSync.',
        ),

        InfoCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: colors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Accounts created here are saved in Firebase Authentication '
                  'and their profiles are stored in Firestore.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),

        const SectionHeading('Register a new account'),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('Full name'),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  hintText: 'Enter the user’s full name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';

                  if (name.isEmpty) {
                    return 'Full name is required.';
                  }

                  if (name.length < 2) {
                    return 'Name must contain at least 2 characters.';
                  }

                  return null;
                },
              ),

              const FieldLabel('Email address'),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  hintText: 'user@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  final emailPattern =
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

                  if (email.isEmpty) {
                    return 'Email address is required.';
                  }

                  if (!emailPattern.hasMatch(email)) {
                    return 'Enter a valid email address.';
                  }

                  return null;
                },
              ),

              const FieldLabel('Temporary password'),
              TextFormField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  hintText: 'At least 8 characters',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _isPasswordVisible
                        ? 'Hide password'
                        : 'Show password',
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required.';
                  }

                  if (value.length < 8) {
                    return 'Password must contain at least 8 characters.';
                  }

                  return null;
                },
              ),

              const FieldLabel('Account role'),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'student',
                    child: Text('Student'),
                  ),
                  DropdownMenuItem(
                    value: 'professor',
                    child: Text('Professor'),
                  ),
                ],
                onChanged: _isCreating
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedRole = value);
                        }
                      },
              ),

              const SizedBox(height: 18),

              PrimaryButton(
                label: _isCreating
                    ? 'Creating account...'
                    : 'Create account',
                enabled: !_isCreating,
                onPressed: _createAccount,
              ),

              if (_isCreating) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: SectionHeading('Registered accounts'),
            ),
            IconButton(
              tooltip: 'Refresh accounts',
              onPressed: _refreshUsers,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildUserFilters(),
        const SizedBox(height: 16),
        _buildUserList(),
      ],
    );
  }
}