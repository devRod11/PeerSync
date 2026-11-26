import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';


import '../core/a11y/app_a11y.dart';
import '../core/a11y/status_presentation.dart';
import '../core/utils/error_messages.dart';
import '../models/authenticated_user.dart';
import '../models/group.dart';
import '../models/milestone.dart';
import '../models/project.dart';
import '../models/submission.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';


class ActivitiesPage extends StatefulWidget {
  final AuthenticatedUser user;

  const ActivitiesPage({
    super.key,
    required this.user,
  });

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  bool _isLoading = true;
  String? _errorMessage;

  List<Project> _projects = [];
  List<Group> _groups = [];
  List<Task> _tasks = [];
  final Map<String, List<Milestone>> _milestonesByGroup = {};
  final Map<String, List<Submission>> _submissionsByTask = {};

  bool get _isProfessor =>
      widget.user.role.trim().toLowerCase() == 'professor';

  bool _isLeader(Group group) => group.leaderID == widget.user.uid;

  bool get _isGroupLeader =>
      _groups.any((group) => _isLeader(group));

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final groups = await ApiService.getGroups();
      final projects = _isProfessor
          ? await ApiService.getProjects()
          : <Project>[];

      final milestoneResults = await Future.wait(
        groups.map((group) async {
          final milestones = await ApiService.getMilestones(
            projectID: group.projectID,
            groupID: group.id,
          );
          milestones.sort((a, b) => a.sequence.compareTo(b.sequence));
          return MapEntry(group.id, milestones);
        }),
      );

      final milestonesMap = Map<String, List<Milestone>>.fromEntries(
        milestoneResults,
      );

      final taskResults = _isProfessor
          ? await Future.wait(
              projects.map(
                (project) => ApiService.getTasks(
                  projectID: project.id,
                ),
              ),
            )
          : await Future.wait(
              groups.map(
                (group) => ApiService.getTasks(
                  groupID: group.id,
                ),
              ),
            );

      final taskMap = <String, Task>{};
      for (final result in taskResults) {
        for (final task in result) {
          taskMap[task.id] = task;
        }
      }

      final tasks = taskMap.values.toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

      // Retrieve individual submission records for Students only.
      // Professor submission monitoring and reviews are handled
      // in Progress Monitoring.
      final visibleSubmissions = _isProfessor
          ? <Submission>[]
          : (await ApiService.getSubmissions())
              .where(
                (submission) =>
                    submission.submittedBy == widget.user.uid,
              )
              .toList();

      // Organize submissions by task ID.
      final submissionsMap = <String, List<Submission>>{};

      for (final submission in visibleSubmissions) {
        submissionsMap
            .putIfAbsent(submission.taskID, () => [])
            .add(submission);
      }

      // Sort each task's submissions from newest to oldest.
      for (final submissions in submissionsMap.values) {
        submissions.sort((a, b) {
          final dateA =
              a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB =
              b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

          return dateB.compareTo(dateA);
        });
      }  
      if (!mounted) return;

