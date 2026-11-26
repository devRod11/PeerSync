import 'package:flutter/material.dart';

import '../core/a11y/app_a11y.dart';
import '../core/a11y/status_presentation.dart';
import '../core/utils/error_messages.dart';
import '../models/group.dart';
import '../models/milestone.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class ProfessorMilestonesPage extends StatefulWidget {
  const ProfessorMilestonesPage({super.key});

  @override
  State<ProfessorMilestonesPage> createState() =>
      _ProfessorMilestonesPageState();
}

class _ProfessorMilestonesPageState
    extends State<ProfessorMilestonesPage> {
  static const Color primaryColor = Color(0xFF0A2342);

  List<Project> _projects = [];
  List<Group> _groups = [];
  List<Milestone> _milestones = [];

  String? _selectedProjectID;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  Project? get _selectedProject {
    for (final project in _projects) {
      if (project.id == _selectedProjectID) return project;
    }
    return null;
  }

  int get _nextSequence {
    if (_milestones.isEmpty) return 1;

    return _milestones
            .map((milestone) => milestone.sequence)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  List<Group> get _projectGroups {
    return _groups
        .where((group) => group.projectID == _selectedProjectID)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        ApiService.getProjects(),
        ApiService.getGroups(),
      ]);

      if (!mounted) return;

      final projects = results[0] as List<Project>;
      final groups = results[1] as List<Group>;

      setState(() {
        _projects = projects;
        _groups = groups;
        _selectedProjectID =
            projects.isNotEmpty ? projects.first.id : null;
        _isLoading = false;
      });

      if (_selectedProjectID != null) {
        await _loadMilestones();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMilestones() async {
    if (_selectedProjectID == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final milestones = await ApiService.getMilestones(
        projectID: _selectedProjectID,
      );

      if (!mounted) return;

      setState(() {
        _milestones = milestones
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _selectProject(String? projectID) async {
    if (projectID == null || projectID == _selectedProjectID) return;

    setState(() {
      _selectedProjectID = projectID;
      _milestones = [];
    });

    await _loadMilestones();
  }

  Future<void> _showMilestoneDialog({
    Milestone? milestone,
  }) async {
    final project = _selectedProject;

    if (project == null) return;

    if (_projectGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create at least one group for this project first.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<MilestoneFormData>(
      context: context,
      builder: (_) => MilestoneFormDialog(
        project: project,
        groups: _projectGroups,
        milestone: milestone,
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _isSaving = true);

    try {
      if (milestone == null) {
        await ApiService.createMilestone(
          projectID: project.id,
          groupID: result.groupIDs,
          title: result.title,
          description: result.description,
          sequence: _nextSequence,
          startDate: result.startDate,
          dueDate: result.dueDate,
          status: result.status,
        );
      } else {
        await ApiService.updateMilestone(
          milestoneId: milestone.id,
          groupID: result.groupIDs,
          title: result.title,
          description: result.description,
          startDate: result.startDate,
          dueDate: result.dueDate,
          status: result.status,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            milestone == null
                ? 'Milestone created successfully.'
                : 'Milestone updated successfully.',
          ),
        ),
      );

      await _loadMilestones();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save milestone: ${friendlyErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _confirmDelete(Milestone milestone) async {
    if (_isSaving || _isLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete milestone?'),
        content: Text(
          'Are you sure you want to delete '
          '"${milestone.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);

    try {
      await ApiService.deleteMilestone(milestone.id);

      final remaining = _milestones
          .where((item) => item.id != milestone.id)
          .toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

      // Renumber the remaining milestones.
      for (int i = 0; i < remaining.length; i++) {
        if (remaining[i].sequence != i + 1) {
          await ApiService.updateMilestone(
            milestoneId: remaining[i].id,
            sequence: i + 1,
          );
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Milestone deleted and remaining sequences updated.',
          ),
        ),
      );

      await _loadMilestones();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to delete or reorder milestones: ${friendlyErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );

      await _loadMilestones();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _groupNames(List<String> groupIDs) {
    final names = _groups
        .where((group) => groupIDs.contains(group.id))
        .map((group) => group.groupName)
        .toList();

    return names.isEmpty ? 'Assigned groups' : names.join(', ');
  }

  String _formatDate(DateTime date) => AppA11y.formatDate(date);

  Widget _buildMilestoneCard(Milestone milestone, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  child: Text('${milestone.sequence}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        milestone.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Completion Order: ${milestone.sequence}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_isSaving && !_isLoading,
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showMilestoneDialog(milestone: milestone);
                    } else if (value == 'delete') {
                      _confirmDelete(milestone);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(milestone.description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.calendar_today, size: 15),
                  label: Text(
                    'Start: ${_formatDate(milestone.startDate)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.event, size: 15),
                  label: Text(
                    'Due: ${_formatDate(milestone.dueDate)}',
                  ),
                ),
                StatusChip(
                  presentation:
                      StatusPresentation.forMilestone(milestone.status),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.groups_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _groupNames(milestone.groupID),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FF),
      appBar: AppBar(
        title: const Text('Milestone Management'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading && _projects.isEmpty
          ? const LoadingView(message: 'Loading milestones\u2026')
          : _errorMessage != null && _projects.isEmpty
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadInitialData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'PROJECT MILESTONES',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Manage project milestones',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create and organize milestones for your project groups.',
                      ),
                      const SizedBox(height: 20),

                      if (_projects.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No projects found. Create a project first.',
                            ),
                          ),
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedProjectID,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Select project',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: _projects.map((project) {
                            return DropdownMenuItem(
                              value: project.id,
                              child: Text(
                                project.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: _selectProject,
                        ),
                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () => _showMilestoneDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Create Milestone'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Milestones (${_milestones.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _isLoading
                                  ? null
                                  : _loadMilestones,
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Refresh milestones',
                            ),
                          ],
                        ),

                        if (_isSaving || _isLoading)
                          const LinearProgressIndicator(),

                        if (_errorMessage != null)
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.danger),
                          )
                        else if (_milestones.isEmpty && !_isLoading)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  'No milestones have been created for this project.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          )
                        else
                          ..._milestones.asMap().entries.map((entry) {
                            return _buildMilestoneCard(
                              entry.value,
                              entry.key,
                            );
                          }),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.danger,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Unable to load milestone data.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadInitialData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// Data returned by the milestone form.
class MilestoneFormData {
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime dueDate;
  final String status;
  final List<String> groupIDs;

  const MilestoneFormData({
    required this.title,
    required this.description,
    required this.startDate,
    required this.dueDate,
    required this.status,
    required this.groupIDs,
  });
}

class MilestoneFormDialog extends StatefulWidget {
  final Project project;
  final List<Group> groups;
  final Milestone? milestone;

  const MilestoneFormDialog({
    super.key,
    required this.project,
    required this.groups,
    this.milestone,
  });

  @override
  State<MilestoneFormDialog> createState() =>
      _MilestoneFormDialogState();
}

class _MilestoneFormDialogState extends State<MilestoneFormDialog> {
  static const Color primaryColor = Color(0xFF0A2342);

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  late DateTime _startDate;
  late DateTime _dueDate;
  late String _status;
  late Set<String> _selectedGroupIDs;

  bool get _isEditing => widget.milestone != null;

  @override
  void initState() {
    super.initState();

    final milestone = widget.milestone;

    _titleController = TextEditingController(
      text: milestone?.title ?? '',
    );
    _descriptionController = TextEditingController(
      text: milestone?.description ?? '',
    );

    _startDate = milestone?.startDate ?? DateTime.now();
    _dueDate = milestone?.dueDate ??
        DateTime.now().add(const Duration(days: 7));
    _status = milestone?.status ?? 'pending';
    _selectedGroupIDs = milestone?.groupID.toSet() ?? {};
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final currentDate = isStart ? _startDate : _dueDate;

    final selected = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selected == null || !mounted) return;

    setState(() {
      if (isStart) {
        _startDate = selected;
        if (_dueDate.isBefore(_startDate)) {
          _dueDate = _startDate;
        }
      } else {
        _dueDate = selected;
      }
    });
  }

  String _formatDate(DateTime date) => AppA11y.formatDate(date);

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedGroupIDs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assign this milestone to at least one group.'),
        ),
      );
      return;
    }

    if (_startDate.isAfter(_dueDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date cannot be later than due date.'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      MilestoneFormData(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        startDate: _startDate,
        dueDate: _dueDate,
        status: _status,
        groupIDs: _selectedGroupIDs.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing ? 'Edit Milestone' : 'Create Milestone',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.project.title,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Milestone title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Description is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                const Text(
                  'Assign to groups',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),

                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderStrong),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: widget.groups.map((group) {
                      return CheckboxListTile(
                        dense: true,
                        value: _selectedGroupIDs.contains(group.id),
                        title: Text(group.groupName),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedGroupIDs.add(group.id);
                            } else {
                              _selectedGroupIDs.remove(group.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: true),
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Start: ${_formatDate(_startDate)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: false),
                  icon: const Icon(Icons.event),
                  label: Text('Due: ${_formatDate(_dueDate)}'),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Pending'),
                    ),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('In Progress'),
                    ),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completed'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _status = value);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
          ),
          onPressed: _submit,
          child: Text(_isEditing ? 'Save Changes' : 'Create'),
        ),
      ],
    );
  }
}