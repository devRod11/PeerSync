import 'package:flutter/material.dart';

import '../core/utils/error_messages.dart';
import '../models/announcement.dart';
import '../models/group.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';

class MyClassesPage extends StatefulWidget {
  const MyClassesPage({super.key});

  @override
  State<MyClassesPage> createState() => _MyClassesPageState();
}

class _MyClassesPageState extends State<MyClassesPage> {
  final TextEditingController _searchController = TextEditingController();

  List<Group> _groups = [];
  List<Task> _tasks = [];
  List<Announcement> _announcements = [];

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Retrieve the authenticated student's groups, tasks, and announcements.
  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final groups = await ApiService.getGroups();

      // Retrieve tasks and announcements for each accessible group.
      final results = await Future.wait(
        groups.map((group) async {
          final responses = await Future.wait([
            ApiService.getTasks(groupID: group.id),
            ApiService.getAnnouncements(groupID: group.id),
          ]);

          return (
            tasks: responses[0] as List<Task>,
            announcements: responses[1] as List<Announcement>,
          );
        }),
      );

      final taskMap = <String, Task>{};
      final announcementMap = <String, Announcement>{};

      for (final result in results) {
        for (final task in result.tasks) {
          taskMap[task.id] = task;
        }

        for (final announcement in result.announcements) {
          announcementMap[announcement.id] = announcement;
        }
      }

      final tasks = taskMap.values.toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

      final announcements = announcementMap.values.toList()
        ..sort((a, b) {
          final dateA =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

          return dateB.compareTo(dateA);
        });

      if (!mounted) return;

