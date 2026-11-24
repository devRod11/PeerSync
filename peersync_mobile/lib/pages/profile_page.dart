
import 'package:flutter/material.dart';

import '../models/authenticated_user.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class ProfilePage extends StatelessWidget {
  final AuthenticatedUser user;

  const ProfilePage({
    super.key,
    required this.user,
  });

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'U';
    }

    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final student = user.role.toLowerCase() == 'student';

    final displayName =
        user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'User';

    final accountRole = student ? 'Student' : 'Professor';

    return PageBody(children: [
      const ScreenHeading(
        title: 'Profile & settings',
        detail: 'Manage your account and preferences.',
      ),

      // Authenticated account information
      InfoCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFDCE5F2),
              child: Text(
                _getInitials(user.displayName),
                style: const TextStyle(
                  color: ink,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: titleStyle),
                  Text(user.email ?? 'No email available', style: subStyle),
                  Text(
                    accountRole,
                    style: subStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      const SectionHeading('Account information'),

      InfoCard(
        child: Column(
          children: [
            DetailLine('Display name', displayName),
            DetailLine('Email address', user.email ?? 'Not available'),
            DetailLine('Account role', accountRole),
            DetailLine(
              'Account status',
              user.isActive ? 'Active' : 'Inactive',
            ),
          ],
        ),
      ),

      const SectionHeading('Notifications'),

      const SwitchTile(
        title: 'In-app notifications',
        subtitle: 'Announcements, deadlines, and feedback',
      ),

      const SwitchTile(
        title: 'Email notifications',
        subtitle: 'Daily summary and urgent updates',
      ),

      SwitchTile(
        title: student
            ? 'Deadline reminders'
            : 'Pending review reminders',
        subtitle: student
            ? 'Notify me 3 days before'
            : 'Send a daily summary',
        trailing: const Icon(Icons.chevron_right),
      ),

      const SectionHeading('Account'),

      const DataRowTile(
        title: 'Password & security',
        subtitle: 'Manage your account security',
        icon: Icons.lock_outline,
      ),

      DataRowTile(
        title: student ? 'My classes & groups' : 'Class management',
        subtitle: student
            ? 'View your enrolled classes and group'
            : 'Manage your classes and student groups',
        icon: Icons.menu_book_outlined,
      ),

      Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Save changes',
              enabled: false,
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlineButtonX(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    ]);
  }
}
