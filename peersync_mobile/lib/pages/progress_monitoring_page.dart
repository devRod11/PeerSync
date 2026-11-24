import 'package:flutter/material.dart';

import '../core/a11y/app_a11y.dart';
import '../core/a11y/status_presentation.dart';
import '../core/utils/error_messages.dart';
import '../models/group.dart';
import '../models/project.dart';
import '../models/submission.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class ProgressMonitoring extends StatefulWidget {
  const ProgressMonitoring({super.key});
  @override State<ProgressMonitoring> createState() => _ProgressMonitoringState();
}

class _ProgressMonitoringState extends State<ProgressMonitoring> {
  String tab = 'Students';

  bool _isLoadingSubmissions = true;
  String? _submissionError;

  List<Group> _groups = [];
  List<Task> _tasks = [];
  List<Submission> _submissions = [];

  @override
  void initState() {
    super.initState();
    _loadReviewData();
  }
  

  Future<void> _loadReviewData() async {
    setState(() {
      _isLoadingSubmissions = true;
      _submissionError = null;
    });
    

    try {
      final results = await Future.wait([
        ApiService.getGroups(),
        ApiService.getProjects(),
        ApiService.getSubmissions(),
      ]);

      final groups = results[0] as List<Group>;
      final projects = results[1] as List<Project>;
      final submissions = results[2] as List<Submission>;

      final taskResults = await Future.wait(
        projects.map(
          (project) => ApiService.getTasks(
            projectID: project.id,
          ),
        ),
      );

      final taskMap = <String, Task>{};

      for (final taskList in taskResults) {
        for (final task in taskList) {
          taskMap[task.id] = task;
        }
      }

      submissions.sort((a, b) {
        final dateA =
            a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB =
            b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

        return dateB.compareTo(dateA);
      });

      if (!mounted) return;

      setState(() {
        _groups = groups;
        _tasks = taskMap.values.toList();
        _submissions = submissions;
        _isLoadingSubmissions = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _submissionError = friendlyErrorMessage(error);
        _isLoadingSubmissions = false;
      });
    }
  }

  Group? _findSubmissionGroup(String groupID) {
    for (final group in _groups) {
      if (group.id == groupID) return group;
    }

    return null;
  }

  Task? _findSubmissionTask(String taskID) {
    for (final task in _tasks) {
      if (task.id == taskID) return task;
    }

    return null;
  }

  GroupMember? _findSubmissionStudent(
    String groupID,
    String studentID,
  ) {
    final group = _findSubmissionGroup(groupID);

    if (group == null) return null;

    for (final member in group.members) {
      if (member.studentID == studentID) {
        return member;
      }
    }

    return null;
  }

  String _formatSubmissionDate(DateTime? date) =>
      AppA11y.formatDate(date);

  Widget _buildSubmissionQueue() {
    if (_isLoadingSubmissions) {
      return const LoadingView(message: 'Loading submissions\u2026');
    }

    if (_submissionError != null) {
      return InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unable to load submissions',
              style: titleStyle,
            ),
            const SizedBox(height: 6),
            Text(_submissionError!, style: subStyle),
            TextButton.icon(
              onPressed: _loadReviewData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_submissions.isEmpty) {
      return const InfoCard(
        child: Text(
          'No student submissions have been received yet.',
          style: subStyle,
        ),
      );
    }

    return Column(
      children: _submissions.map((submission) {
        final group = _findSubmissionGroup(submission.groupID);

        final student = _findSubmissionStudent(
          submission.groupID,
          submission.submittedBy,
        );

        final task = _findSubmissionTask(submission.taskID);

        final status = submission.status.toLowerCase();

        return InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student?.displayName ?? 'Unknown student',
                          style: titleStyle,
                        ),
                        Text(
                          student?.email ?? 'Student information unavailable',
                          style: subStyle,
                        ),
                      ],
                    ),
                  ),
                  StatusChip(
                    presentation: StatusPresentation.forSubmission(status),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                'Group: ${group?.groupName ?? 'Unknown group'}',
                style: subStyle,
              ),

              const SizedBox(height: 4),

