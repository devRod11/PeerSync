import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/authenticated_user.dart';
import '../models/project.dart';
import '../models/group.dart';
import '../models/task.dart';
import '../models/milestone.dart';
import '../models/submission.dart';
import '../models/announcement.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';

class StudentDashboard extends StatefulWidget {
  final ValueChanged<int> go;
  final AuthenticatedUser user;

  const StudentDashboard({
    super.key,
    required this.go,
    required this.user,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  late Future<_StudentDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_StudentDashboardData> _loadDashboard() async {
    final results = await Future.wait([
      ApiService.getProjects(),
      ApiService.getGroups(),
      ApiService.getTasks(),
      ApiService.getMilestones(),
      ApiService.getSubmissions(),
      ApiService.getAnnouncements(),
    ]);

    return _StudentDashboardData(
      projects: results[0] as List<Project>,
      groups: results[1] as List<Group>,
      tasks: results[2] as List<Task>,
      milestones: results[3] as List<Milestone>,
      submissions: results[4] as List<Submission>,
      announcements: results[5] as List<Announcement>,
    );
  }

  void _retry() {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
  }

  String _studentName() {
    final name = widget.user.displayName?.trim();

    if (name == null || name.isEmpty) {
      return 'Student';
    }

    return name;
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  String _formatRelativeDate(DateTime? date) {
    if (date == null) return 'Date unavailable';

    final difference = DateTime.now().difference(date);

    if (difference.inMinutes < 1 && !difference.isNegative) {
      return 'Just now';
    }

    if (difference.inMinutes < 60 && !difference.isNegative) {
      return '${difference.inMinutes} minutes ago';
    }

    if (difference.inHours < 24 && !difference.isNegative) {
      return '${difference.inHours} hours ago';
    }

    if (difference.inDays == 1) return 'Yesterday';

    if (difference.inDays > 1) {
      return '${difference.inDays} days ago';
    }

    return _formatDate(date);
  }

  int _daysUntil(DateTime date) {
    final today = DateTime.now();

    final todayDate = DateTime(today.year, today.month, today.day);
    final deadlineDate = DateTime(date.year, date.month, date.day);

    return deadlineDate.difference(todayDate).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return FutureBuilder<_StudentDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PageBody(
            children: [
              SizedBox(height: 180),
              Center(child: CircularProgressIndicator()),
              SizedBox(height: 12),
              Center(
                child: Text(
                  'Loading your dashboard...',
                  style: subStyle,
                ),
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return PageBody(
            children: [
              ScreenHeading(
                eyebrow: _formatDate(now).toUpperCase(),
                title: 'Welcome back, ${_studentName()}.',
                detail: 'Here is your latest academic progress.',
              ),
              InfoCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 38,
                      color: Colors.redAccent,
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
        final uid = widget.user.uid;

        // Identify the groups where this student is a member.
        final studentGroups = data.groups.where((group) {
          final isInMemberList = group.memberIDs.contains(uid);
          final isInMembers = group.members.any(
            (member) => member.studentID == uid,
          );

          return isInMemberList || isInMembers;
        }).toList();

        final studentGroupIDs =
            studentGroups.map((group) => group.id).toSet();

        final studentProjectIDs =
            studentGroups.map((group) => group.projectID).toSet();

        // Only include projects connected to the student's groups.
        final studentProjects = data.projects
            .where((project) => studentProjectIDs.contains(project.id))
            .toList();
  
        final projectById = { 
          for (final project in studentProjects) project.id: project,
        };

        // Only count tasks assigned to this student.
        final assignedTasks = data.tasks.where((task) {
          return studentGroupIDs.contains(task.groupID) &&
              task.assignedTo.contains(uid);
        }).toList();

        final completedTasks = assignedTasks.where(
          (task) => task.status.toLowerCase() == 'completed',
        ).length;

        final taskProgress = assignedTasks.isEmpty
            ? 0.0
            : completedTasks / assignedTasks.length;

        // Upcoming assigned task deadlines.
        final upcomingDeadlines = <_StudentDeadline>[];

        for (final task in assignedTasks) {
          if (task.dueDate.isAfter(DateTime.now()) &&
              task.status.toLowerCase() != 'completed') {
            final matchingGroups = studentGroups
                .where((group) => group.id == task.groupID)
                .toList();

            if (matchingGroups.isEmpty) continue;

            final group = matchingGroups.first;

            upcomingDeadlines.add(
              _StudentDeadline(
                title: task.title,
                subtitle: group.projectTitle,
                dueDate: task.dueDate,
                type: 'Task',
              ),
            );
          }
        }

        // Include milestones relevant to the student's groups.
        for (final milestone in data.milestones) {
          final belongsToStudent = milestone.groupID.any(
            (groupID) => studentGroupIDs.contains(groupID),
          );

          if (belongsToStudent &&
              milestone.dueDate.isAfter(DateTime.now()) &&
              milestone.status.toLowerCase() != 'completed') {
            final project = projectById[milestone.projectID];
            if (project == null) continue;

            upcomingDeadlines.add(
              _StudentDeadline(
                title: milestone.title,
                subtitle: project.title,
                dueDate: milestone.dueDate,
                type: 'Milestone',
              ),
            );
          }
        }

        upcomingDeadlines.sort(
          (a, b) => a.dueDate.compareTo(b.dueDate),
        );

        // Only use this student's own submission records.
        final studentSubmissions = data.submissions
            .where((submission) => submission.submittedBy == uid)
            .toList();

        // Find the latest submission that has Professor feedback.
        final submissionsWithFeedback = studentSubmissions
            .where((submission) =>
                submission.feedback != null &&
                submission.feedback!.trim().isNotEmpty)
            .toList()
          ..sort((a, b) {
            final dateA =
                a.reviewedAt ?? a.submittedAt ?? DateTime(2000);
            final dateB =
                b.reviewedAt ?? b.submittedAt ?? DateTime(2000);

            return dateB.compareTo(dateA);
          });

        final latestFeedback = submissionsWithFeedback.isEmpty
            ? null
            : submissionsWithFeedback.first;

        final taskTitles = {
          for (final task in data.tasks) task.id: task.title,
        };

        // Keep only announcements relevant to the student's projects/groups.
        final studentAnnouncements = data.announcements.where((announcement) {
          if (!studentProjectIDs.contains(announcement.projectID)) {
            return false;
          }

          if (announcement.targetType.toLowerCase() == 'project') {
            return true;
          }

          return announcement.groupID?.any(
                (groupID) => studentGroupIDs.contains(groupID),
              ) ??
              false;
        }).toList()
          ..sort((a, b) {
            final dateA = a.createdAt ?? DateTime(2000);
            final dateB = b.createdAt ?? DateTime(2000);

            return dateB.compareTo(dateA);
          });

        return PageBody(
          children: [
            ScreenHeading(
              eyebrow: _formatDate(now).toUpperCase(),
              title: 'Welcome back, ${_studentName()}.',
              detail: 'Here is your latest academic progress.',
            ),

            // Personal task progress.
            InfoCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MY TASK PROGRESS',
                          style: tinyCaps,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$completedTasks of ${assignedTasks.length} tasks complete',
                          style: titleStyle,
                        ),
                        const SizedBox(height: 9),
                        ProgressBar(value: taskProgress),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(taskProgress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            // Quick actions.
            Row(
              children: [
                Expanded(
                  child: QuickAction(
                    icon: Icons.description_outlined,
                    label: 'Activities',
                    onTap: () => widget.go(8),
                  ),
                ),
                Expanded(
                  child: QuickAction(
                    icon: Icons.add,
                    label: 'Submit update',
                    onTap: () => widget.go(8),
                  ),
                ),
                Expanded(
                  child: QuickAction(
                    icon: Icons.campaign_outlined,
                    label: 'Announcements',
                    onTap: () => widget.go(9),
                  ),
                ),
              ],
            ),

            // Upcoming deadlines.
            SectionHeading(
              'Upcoming',
              action: 'See all',
            ),

            if (upcomingDeadlines.isEmpty)
              const InfoCard(
                child: Text(
                  'You have no upcoming assigned deadlines.',
                  style: subStyle,
                ),
              )
            else
              ...upcomingDeadlines.take(3).map((deadline) {
                final daysLeft = _daysUntil(deadline.dueDate);

                final label = daysLeft == 0
                    ? 'DUE TODAY'
                    : daysLeft == 1
                        ? '1 DAY LEFT'
                        : '$daysLeft DAYS LEFT';

                return DeadlineCard(
                  day: deadline.dueDate.day.toString().padLeft(2, '0'),
                  label: label,
                  title: deadline.title,
                  subtitle: '${deadline.subtitle} · '
                      '${deadline.type} · '
                      '${_formatTime(deadline.dueDate)}',
                  urgent: daysLeft <= 3,
                );
              }),

            // Student groups and projects.
            SectionHeading(
              'My classes',
              action: 'View all',
            ),

            if (studentGroups.isEmpty)
              const InfoCard(
                child: Text(
                  'You are not currently assigned to a group.',
                  style: subStyle,
                ),
              )
            else
              ...studentGroups
                .where((group) => projectById.containsKey(group.projectID))
                .take(3)
                .map((group) {
              final project = projectById[group.projectID]!;

              final groupTasks = assignedTasks
                  .where((task) => task.groupID == group.id)
                  .toList();

              final groupCompletedTasks = groupTasks
                  .where((task) => task.status.toLowerCase() == 'completed')
                  .length;

              final groupProgress = groupTasks.isEmpty
                  ? 0.0
                  : groupCompletedTasks / groupTasks.length;

              return InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BadgeX(project.academicYear, dark: true),
                    const SizedBox(height: 6),
                    Text(project.title, style: titleStyle),
                    Text(group.groupName, style: subStyle),
                    const SizedBox(height: 10),
                    ProgressBar(value: groupProgress),
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'My task completion ${(groupProgress * 100).round()}%',
                        style: subStyle,
                      ),
                    ),
                  ],
                ),
              );
            }),
            // Recent announcements.
            SectionHeading(
              'Recent announcements',
              action: 'View feed',
            ),

            if (studentAnnouncements.isEmpty)
              const InfoCard(
                child: Text(
                  'There are no recent announcements.',
                  style: subStyle,
                ),
              )
            else
              ...studentAnnouncements.take(3).map((announcement) {
                return DataRowTile(
                  title: announcement.title,
                  subtitle: 'Professor · '
                      '${_formatRelativeDate(announcement.createdAt)}',
                  leading: '!',
                );
              }),

            // Latest Professor feedback.
            SectionHeading('Latest feedback'),

            if (latestFeedback == null)
              const InfoCard(
                child: Text(
                  'You do not have any reviewed submissions with feedback yet.',
                  style: subStyle,
                ),
              )
            else
              InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.rate_review_outlined,
                          size: 18,
                          color: ink,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            taskTitles[latestFeedback.taskID] ??
                                'Task submission',
                            style: titleStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      latestFeedback.status == 'revision_required'
                          ? 'Revision requested'
                          : latestFeedback.status == 'approved'
                              ? 'Submission approved'
                              : 'Submission feedback',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      latestFeedback.feedback!,
                      style: subStyle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatRelativeDate(latestFeedback.reviewedAt),
                      style: subStyle,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StudentDashboardData {
  final List<Project> projects;
  final List<Group> groups;
  final List<Task> tasks;
  final List<Milestone> milestones;
  final List<Submission> submissions;
  final List<Announcement> announcements;

  const _StudentDashboardData({
    required this.projects,
    required this.groups,
    required this.tasks,
    required this.milestones,
    required this.submissions,
    required this.announcements,
  });
}

class _StudentDeadline {
  final String title;
  final String subtitle;
  final DateTime dueDate;
  final String type;

  const _StudentDeadline({
    required this.title,
    required this.subtitle,
    required this.dueDate,
    required this.type,
  });
}