      setState(() {
        _projects = projects;
        _groups = groups;

        _milestonesByGroup
          ..clear()
          ..addAll(milestonesMap);

        _submissionsByTask
          ..clear()
          ..addAll(submissionsMap);

        _tasks = tasks;
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

  String _formatDate(DateTime date) => AppA11y.formatDate(date);


  Widget _statusBadge(String status) {
    // Status is conveyed by an icon plus a text label, never by color alone.
    return StatusChip(presentation: StatusPresentation.forTask(status));
  }

  Group? _findGroup(String groupID) {
    for (final group in _groups) {
      if (group.id == groupID) return group;
    }
    return null;
  }

  Project? _findProject(String projectID) {
    for (final project in _projects) {
      if (project.id == projectID) return project;
    }
    return null;
  }

  Milestone? _findMilestone(String groupID, String milestoneID) {
    final milestones = _milestonesByGroup[groupID] ?? [];
    for (final milestone in milestones) {
      if (milestone.id == milestoneID) return milestone;
    }
    return null;
  }

  Submission? _getLatestSubmission(String taskID) {
    final submissions = _submissionsByTask[taskID];

    if (submissions == null || submissions.isEmpty) {
      return null;
    }

    // The list is already sorted newest first.
    return submissions.first;
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete task?',
      message: 'Are you sure you want to delete "${task.title}"? '
          'This action cannot be undone.',
    );

    if (!confirmed) return;

    try {
      await ApiService.deleteTask(task.id);
      if (!mounted) return;

      setState(() {
        _tasks.removeWhere((item) => item.id == task.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete task: $error')),
      );
    }
  }

  Future<void> _openSubmissionDialog(Task task) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _SubmissionDialog(
        task: task,
        user: widget.user,
      );
    },
  );

  if (result == true) {
    await _loadActivities();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Submission recorded successfully.'),
      ),
    );
  }
}

  Future<void> _openTaskForm({Task? existingTask}) async {
  final editableGroups = _isProfessor
      ? _groups
      : _groups.where(_isLeader).toList();

  if (editableGroups.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No group is available for task management.'),
      ),
    );
    return;
  }

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _TaskFormDialog(
        isProfessor: _isProfessor,
        projects: _projects,
        groups: editableGroups,
        milestonesByGroup: _milestonesByGroup,
        existingTask: existingTask,
      );
    },
  );

  if (result == true) {
    await _loadActivities();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingTask == null
              ? 'Task created successfully.'
              : 'Task updated successfully.',
        ),
      ),
    );
  }
}

bool _canSubmitTask(Task task) {
  final submission = _getLatestSubmission(task.id);

  if (submission == null) {
    return true;
  }

  final status = submission.status.toLowerCase();

  return status == 'revision_required';
}

Widget _buildSubmissionStatus(Task task) {
  final submission = _getLatestSubmission(task.id);

  if (submission == null) {
    return const StatusChip(
      presentation: StatusPresentation(
        label: 'Not submitted',
        icon: Icons.upload_file_outlined,
        tone: StatusTone.neutral,
      ),
      prefix: 'My submission',
    );
  }

  return StatusChip(
    presentation: StatusPresentation.forSubmission(submission.status),
    prefix: 'My submission',
  );
}

