import 'package:flutter/material.dart';

import '../core/utils/error_messages.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';
import 'group_management_page.dart';
import 'professor_milestones_page.dart';

class ClassManagement extends StatefulWidget {
  const ClassManagement({super.key});

  @override
  State<ClassManagement> createState() => _ClassManagementState();
}

class _ClassManagementState extends State<ClassManagement> {
  List<Project> _projects = [];

  bool _isLoading = true;
  bool _isSaving = false;

  String _searchQuery = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  // Retrieve projects from FastAPI.
  Future<void> _loadProjects() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final projects = await ApiService.getProjects();

      if (!mounted) return;

      setState(() {
        _projects = projects;
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

  // Filter projects based on the search field.
  List<Project> get _filteredProjects {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _projects;
    }

    return _projects.where((project) {
      return project.title.toLowerCase().contains(query) ||
          project.description.toLowerCase().contains(query) ||
          project.academicYear.toLowerCase().contains(query) ||
          project.status.toLowerCase().contains(query);
    }).toList();
  }

  // Create or edit a project.
  Future<void> _showProjectDialog({Project? project}) async {
    final formData = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return ProjectFormDialog(project: project);
      },
    );

    if (formData == null || !mounted) return;

    await _saveProject(formData, project: project);
  }

  // Send project data to FastAPI.
  Future<void> _saveProject(
    Map<String, String> data, {
    Project? project,
  }) async {
    setState(() {
      _isSaving = true;
    });

    try {
      if (project == null) {
        await ApiService.createProject(
          title: data['title']!,
          description: data['description']!,
          academicYear: data['academicYear']!,
          status: data['status']!,
        );
      } else {
        await ApiService.updateProject(
          projectId: project.id,
          title: data['title']!,
          description: data['description']!,
          academicYear: data['academicYear']!,
          status: data['status']!,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            project == null
                ? 'Project created successfully.'
                : 'Project updated successfully.',
          ),
        ),
      );

      await _loadProjects();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unable to save project: ${friendlyErrorMessage(e)}')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // Ask for confirmation before deleting a project.
  Future<void> _confirmDelete(Project project) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete project?',
      message: 'Are you sure you want to delete "${project.title}"? '
          'This action cannot be undone.',
    );

    if (confirmed) {
      await _deleteProject(project);
    }
  }

  // Delete project through FastAPI.
  Future<void> _deleteProject(Project project) async {
    try {
      await ApiService.deleteProject(project.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project deleted successfully.')),
      );

      await _loadProjects();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to delete project: ${friendlyErrorMessage(e)}')));
    }
  }

  // Project card.
  Widget _buildProjectCard(Project project) {
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
                Expanded(
                  child: Text(
                    project.title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showProjectDialog(project: project);
                    } else if (value == 'delete') {
                      _confirmDelete(project);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: AppColors.danger),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            Text(
              project.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(project.academicYear),
                ),
                Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 16),
                  label: Text(project.status),
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
    return PageBody(
      children: [
        const ScreenHeading(
          eyebrow: 'PROJECT MANAGEMENT',
          title: 'My projects',
          detail: 'Manage your capstone projects.',
        ),

        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const GroupManagementPage(),
              ),
            );
          },
          icon: const Icon(Icons.groups),
          label: const Text('Manage Groups'),
        ),

        const SizedBox(height: 4),

        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfessorMilestonesPage(),
              ),
            );
          },
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Manage Milestones'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0A2342),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 45),
          ),
        ),

        const SizedBox(height: 10),

        PrimaryButton(
          label: '＋ Create project',
          onPressed: _isSaving ? () {} : () => _showProjectDialog(),
        ),

        const SizedBox(height: 16),

        TextField(
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          decoration: const InputDecoration(
            hintText: 'Search projects',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: Text(
                'Projects (${_projects.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh projects',
              onPressed: _isLoading ? null : _loadProjects,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),

        if (_isSaving) const LinearProgressIndicator(),

        if (_isLoading)
          const LoadingView(message: 'Loading classes…')
        else if (_errorMessage != null)
          ErrorStateView(
            message: _errorMessage!,
            onRetry: _loadProjects,
          )
        else if (_filteredProjects.isEmpty)
          InfoCard(
            child: Column(
              children: [
                const Icon(Icons.folder_open_outlined, size: 40),
                const SizedBox(height: 8),
                Text(
                  _projects.isEmpty
                      ? 'No projects found.'
                      : 'No matching projects found.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _projects.isEmpty
                      ? 'Create your first capstone project to get started.'
                      : 'Try another search term.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._filteredProjects.map(_buildProjectCard),
      ],
    );
  }
}

class ProjectFormDialog extends StatefulWidget {
  final Project? project;

  const ProjectFormDialog({
    super.key,
    this.project,
  });

  @override
  State<ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<ProjectFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _academicYearController;
  late final TextEditingController _statusController;

  bool get isEditing => widget.project != null;

  @override
  void initState() {
    super.initState();

    final project = widget.project;

    _titleController = TextEditingController(
      text: project?.title ?? '',
    );

    _descriptionController = TextEditingController(
      text: project?.description ?? '',
    );

    _academicYearController = TextEditingController(
      text: project?.academicYear ?? '',
    );

    _statusController = TextEditingController(
      text: project?.status ?? 'ongoing',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _academicYearController.dispose();
    _statusController.dispose();

    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.pop(context, {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'academicYear': _academicYearController.text.trim(),
      'status': _statusController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'Edit project' : 'Create project'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Project title',
                  hintText: 'Enter project title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Project title is required.';
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
                  hintText: 'Enter project description',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Description is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _academicYearController,
                decoration: const InputDecoration(
                  labelText: 'Academic year',
                  hintText: 'Example: 2026-2027',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Academic year is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _statusController,
                decoration: const InputDecoration(
                  labelText: 'Project status',
                  hintText: 'Example: ongoing',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Project status is required.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Save changes' : 'Create'),
        ),
      ],
    );
  }
}
