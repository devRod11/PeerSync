import 'package:flutter/material.dart';

import '../core/a11y/app_a11y.dart';
import '../models/authenticated_user.dart';
import '../models/group.dart';
import '../models/milestone.dart';
import '../models/project.dart';
import '../models/submission.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class ProfessorDashboard extends StatefulWidget {
  final ValueChanged<int> go;
  final AuthenticatedUser user;

  const ProfessorDashboard({
    super.key,
    required this.go,
    required this.user,
  });

  @override
  State<ProfessorDashboard> createState() => _ProfessorDashboardState();
}

class _ProfessorDashboardState extends State<ProfessorDashboard> {
  late Future<_ProfessorDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_ProfessorDashboardData> _loadDashboard() async {
    final results = await Future.wait([
      ApiService.getProjects(),
      ApiService.getGroups(),
      ApiService.getTasks(),
      ApiService.getMilestones(),
      ApiService.getSubmissions(),
    ]);

    return _ProfessorDashboardData(
      projects: results[0] as List<Project>,
      groups: results[1] as List<Group>,
      tasks: results[2] as List<Task>,
      milestones: results[3] as List<Milestone>,
      submissions: results[4] as List<Submission>,
    );
  }

  void _retry() {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
  }

  String _greetingName() {
    final name = widget.user.displayName?.trim();

    if (name == null || name.isEmpty) {
      return 'Professor';
    }

    return name;
  }

  String _formatDate(DateTime date) => AppA11y.formatDate(date);