Widget _buildSubmissionDetails(Task task) {
  final submission = _getLatestSubmission(task.id);

  if (submission == null) {
    return const SizedBox.shrink();
  }

  final submittedAt = submission.submittedAt;
  final reviewedAt = submission.reviewedAt;

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LATEST SUBMISSION',
          style: titleStyle,
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
                '${submission.fileName} '
                '(${submission.fileType})',
                style: subStyle,
              ),
            ),
          ],
        ),

        if (submittedAt != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Submitted: ${_formatDate(submittedAt)}',
                  style: subStyle,
                ),
              ),
            ],
          ),
        ],

        if (reviewedAt != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.event_available, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reviewed: ${_formatDate(reviewedAt)}',
                  style: subStyle,
                ),
              ),
            ],
          ),
        ],

        if (submission.feedback != null &&
            submission.feedback!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(),
          const Text(
            'PROFESSOR FEEDBACK',
            style: titleStyle,
          ),
          const SizedBox(height: 6),
          Text(
            submission.feedback!,
            style: subStyle,
          ),
        ],
      ],
    ),
  );
}

  Widget _buildTaskCard(Task task) {
    final group = _findGroup(task.groupID);
    final project = _findProject(task.projectID);
    final milestone = _findMilestone(task.groupID, task.milestoneID);

    final isLeaderForTask =
        group != null && _isLeader(group);

    final canEdit = isLeaderForTask && !_isProfessor;
    final canDelete = canEdit && task.createdBy == widget.user.uid;


    final isOverdue = task.dueDate.isBefore(DateTime.now()) &&
        task.status.toLowerCase() != 'completed';

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(task.title, style: titleStyle),
              ),
              _statusBadge(task.status),
              if (canEdit || canDelete)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'edit') {
                      _openTaskForm(existingTask: task);
                    } else if (value == 'delete') {
                      _deleteTask(task);
                    }
                  },
                  itemBuilder: (context) => [
                    if (canEdit)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit task'),
                      ),
                    if (canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete task'),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${project?.title ?? group?.projectTitle ?? 'Project'} · '
            '${group?.groupName ?? 'Group'}',
            style: subStyle,
          ),
          if (milestone != null) ...[
            const SizedBox(height: 4),
            Text('Milestone: ${milestone.title}', style: subStyle),
          ],
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.description, style: subStyle),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              BadgeX('PRIORITY: ${task.priority}'),
              BadgeX(
                isOverdue ? 'OVERDUE' : 'DUE ${_formatDate(task.dueDate)}',
                danger: isOverdue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Assigned to ${task.assignedTo.length} student(s)',
            style: subStyle,
          ),

          // Display the authenticated student's individual submission status.
          if (!_isProfessor &&
            task.assignedTo.contains(widget.user.uid)) ...[
          const SizedBox(height: 10),
          _buildSubmissionStatus(task),
          _buildSubmissionDetails(task),

          const SizedBox(height: 10),

          if (_canSubmitTask(task))
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openSubmissionDialog(task),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  _getLatestSubmission(task.id) == null
                      ? 'Submit Task'
                      : 'Submit Revised Work',
                ),
              ),
            )
          else
            Text(
              _getLatestSubmission(task.id)?.status.toLowerCase() == 'pending'
                  ? 'Your submission is awaiting Professor review.'
                  : 'Your submission has been approved.',
              style: subStyle,
            ),
        ],
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    if (_tasks.isEmpty) {
      return const InfoCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 15),
          child: Column(
            children: [
              Icon(Icons.assignment_outlined, size: 34, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text('No tasks found', style: titleStyle),
              SizedBox(height: 5),
              Text(
                'Tasks will appear here when they are created or assigned.',
                textAlign: TextAlign.center,
                style: subStyle,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _tasks.map(_buildTaskCard).toList(),
    );
  }

  Widget _buildStudentMilestones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _groups.map((group) {
        final milestones = _milestonesByGroup[group.id] ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(group.projectTitle, style: titleStyle),
            const SizedBox(height: 4),
            Text(group.groupName, style: subStyle),
            const SizedBox(height: 8),
            if (milestones.isEmpty)
              const InfoCard(
                child: Text(
                  'No milestones have been assigned to this group yet.',
                  style: subStyle,
                ),
              )
            else
              ...milestones.map((milestone) {
                final normalized =
                    milestone.status.toLowerCase().replaceAll(' ', '_');

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
                          StatusChip(
                            presentation:
                                StatusPresentation.forMilestone(normalized),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(milestone.title, style: titleStyle),
                      if (milestone.description.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(milestone.description, style: subStyle),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'Start: ${_formatDate(milestone.startDate)}',
                        style: subStyle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Due: ${_formatDate(milestone.dueDate)}',
                        style: subStyle,
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 10),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildLoadingOrError() {
    if (_isLoading) {
      return const LoadingView(message: 'Loading activities…');
    }

    if (_errorMessage != null) {
      return ErrorStateView(
        message: _errorMessage!,
        onRetry: _loadActivities,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final canCreateTasks = _isProfessor ? false : _isGroupLeader;

    return PageBody(
      children: [
        ScreenHeading(
          title: 'Activities',
          detail: _isProfessor
              ? 'Monitor tasks across your projects and groups.'
              : _isGroupLeader
                  ? 'Manage group tasks and monitor project milestones.'
                  : 'View your assigned tasks and project milestones.',
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _isProfessor
                    ? 'Professor view'
                    : _isGroupLeader
                        ? 'Group Leader view'
                        : 'Student view',
                style: tinyCaps,
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _isLoading ? null : _loadActivities,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        if (canCreateTasks)
          PrimaryButton(
            label: '＋ Create group task',
            onPressed: () => _openTaskForm(),
          ),
        if (_isProfessor || _isGroupLeader)
          const SectionHeading('Task monitoring'),
        if (!_isProfessor && !_isGroupLeader)
          const SectionHeading('My assigned tasks'),
        if (_isLoading || _errorMessage != null)
          _buildLoadingOrError()
        else
          _buildTaskList(),
        if (!_isProfessor) ...[
          const SectionHeading('Project milestones'),
          if (_isLoading || _errorMessage != null)
            const SizedBox.shrink()
          else if (_groups.isEmpty)
            const InfoCard(
              child: Text(
                'You are not currently assigned to a project group.',
                style: subStyle,
              ),
            )
          else
            _buildStudentMilestones(),
        ],
        if (_isProfessor && _projects.isEmpty && !_isLoading)
          const InfoCard(
            child: Text(
              'No projects are currently available to monitor.',
              style: subStyle,
            ),
          ),
        if (!_isProfessor && !_isGroupLeader && !_isLoading)
          const InfoCard(
            child: Text(
              'Only the Group Leader can create and manage group tasks.',
              style: subStyle,
            ),
          ),
      ],
    );
  }
}


class _SubmissionDialog extends StatefulWidget {
  final Task task;
  final AuthenticatedUser user;

  const _SubmissionDialog({
    required this.task,
    required this.user,
  });

  @override
  State<_SubmissionDialog> createState() =>
      _SubmissionDialogState();
}


class _SubmissionDialogState extends State<_SubmissionDialog> {
  file_picker.PlatformFile? selectedFile;
  bool isSaving = false;

  static const int maxFileSize = 25 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'ppt',
    'pptx',
    'xls',
    'xlsx',
    'txt',
    'csv',
    'zip',
  ];

  Future<void> _pickFile() async {
    try {
      final result = await file_picker.FilePicker.pickFiles(
        type: file_picker.FileType.custom,
        allowedExtensions: allowedExtensions,
      );

      if (result.isEmpty) return;

      final file = result.single;
      final fileSize = await file.length();

      if (fileSize == null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to determine the selected file size.'),
          ),
        );
        return;
      }

      if (fileSize > maxFileSize) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File size exceeds the 25 MB upload limit.'),
          ),
        );
        return;
      }

      setState(() {
        selectedFile = file;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to select file: $e'),
        ),
      );
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'File size unavailable';
    if (bytes < 1024) return '$bytes B';

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _submit() async {
    final file = selectedFile;

    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file first.'),
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final fileBytes = await file.readAsBytes();

      await ApiService.uploadSubmission(
        projectID: widget.task.projectID,
        groupID: widget.task.groupID,
        taskID: widget.task.id,
        fileName: file.name,
        fileBytes: fileBytes,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to upload submission: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Submit Task'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Task: ${widget.task.title}',
              style: titleStyle,
            ),

            const SizedBox(height: 12),

            const Text(
              'Select the document you want to submit. '
              'Supported formats include PDF, Word, PowerPoint, '
              'Excel, TXT, CSV, and ZIP.',
              style: subStyle,
            ),

            const SizedBox(height: 18),

            OutlinedButton.icon(
              onPressed: isSaving ? null : _pickFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choose File'),
            ),

            const SizedBox(height: 12),

            if (selectedFile != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.insert_drive_file_outlined,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedFile!.name,
                            style: titleStyle,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatFileSize(selectedFile!.lengthSync()),
                            style: subStyle,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove selected file',
                      onPressed: isSaving
                          ? null
                          : () {
                              setState(() {
                                selectedFile = null;
                              });
                            },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            const Text(
              'Maximum file size: 25 MB',
              style: subStyle,
            ),

            if (isSaving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Uploading your submission...',
                style: subStyle,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: isSaving || selectedFile == null
              ? null
              : _submit,
          icon: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(
            isSaving ? 'Uploading...' : 'Upload Submission',
          ),
        ),
      ],
    );
  }
}

class _TaskFormDialog extends StatefulWidget {
  final bool isProfessor;
  final List<Project> projects;
  final List<Group> groups;
  final Map<String, List<Milestone>> milestonesByGroup;
  final Task? existingTask;

  const _TaskFormDialog({
    required this.isProfessor,
    required this.projects,
    required this.groups,
    required this.milestonesByGroup,
    this.existingTask,
  });

  @override
  State<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<_TaskFormDialog> {
  late final TextEditingController titleController;
  late final TextEditingController descriptionController;

  late String? selectedProjectID;
  late String? selectedGroupID;
  late String? selectedMilestoneID;
  late DateTime selectedDueDate;
  late String selectedPriority;

  final Set<String> selectedStudents = {};
  bool isSaving = false;

  Task? get existingTask => widget.existingTask;

  @override
  void initState() {
    super.initState();

    titleController = TextEditingController(
      text: existingTask?.title ?? '',
    );

    descriptionController = TextEditingController(
      text: existingTask?.description ?? '',
    );

    final initialGroup = existingTask == null
        ? widget.groups.first
        : widget.groups.firstWhere(
            (group) => group.id == existingTask!.groupID,
            orElse: () => widget.groups.first,
          );

    selectedProjectID = initialGroup.projectID;
    selectedGroupID = initialGroup.id;

    final milestones =
        widget.milestonesByGroup[initialGroup.id] ?? [];

    selectedMilestoneID = existingTask?.milestoneID;

    if (selectedMilestoneID == null ||
        !milestones.any((m) => m.id == selectedMilestoneID)) {
      selectedMilestoneID =
          milestones.isNotEmpty ? milestones.first.id : null;
    }

    selectedDueDate = existingTask?.dueDate ??
        DateTime.now().add(const Duration(days: 7));

    selectedPriority = existingTask?.priority ?? 'Medium';

    selectedStudents.addAll(existingTask?.assignedTo ?? []);
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  T? _firstWhereOrNull<T>(
    Iterable<T> items,
    bool Function(T) test,
  ) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  String _formatDate(DateTime date) => AppA11y.formatDate(date);

  Future<void> _selectDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDueDate,
      firstDate: DateTime.now().subtract(
        const Duration(days: 365),
      ),
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ),
    );

    if (!mounted || date == null) return;

    setState(() {
      selectedDueDate = DateTime(
        date.year,
        date.month,
        date.day,
        23,
        59,
      );
    });
  }

  Future<void> _saveTask() async {
    final title = titleController.text.trim();
    final description = descriptionController.text.trim();

    if (title.isEmpty ||
        description.isEmpty ||
        selectedProjectID == null ||
        selectedGroupID == null ||
        selectedMilestoneID == null ||
        selectedStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete all fields and assign at least one student.',
          ),
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      if (existingTask == null) {
        await ApiService.createTask(
          projectID: selectedProjectID!,
          groupID: selectedGroupID!,
          milestoneID: selectedMilestoneID!,
          assignedTo: selectedStudents.toList(),
          title: title,
          description: description,
          dueDate: selectedDueDate,
          priority: selectedPriority,
        );
      } else {
        await ApiService.updateTask(
          taskId: existingTask!.id,
          assignedTo: selectedStudents.toList(),
          title: title,
          description: description,
          dueDate: selectedDueDate,
          priority: selectedPriority,
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save task: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableProjects = widget.projects;

    final availableGroups = widget.groups
        .where((g) => g.projectID == selectedProjectID)
        .toList();

    final currentGroup = _firstWhereOrNull(
      availableGroups,
      (g) => g.id == selectedGroupID,
    );

    final availableMilestones = currentGroup == null
        ? <Milestone>[]
        : (widget.milestonesByGroup[currentGroup.id] ?? []);

    if (availableMilestones.isNotEmpty &&
        !availableMilestones.any(
          (m) => m.id == selectedMilestoneID,
        )) {
      selectedMilestoneID = availableMilestones.first.id;
    }

    final members = currentGroup?.members ?? <GroupMember>[];

    return AlertDialog(
      title: Text(
        existingTask == null ? 'Create task' : 'Edit task',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isProfessor) ...[
                const FieldLabel('Project'),
                DropdownButtonFormField<String>(
                  initialValue: selectedProjectID,
                  isExpanded: true,
                  items: availableProjects.map((project) {
                    return DropdownMenuItem(
                      value: project.id,
                      child: Text(
                        project.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: existingTask != null
                      ? null
                      : (value) {
                          setState(() {
                            selectedProjectID = value;

                            final firstGroup = _firstWhereOrNull(
                              widget.groups,
                              (g) => g.projectID == value,
                            );

                            selectedGroupID = firstGroup?.id;

                            final milestones = firstGroup == null
                                ? <Milestone>[]
                                : (widget.milestonesByGroup[
                                        firstGroup.id] ??
                                    []);

                            selectedMilestoneID = milestones.isEmpty
                                ? null
                                : milestones.first.id;

                            selectedStudents.clear();
                          });
                        },
                ),
              ] else ...[
                const FieldLabel('Project'),
                Text(
                  currentGroup?.projectTitle ??
                      widget.groups.first.projectTitle,
                  style: titleStyle,
                ),
              ],

              const FieldLabel('Group'),
              DropdownButtonFormField<String>(
                initialValue: selectedGroupID,
                isExpanded: true,
                items: availableGroups.map((group) {
                  return DropdownMenuItem(
                    value: group.id,
                    child: Text(group.groupName),
                  );
                }).toList(),
                onChanged: existingTask != null
                    ? null
                    : (value) {
                        setState(() {
                          selectedGroupID = value;

                          final milestones =
                              widget.milestonesByGroup[value] ?? [];

                          selectedMilestoneID = milestones.isEmpty
                              ? null
                              : milestones.first.id;

                          selectedStudents.clear();
                        });
                      },
              ),

              const FieldLabel('Milestone'),
              DropdownButtonFormField<String>(
                initialValue: selectedMilestoneID,
                isExpanded: true,
                items: availableMilestones.map((milestone) {
                  return DropdownMenuItem(
                    value: milestone.id,
                    child: Text(
                      milestone.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedMilestoneID = value;
                  });
                },
              ),

              const FieldLabel('Task title'),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  hintText: 'Enter task title',
                ),
              ),

              const FieldLabel('Instructions'),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describe the task and requirements',
                ),
              ),

              const FieldLabel('Assign to group members'),
              if (members.isEmpty)
                const Text(
                  'No group members were found.',
                  style: subStyle,
                )
              else
                ...members.map((member) {
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity:
                        ListTileControlAffinity.leading,
                    title: Text(
                      member.displayName,
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      member.email,
                      style: subStyle,
                    ),
                    value: selectedStudents.contains(
                      member.studentID,
                    ),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          selectedStudents.add(member.studentID);
                        } else {
                          selectedStudents.remove(member.studentID);
                        }
                      });
                    },
                  );
                }),

              const FieldLabel('Priority'),
              DropdownButtonFormField<String>(
                initialValue: selectedPriority,
                items: const [
                  DropdownMenuItem(
                    value: 'Low',
                    child: Text('Low'),
                  ),
                  DropdownMenuItem(
                    value: 'Medium',
                    child: Text('Medium'),
                  ), 
                  DropdownMenuItem(
                    value: 'High',
                    child: Text('High'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedPriority = value;
                    });
                  }
                },
              ),

              const FieldLabel('Due date'),
              OutlinedButton.icon(
                onPressed: isSaving ? null : _selectDueDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_formatDate(selectedDueDate)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: isSaving ? null : _saveTask,
          child: isSaving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  existingTask == null
                      ? 'Create task'
                      : 'Save changes',
                ),
        ),
      ],
    );
  }
}