              Text(
                'Task: ${task?.title ?? 'Unknown task'}',
                style: subStyle,
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${submission.fileName} (${submission.fileType})',
                      style: subStyle,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              Text(
                'Submitted: ${_formatSubmissionDate(submission.submittedAt)}',
                style: subStyle,
              ),      
              if (submission.feedback != null &&
                  submission.feedback!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(),
                const Text(
                  'FEEDBACK',
                  style: titleStyle,
                ),
                const SizedBox(height: 5),
                Text(submission.feedback!, style: subStyle),
              ],

              if (status == 'pending') ...[
                const SizedBox(height: 14),
                // One full-width action. The previous layout split the row in
                // two, which forced "Review / Request Revision" to wrap and
                // clip inside a fixed-height button - and both halves opened
                // the same dialog anyway.
                PrimaryButton(
                  label: 'Review submission',
                  onPressed: () => _reviewSubmission(submission),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _reviewSubmission(Submission submission) async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => const _SubmissionReviewDialog(),
    );

    if (result == null || !mounted) return;

    try {
      await ApiService.reviewSubmission(
        submissionId: submission.id,
        status: result['status']!,
        feedback: result['feedback'],
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['status'] == 'approved'
                ? 'Submission approved successfully.'
                : 'Revision requested successfully.',
          ),
        ),
      );

      await _loadReviewData();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to review submission: $error'),
        ),
      );
    }
  }


  @override Widget build(BuildContext context) => PageBody(children: [
    const ScreenHeading(eyebrow: 'Progress Monitoring', title: 'Student Submissions', detail:'Track individual and group milestones.'),
      Row(
        children: [
          Expanded(
            child: Text(
              '${_submissions.length} submission(s) received',
              style: subStyle,
            ),
          ),
          IconButton(
            tooltip: 'Refresh submissions',
            onPressed: _isLoadingSubmissions
                ? null
                : _loadReviewData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      _buildSubmissionQueue(),
      /*
    InfoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(backgroundColor: const Color(0xFFDCE5F2), child: Text(tab == 'Students' ? 'AR' : 'TO', style: const TextStyle(color: ink))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tab == 'Students' ? 'Ana Marie Reyes' : 'Team Orbit', style: titleStyle), Text(tab == 'Students' ? 'Team Orbit · 2021-01482' : '5 members · Capstone Project', style: subStyle)])), const Icon(Icons.chevron_right)]),
      const SizedBox(height: 14), const MetricsRow(items: [('07','Completed'),('02','Pending'),('01','Overdue')]),
      const SizedBox(height: 10), const ProgressBar(value: .72), const Align(alignment: Alignment.centerRight, child: Text('Overall progress  72%', style: subStyle)),
    ])),
    const SectionHeading('Milestone timeline', action: 'View report'),
    const TimelineEntry('Topic approval', 'Completed · Sep 12', state: 'done', tag: 'Reviewed'),
    const TimelineEntry('Requirements analysis', 'In progress · Due Oct 17', state: 'active', tag: '72%'),
    const TimelineEntry('Research instruments', 'Overdue by 2 days', state: 'late', tag: 'Overdue'),
    const TimelineEntry('Prototype build', 'Not started · Due Nov 04'),
    const SectionHeading('Latest progress update'),
    const InfoCard(child: ListTile(contentPadding: EdgeInsets.zero, title: Text('“We completed the user interview guide…”', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)), subtitle: Text('Updated today, 9:42 AM · 1 attachment', style: subStyle), trailing: Icon(Icons.attach_file))),
    const FieldLabel('Professor feedback'),
    const TextField(maxLines: 3, decoration: InputDecoration(hintText: 'Add comments or recommendations…')),
    // Review actions live in the submission review sheet. */
  ]); 
}

class _SubmissionReviewDialog extends StatefulWidget {
  const _SubmissionReviewDialog();

  @override
  State<_SubmissionReviewDialog> createState() =>
      _SubmissionReviewDialogState();
}

class _SubmissionReviewDialogState
    extends State<_SubmissionReviewDialog> {
  final TextEditingController _feedbackController =
      TextEditingController();

  String? _errorMessage;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  void _submitReview(String status) {
    final feedback = _feedbackController.text.trim();

    if (status == 'revision_required' && feedback.isEmpty) {
      setState(() {
        _errorMessage =
            'Feedback is required when requesting a revision.';
      });
      return;
    }

    Navigator.pop(
      context,
      <String, String?>{
        'status': status,
        'feedback': feedback.isEmpty ? null : feedback,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review Student Submission'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add feedback for the student. Feedback is optional '
              'when approving and required when requesting a revision.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _feedbackController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Professor Feedback',
                hintText: 'Enter comments or required corrections...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _submitReview('revision_required'),
          child: const Text('Request Revision'),
        ),
        ElevatedButton(
          onPressed: () => _submitReview('approved'),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