  String _formatRelativeDate(DateTime? date) =>
      AppA11y.relativeTime(date);

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return FutureBuilder<_ProfessorDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PageBody(
            children: [
              SizedBox(height: 120),
              LoadingView(message: 'Loading your dashboard\u2026'),
            ],
          );
        }

        if (snapshot.hasError) {
          return PageBody(
            children: [
              ScreenHeading(
                eyebrow: _formatDate(now).toUpperCase(),
                title: 'Welcome, ${_greetingName()}.',
                detail: 'Here is what needs your attention today.',
              ),
              InfoCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 38,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Unable to load dashboard data.',
                      style: titleStyle,
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Please check your connection and try again.',
                      style: subStyle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      label: 'Try again',
                      onPressed: _retry,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final data = snapshot.data!;

        final uniqueStudentIDs = <String>{};

        for (final group in data.groups) {
          if (group.members.isNotEmpty) {
            uniqueStudentIDs.addAll(
              group.members.map((member) => member.studentID),
            );
          } else {
            uniqueStudentIDs.addAll(group.memberIDs);
          }
        }

        final pendingSubmissions = data.submissions
            .where((submission) =>
                submission.status.toLowerCase() == 'pending')
            .toList();

        final upcomingDeadlines = <_DashboardDeadline>[];

        for (final task in data.tasks) {
          final dueDate = task.dueDate;

          if (dueDate.isAfter(DateTime.now()) &&
             task.status.toLowerCase() != 'completed') {
            upcomingDeadlines.add(
              _DashboardDeadline(
                title: task.title,
                subtitle: 'Task deadline',
                dueDate: dueDate,
              ),
            );
          }
        }

        for (final milestone in data.milestones) {
          final dueDate = milestone.dueDate;

        if (dueDate.isAfter(DateTime.now()) &&
            milestone.status.toLowerCase() != 'completed'){
            upcomingDeadlines.add(
              _DashboardDeadline(
                title: milestone.title,
                subtitle: 'Milestone deadline',
                dueDate: dueDate,
              ),
            );
          }
        }

        upcomingDeadlines.sort(
          (a, b) => a.dueDate.compareTo(b.dueDate),
        );

        final recentSubmissions = [...data.submissions]
          ..sort((a, b) {
            final dateA = a.submittedAt ?? DateTime(2000);
            final dateB = b.submittedAt ?? DateTime(2000);
            return dateB.compareTo(dateA);
          });

        final groupNames = {
          for (final group in data.groups) group.id: group.groupName,
        };

        final taskTitles = {
          for (final task in data.tasks) task.id: task.title,
        };

        final studentNames = <String, String>{};

        for (final group in data.groups) {
          for (final member in group.members) {
            studentNames[member.studentID] = member.displayName;
          }
        }

        return PageBody(
          children: [
            ScreenHeading(
              eyebrow: _formatDate(now).toUpperCase(),
              title: 'Welcome, ${_greetingName()}.',
              detail: 'Here is what needs your attention today.',
            ),

            Row(
              children: [
                Expanded(
                  child: StatTile(
                    '${data.projects.length}',
                    'Projects',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    '${uniqueStudentIDs.length}',
                    'Students',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    '${data.groups.length}',
                    'Groups',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    '${pendingSubmissions.length}',
                    'Pending',
                    highlighted: true,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: '＋ Announcement',
                    onPressed: () => widget.go(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlineButtonX(
                    label: ' Activity',
                    onPressed: () => widget.go(5),
                  ),
                ),
              ],
            ),

            const SectionHeading(
              'Managed projects',
              action: 'See all',
            ),

            if (data.projects.isEmpty)
              const InfoCard(
                child: Text(
                  'No projects are currently available.',
                  style: subStyle,
                ),
              )
            else
              ...data.projects.take(3).map((project) {
                final projectTasks = data.tasks
                    .where((task) => task.projectID == project.id)
                    .toList();

                final completedTasks = projectTasks
                    .where((task) =>
                        task.status.toLowerCase() == 'completed')
                    .length;

                final progress = projectTasks.isEmpty
                    ? 0.0
                    : completedTasks / projectTasks.length;

                return InfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BadgeX(project.academicYear),
                      const SizedBox(height: 8),
                      Text(project.title, style: titleStyle),
                      Text(
                        '${projectTasks.length} tasks · '
                        '${project.status}',
                        style: subStyle,
                      ),
                      const SizedBox(height: 10),
                      ProgressBar(value: progress),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Task completion  ${(progress * 100).round()}%',
                          style: subStyle,
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SectionHeading(
              'Needs attention',
              action: 'Review all',
            ),

            if (pendingSubmissions.isEmpty)
              const InfoCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.success,
                    child: Icon(
                      Icons.check,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    'No pending submissions',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'You are all caught up!',
                    style: subStyle,
                  ),
                ),
              )
            else
              InfoCard(
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: ink,
                      child: Icon(
                        Icons.assignment_outlined,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      '${pendingSubmissions.length} pending submissions',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Student submissions waiting for your review.',
                      style: subStyle,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.go(3),
                  ),
                ),
              ),

            const SectionHeading(
              'Recent submissions',
              action: 'View progress',
            ),

            if (recentSubmissions.isEmpty)
              const InfoCard(
                child: Text(
                  'No student submissions yet.',
                  style: subStyle,
                ),
              )
            else
              ...recentSubmissions.take(3).map((submission) {
                final studentName =
                    studentNames[submission.submittedBy] ??
                    'Student';

                final groupName =
                    groupNames[submission.groupID] ?? 'Group';

                final taskTitle =
                    taskTitles[submission.taskID] ?? 'Task submission';

                return DataRowTile(
                  title: '$studentName submitted an update',
                  subtitle: '$groupName · $taskTitle · '
                      '${_formatRelativeDate(submission.submittedAt)}',
                  leading: _initials(studentName),
                );
              }),

            const SectionHeading('Upcoming deadlines'),

            if (upcomingDeadlines.isEmpty)
              const InfoCard(
                child: Text(
                  'There are no upcoming task or milestone deadlines.',
                  style: subStyle,
                ),
              )
            else
              ...upcomingDeadlines.take(3).map((deadline) {
                final daysLeft =
                    deadline.dueDate.difference(DateTime.now()).inDays;

                final label = daysLeft == 0
                    ? 'DUE TODAY'
                    : daysLeft == 1
                        ? '1 DAY LEFT'
                        : '$daysLeft DAYS LEFT';

                return DataRowTile(
                  title: deadline.title,
                  subtitle: '${deadline.subtitle} · '
                      '${_formatDate(deadline.dueDate)}',
                  leading: '${deadline.dueDate.day}',
                  trailing: label,
                );
              }),
          ],
        );
      },
    );
  }
}

class _ProfessorDashboardData {
  final List<Project> projects;
  final List<Group> groups;
  final List<Task> tasks;
  final List<Milestone> milestones;
  final List<Submission> submissions;

  const _ProfessorDashboardData({
    required this.projects,
    required this.groups,
    required this.tasks,
    required this.milestones,
    required this.submissions,
  });
}

class _DashboardDeadline {
  final String title;
  final String subtitle;
  final DateTime dueDate;

  const _DashboardDeadline({
    required this.title,
    required this.subtitle,
    required this.dueDate,
  });
}