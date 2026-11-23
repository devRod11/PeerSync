import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';

class MyClassesPage extends StatefulWidget {
  const MyClassesPage({super.key});

  @override
  State<MyClassesPage> createState() => _MyClassesPageState();
}

class _MyClassesPageState extends State<MyClassesPage> {
  List<Group> _groups = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  // Retrieve the student's groups and accessible projects.
  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final groups = await ApiService.getGroups();

      if (!mounted) return;

      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  // Display group information.
  Widget _buildGroupCard(Group group) {

    final isLeaderAssigned = group.leaderID != null &&
        group.leaderID!.isNotEmpty;

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BadgeX('MY GROUP', dark: true),
              const Spacer(),
              Text(
                '${group.members.length} MEMBERS',
                style: subStyle,
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            group.groupName,
            style: titleStyle,
          ),

          Text(
            group.projectTitle,
            style: subStyle,
          ),

          const SizedBox(height: 14),

          const Divider(),

          Row(
            children: [
              const Icon(
                Icons.people_outline,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${group.members.length} group members',
                  style: subStyle,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Icon(
                Icons.star_outline,
                size: 18,
                color: isLeaderAssigned
                    ? Colors.amber.shade800
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLeaderAssigned
                      ? 'Group Leader assigned'
                      : 'No Group Leader assigned',
                  style: subStyle,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          OutlineButtonX(
            label: 'View group workspace',
            onPressed: () => _showGroupDetails(group),
          ),
        ],
      ),
    );
  }

  // Display group details.
  void _showGroupDetails(Group group) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(group.groupName),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PROJECT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  group.projectTitle,
                ),

                const SizedBox(height: 16),

                const Text(
                  'GROUP MEMBERS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),

                if (group.members.isEmpty)
                  const Text('No members found.')
                else
                  ...group.members.map((member) {
                  final isLeader = member.studentID == group.leaderID;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isLeader ? Icons.star : Icons.person_outline,
                      color: isLeader ? Colors.amber.shade800 : null,
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(
                      '${member.memberRole} · ${member.email}',
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        ScreenHeading(
          title: 'My classes',
          detail:
              '4 enrolled classes · ${_groups.length} active groups',
        ),

        const SearchField(hint: 'Search classes'),

        const SizedBox(height: 10),

        const InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BadgeX('IT 401 · 4A', dark: true),
                  Spacer(),
                  Text('72%', style: titleStyle),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Capstone Project 1',
                style: titleStyle,
              ),
              Text(
                'Prof. Maria Diaz · M/W 10:00–11:30',
                style: subStyle,
              ),
              SizedBox(height: 10),
              ProgressBar(value: .72),
              SizedBox(height: 12),
              MetricsRow(
                items: [
                  ('02', 'Activities'),
                  ('03', 'Deadlines'),
                  ('01', 'Group'),
                ],
              ),
            ],
          ),
        ),

        const SectionHeading(
          'Quick access',
          action: 'Class details',
        ),

        const Row(
          children: [
            Expanded(
              child: QuickTile(
                icon: Icons.campaign_outlined,
                title: 'Announcements',
                subtitle: '2 unread',
              ),
            ),
            Expanded(
              child: QuickTile(
                icon: Icons.description_outlined,
                title: 'Activities',
                subtitle: '2 pending',
              ),
            ),
            Expanded(
              child: QuickTile(
                icon: Icons.calendar_month_outlined,
                title: 'Deadlines',
                subtitle: 'Next: Oct 17',
              ),
            ),
          ],
        ),

        SectionHeading(
          'My groups',
          action: 'Refresh',
        ),

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (_errorMessage != null)
          InfoCard(
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 36,
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadGroups,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          )
        else if (_groups.isEmpty)
          const InfoCard(
            child: Column(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 40,
                ),
                SizedBox(height: 8),
                Text(
                  'You are not assigned to any group yet.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._groups.map(_buildGroupCard),

        const SectionHeading('Team updates', action: 'View all'),

        const DataRowTile(
          title: 'Ana uploaded interview notes',
          subtitle: 'Today · 10:14 AM',
          leading: 'AR',
        ),

        const DataRowTile(
          title: 'Mika completed assigned task',
          subtitle: 'Yesterday · Chapter 2',
          leading: 'MS',
        ),

        PrimaryButton(
          label: '＋ Submit team update',
          onPressed: () {},
        ),
      ],
    );
  }
}
