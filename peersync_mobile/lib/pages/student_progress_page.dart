import 'package:flutter/material.dart';
import '../models/group.dart';
import '../models/milestone.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';

class StudentProgressPage extends StatefulWidget {
  const StudentProgressPage({super.key});

  @override
  State<StudentProgressPage> createState() => _StudentProgressPageState();
}

class _StudentProgressPageState extends State<StudentProgressPage> {
  late Future<List<_GroupMilestoneSection>> _milestonesFuture;

  @override
  void initState() {
    super.initState();
    _milestonesFuture = _loadStudentMilestones();
  }

  // Retrieve the student's groups and their assigned milestones.
  Future<List<_GroupMilestoneSection>> _loadStudentMilestones() async {
    final groups = await ApiService.getGroups();

    if (groups.isEmpty) {
      return [];
    }

    final sections = await Future.wait(
      groups.map((group) async {
        final milestones = await ApiService.getMilestones(
          projectID: group.projectID,
          groupID: group.id,
        );

        milestones.sort(
          (a, b) => a.sequence.compareTo(b.sequence),
        );

        return _GroupMilestoneSection(
          group: group,
          milestones: milestones,
        );
      }),
    );

    return sections;
  }

  // Format dates without requiring an additional package.
  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  // Display the milestone status returned by the backend.
  Widget _buildStatusBadge(String status) {
    final normalizedStatus = status.toLowerCase().replaceAll(' ', '_');

    final label = normalizedStatus
        .replaceAll('_', ' ')
        .toUpperCase();

    return BadgeX(
      label,
      dark: normalizedStatus == 'in_progress',
      danger: normalizedStatus == 'overdue',
    );
  }

  Widget _buildMilestoneCard(Milestone milestone) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MILESTONE ${milestone.sequence}',
                style: tinyCaps,
              ),
              const Spacer(),
              _buildStatusBadge(milestone.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            milestone.title,
            style: titleStyle,
          ),
          if (milestone.description.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              milestone.description,
              style: subStyle,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Start: ${_formatDate(milestone.startDate)}',
                  style: subStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(
                Icons.event_outlined,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Due: ${_formatDate(milestone.dueDate)}',
                  style: subStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMilestonesContent() {
    return FutureBuilder<List<_GroupMilestoneSection>>(
      future: _milestonesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const InfoCard(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Unable to load milestones',
                      style: titleStyle,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: subStyle,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _milestonesFuture = _loadStudentMilestones();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ),
              ],
            ),
          );
        }

        final sections = snapshot.data ?? [];

        if (sections.isEmpty) {
          return const InfoCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 36,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No group assignments found',
                    style: titleStyle,
                  ),
                  SizedBox(height: 5),
                  Text(
                    'You are not currently assigned to a project group.',
                    style: subStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sections.map((section) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  section.group.projectTitle,
                  style: titleStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  section.group.groupName,
                  style: subStyle,
                ),
                const SizedBox(height: 12),

                if (section.milestones.isEmpty)
                  const InfoCard(
                    child: Text(
                      'No milestones have been assigned to this group yet.',
                      style: subStyle,
                    ),
                  )
                else
                  ...section.milestones.map(
                    _buildMilestoneCard,
                  ),

                const SizedBox(height: 12),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const ScreenHeading(
          title: 'My progress',
          detail: 'View milestones assigned to your groups',
        ),

        const SectionHeading('Project milestones'),

        _buildMilestonesContent(),

        // Existing progress submission section retained.
        const SectionHeading('Submit progress update'),
        const FieldLabel('Activity'),
        const DropdownField(
          items: [
            'Requirements Analysis',
            'Research Instruments',
            'Chapter 2 Draft',
          ],
        ),
        const FieldLabel('What did you accomplish?'),
        const TextField(
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Share your progress, blockers, or questions…',
          ),
        ),
        const AttachmentTile(label: 'Attach a file'),
        PrimaryButton(
          label: 'Submit progress',
          onPressed: () {},
        ),

        // Existing submission history retained.
        const SectionHeading('Submission history'),
        const DataRowTile(
          title: 'Chapter 1 Draft',
          subtitle: 'Submitted Oct 08 · Reviewed',
          leading: '✓',
          trailing: 'Completed',
        ),
        const InfoCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              child: Text('MD'),
            ),
            title: Text(
              'Professor feedback',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '“Clarify the scope in section 2. Good progress overall.”\n'
              'Oct 09 · Chapter 1 Draft',
              style: subStyle,
            ),
          ),
        ),
      ],
    );
  }
}

// Holds the milestones belonging to one student group.
class _GroupMilestoneSection {
  final Group group;
  final List<Milestone> milestones;

  const _GroupMilestoneSection({
    required this.group,
    required this.milestones,
  });
}