      setState(() {
        _groups = groups;
        _tasks = tasks;
        _announcements = announcements;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = friendlyErrorMessage(error);
        _isLoading = false;
      });
    }
  }

  // Filter groups using the group name or project title.
  List<Group> get _filteredGroups {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) return _groups;

    return _groups.where((group) {
      return group.groupName.toLowerCase().contains(query) ||
          group.projectTitle.toLowerCase().contains(query);
    }).toList();
  }

  // Group the student's groups by their associated project.
  Map<String, List<Group>> get _groupsByProject {
    final result = <String, List<Group>>{};

    for (final group in _filteredGroups) {
      result.putIfAbsent(group.projectID, () => []).add(group);
    }

    return result;
  }

  int get _projectCount => _groups
      .map((group) => group.projectID)
      .toSet()
      .length;

  int get _upcomingDeadlineCount {
    final now = DateTime.now();

    return _tasks.where((task) {
      final status = task.status.toLowerCase().trim();

      return task.dueDate.isAfter(now) &&
          status != 'completed' &&
          status != 'approved';
    }).length;
  }

  int _taskCountForProject(List<Group> groups) {
    final groupIDs = groups.map((group) => group.id).toSet();

    return _tasks
        .where((task) => groupIDs.contains(task.groupID))
        .length;
  }

  int _deadlineCountForProject(List<Group> groups) {
    final groupIDs = groups.map((group) => group.id).toSet();
    final now = DateTime.now();

    return _tasks.where((task) {
      final status = task.status.toLowerCase().trim();

      return groupIDs.contains(task.groupID) &&
          task.dueDate.isAfter(now) &&
          status != 'completed' &&
          status != 'approved';
    }).length;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Date unavailable';

    final localDate = date.toLocal();

    return '${localDate.day.toString().padLeft(2, '0')}/'
        '${localDate.month.toString().padLeft(2, '0')}/'
        '${localDate.year}';
  }

  String _announcementTargetLabel(Announcement announcement) {
    final targetGroupIDs = announcement.groupID ?? [];

    if (targetGroupIDs.isEmpty) {
      return 'Project announcement';
    }

    final groupNames = _groups
        .where((group) => targetGroupIDs.contains(group.id))
        .map((group) => group.groupName)
        .toList();

    if (groupNames.isEmpty) {
      return 'Group announcement';
    }

    return groupNames.join(', ');
  }

  // Display one project and its associated student groups.
  Widget _buildProjectCard(
    String projectID,
    List<Group> groups,
  ) {
    final projectTitle = groups.first.projectTitle;
    final taskCount = _taskCountForProject(groups);
    final deadlineCount = _deadlineCountForProject(groups);


    final colors = Theme.of(context).colorScheme;

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BadgeX('MY CLASS', dark: true),
              const Spacer(),
              Text(
                '${groups.length} ${groups.length == 1 ? 'GROUP' : 'GROUPS'}',
                style: subStyle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            projectTitle,
            style: titleStyle,
          ),
          const SizedBox(height: 4),
          Text(
            'Project ID: $projectID',
            style: subStyle,
          ),
          const SizedBox(height: 14),
          Divider(color: colors.outlineVariant),
          Row(
            children: [
              Icon(
                Icons.groups_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${groups.length} assigned '
                  '${groups.length == 1 ? 'group' : 'groups'}',
                  style: subStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$taskCount assigned '
                  '${taskCount == 1 ? 'activity' : 'activities'}',
                  style: subStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$deadlineCount upcoming '
                  '${deadlineCount == 1 ? 'deadline' : 'deadlines'}',
                  style: subStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
}

  // Display group information.
  Widget _buildGroupCard(Group group) {
    final colors = Theme.of(context).colorScheme;
    final isLeaderAssigned =
        group.leaderID != null && group.leaderID!.isNotEmpty;

    final isCurrentStudentLeader = group.members.any(
      (member) =>
          member.studentID == group.leaderID &&
          group.leaderID!.isNotEmpty,
    );

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
          Divider(color: colors.outlineVariant),
          Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 18,
                color: colors.onSurfaceVariant,
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
                  ? colors.tertiary
                  : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLeaderAssigned
                      ? isCurrentStudentLeader
                          ? 'You are the Group Leader'
                          : 'Group Leader assigned'
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

  // Display group details and actual group members.
  void _showGroupDetails(Group group) {
    final colors = Theme.of(context).colorScheme;
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
                Text(
                  'PROJECT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(group.projectTitle),
                const SizedBox(height: 16),
                Text(
                  'GROUP MEMBERS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (group.members.isEmpty)
                  const Text('No members found.')
                else
                  ...group.members.map((member) {
                    final isLeader =
                        member.studentID == group.leaderID;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isLeader
                            ? Icons.star
                            : Icons.person_outline,
                        color: isLeader
                            ? colors.tertiary
                            : colors.onSurfaceVariant,
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
              child: Text(
                'Close',
                style: TextStyle(color: colors.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  // Display recent announcements retrieved from the backend.
  Widget _buildAnnouncementCard(Announcement announcement) {
    final colors = Theme.of(context).colorScheme;

    return InfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 24,
            color: colors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.title,
                  style: titleStyle,
                ),
                const SizedBox(height: 5),
                Text(
                  announcement.content,
                  style: subStyle.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  _announcementTargetLabel(announcement),
                  style: subStyle.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(announcement.createdAt),
                  style: subStyle.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectList() {
    final projects = _groupsByProject;

    if (projects.isEmpty) {
      return InfoCard(
        child: Column(
          children: [
            Icon(
              Icons.school_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'No classes assigned yet.'
                  : 'No classes match your search.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Your assigned classes and project groups will appear here.',
              textAlign: TextAlign.center,
              style: subStyle.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: projects.entries.map((entry) {
        return _buildProjectCard(entry.key, entry.value);
      }).toList(),
    );
  }

  Widget _buildRecentAnnouncements() {
    if (_announcements.isEmpty) {
      final colors = Theme.of(context).colorScheme;

      return InfoCard(
        child: Column(
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 36,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            const Text(
              'No announcements yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Announcements for your classes and groups will appear here.',
              textAlign: TextAlign.center,
              style: subStyle.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final recentAnnouncements = _announcements.take(5).toList();

    return Column(
      children: recentAnnouncements
          .map(_buildAnnouncementCard)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        ScreenHeading(
          title: 'My classes',
          detail: '$_projectCount '
              '${_projectCount == 1 ? 'class' : 'classes'} · '
              '${_groups.length} '
              '${_groups.length == 1 ? 'active group' : 'active groups'}',
        ),

        TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          decoration: InputDecoration(
            hintText: 'Search classes or groups',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.close),
                  )
                : null,
          ),
        ),

        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Refresh classes',
              onPressed: _isLoading ? null : _loadGroups,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),

        if (_isLoading)
          const LoadingView(
            message: 'Loading your classes and groups…',
          )
        else if (_errorMessage != null)
          ErrorStateView(
            message: _errorMessage!,
            onRetry: _loadGroups,
          )
        else ...[
          const SectionHeading('Class overview'),
          InfoCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildOverviewMetric(
                        Icons.school_outlined,
                        '$_projectCount',
                        'Classes',
                      ),
                    ),
                    Expanded(
                      child: _buildOverviewMetric(
                        Icons.assignment_outlined,
                        '${_tasks.length}',
                        'Activities',
                      ),
                    ),
                    Expanded(
                      child: _buildOverviewMetric(
                        Icons.calendar_month_outlined,
                        '$_upcomingDeadlineCount',
                        'Deadlines',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SectionHeading('My classes'),
          _buildProjectList(),

          const SectionHeading('My groups'),
          if (_filteredGroups.isEmpty)
            InfoCard(
              child: Text(
                'No groups found.',
                textAlign: TextAlign.center,
                style: subStyle.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._filteredGroups.map(_buildGroupCard),

          const SectionHeading('Recent announcements'),
          _buildRecentAnnouncements(),
        ],
      ],
    );
  }

  Widget _buildOverviewMetric(
    IconData icon,
    String value,
    String label,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(
          icon,
          size: 22,
          color: colors.primary,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: titleStyle,
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: subStyle.copyWith(
            color: colors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}