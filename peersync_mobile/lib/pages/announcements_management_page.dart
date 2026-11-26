import 'package:flutter/material.dart';

import '../core/a11y/app_a11y.dart';
import '../core/utils/error_messages.dart';
import '../models/announcement.dart';
import '../models/group.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class AnnouncementsManagement extends StatefulWidget {
  const AnnouncementsManagement({super.key});

  @override
  State<AnnouncementsManagement> createState() =>
      _AnnouncementsManagementState();
}

class _AnnouncementsManagementState
    extends State<AnnouncementsManagement> {
  bool isLoading = true;
  String? errorMessage;

  List<Project> projects = [];
  List<Group> groups = [];
  List<Announcement> announcements = [];

  String? selectedProjectID;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Load projects, groups, and announcements.
  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loadedProjects = await ApiService.getProjects();
      final loadedGroups = await ApiService.getGroups();

      final projectID = selectedProjectID != null &&
              loadedProjects.any((p) => p.id == selectedProjectID)
          ? selectedProjectID
          : (loadedProjects.isNotEmpty ? loadedProjects.first.id : null);

      final loadedAnnouncements = projectID == null
          ? <Announcement>[]
          : await ApiService.getAnnouncements(
              projectID: projectID,
            );

      if (!mounted) return;

      setState(() {
        projects = loadedProjects;
        groups = loadedGroups;
        selectedProjectID = projectID;
        announcements = loadedAnnouncements;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = friendlyErrorMessage(e);
        isLoading = false;
      });
    }
  }

  // Reload announcements for the selected project.
  Future<void> _loadAnnouncements() async {
    if (selectedProjectID == null) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await ApiService.getAnnouncements(
        projectID: selectedProjectID,
      );

      if (!mounted) return;

      setState(() {
        announcements = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = friendlyErrorMessage(e);
        isLoading = false;
      });
    }
  }

  // Display a short message.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

    // Create or edit an announcement.
  Future<void> _showAnnouncementDialog({
      Announcement? announcement,
    }) async {
      if (projects.isEmpty) {
        _showMessage('Create a project before publishing announcements.');
        return;
      }

      final isEditing = announcement != null;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _AnnouncementDialog(
            projects: projects,
            groups: groups,
            selectedProjectID: selectedProjectID,
            announcement: announcement,
          );
        },
      );

      if (!mounted || result != true) return;

      _showMessage(
        isEditing
            ? 'Announcement updated successfully.'
            : 'Announcement published successfully.',
      );

      await _loadAnnouncements();
    }

  // Confirm and delete an announcement.
  Future<void> _confirmDelete(Announcement announcement) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete announcement?',
      message: 'Are you sure you want to delete "${announcement.title}"? '
          'This action cannot be undone.',
    );

    if (!confirmed) return;

    try {
      await ApiService.deleteAnnouncement(announcement.id);

      if (!mounted) return;

      _showMessage('Announcement deleted successfully.');
      await _loadAnnouncements();
    } catch (e) {
      if (!mounted) return;
      _showMessage(friendlyErrorMessage(e));
    }
  }

  String _formatDate(DateTime? date) => AppA11y.formatDate(date);

  String _audienceLabel(Announcement announcement) {
    if (announcement.targetType == 'project') {
      return 'Entire Project';
    }

    final count = announcement.groupID?.length ?? 0;

    return '$count ${count == 1 ? 'Group' : 'Groups'}';
  }

  Widget _buildAnnouncementCard(Announcement announcement) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BadgeX('PUBLISHED'),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _showAnnouncementDialog(
                      announcement: announcement,
                    );
                  } else if (value == 'delete') {
                    _confirmDelete(announcement);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18),
                        SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 9),

          Text(
            announcement.title,
            style: titleStyle,
          ),

          const SizedBox(height: 5),

          Text(
            announcement.content,
            style: subStyle,
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(Icons.campaign_outlined, size: 16),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _audienceLabel(announcement),
                  style: subStyle,
                ),
              ),
              Text(
                _formatDate(announcement.createdAt),
                style: subStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const ScreenHeading(
          title: 'Announcements',
          detail: 'Communicate updates to your classes.',
        ),

        PrimaryButton(
          label: '＋ Create announcement',
          onPressed: () => _showAnnouncementDialog(),
        ),

        const SizedBox(height: 16),

        if (projects.isNotEmpty) ...[
          const FieldLabel('Select project'),
          DropdownButtonFormField<String>(
            initialValue: selectedProjectID,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: projects.map((project) {
              return DropdownMenuItem<String>(
                value: project.id,
                child: Text(
                  project.title,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;

              setState(() {
                selectedProjectID = value;
              });

              _loadAnnouncements();
            },
          ),
          const SizedBox(height: 16),
        ],

        Row(
          children: [
            const Expanded(
              child: SectionHeading('Published announcements'),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: isLoading ? null : _loadData,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),

        if (isLoading)
          const LoadingView(message: 'Loading announcements\u2026')
        else if (errorMessage != null)
          InfoCard(
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.danger,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _loadData,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          )
        else if (projects.isEmpty)
          const InfoCard(
            child: Text(
              'No projects are available. Create a project before publishing announcements.',
            ),
          )
        else if (announcements.isEmpty)
          const InfoCard(
            child: Column(
              children: [
                Icon(
                  Icons.campaign_outlined,
                  size: 38,
                  color: AppColors.textMuted,
                ),
                SizedBox(height: 8),
                Text(
                  'No announcements yet.',
                  style: titleStyle,
                ),
                SizedBox(height: 4),
                Text(
                  'Create an announcement to share updates with your students.',
                  style: subStyle,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...announcements.map(_buildAnnouncementCard),
      ],
    );
  }
}

class _AnnouncementDialog extends StatefulWidget {
  final List<Project> projects;
  final List<Group> groups;
  final String? selectedProjectID;
  final Announcement? announcement;

  const _AnnouncementDialog({
    required this.projects,
    required this.groups,
    required this.selectedProjectID,
    this.announcement,
  });

  @override
  State<_AnnouncementDialog> createState() =>
      _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  late String _dialogProjectID;
  late String _targetType;
  late List<String> _selectedGroupIDs;

  bool _isSaving = false;

  bool get _isEditing => widget.announcement != null;

  @override
  void initState() {
    super.initState();

    final announcement = widget.announcement;

    _titleController = TextEditingController(
      text: announcement?.title ?? '',
    );

    _contentController = TextEditingController(
      text: announcement?.content ?? '',
    );

    _dialogProjectID = announcement?.projectID ??
        widget.selectedProjectID ??
        widget.projects.first.id;

    _targetType = announcement?.targetType ?? 'project';

    _selectedGroupIDs = List<String>.from(
      announcement?.groupID ?? [],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();

    super.dispose();
  }

  // Save a new announcement or update an existing one.
  Future<void> _saveAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;

    if (_targetType == 'group' && _selectedGroupIDs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one group.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      if (_isEditing) {
        await ApiService.updateAnnouncement(
          announcementId: widget.announcement!.id,
          targetType: _targetType,
          groupID: _targetType == 'group'
              ? _selectedGroupIDs
              : null,
          title: _titleController.text,
          content: _contentController.text,
        );
      } else {
        await ApiService.createAnnouncement(
          projectID: _dialogProjectID,
          targetType: _targetType,
          groupID: _targetType == 'group'
              ? _selectedGroupIDs
              : null,
          title: _titleController.text,
          content: _contentController.text,
        );
      }

      if (!mounted) return;

      // Return true to the parent page to indicate a successful save.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableGroups = widget.groups
        .where((group) => group.projectID == _dialogProjectID)
        .toList();

    return AlertDialog(
      title: Text(
        _isEditing ? 'Edit announcement' : 'Create announcement',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Project',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  initialValue: _dialogProjectID,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: widget.projects.map((project) {
                    return DropdownMenuItem<String>(
                      value: project.id,
                      child: Text(
                        project.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _isEditing || _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;

                          setState(() {
                            _dialogProjectID = value;
                            _selectedGroupIDs = [];
                          });
                        },
                ),

                const SizedBox(height: 16),

                const Text(
                  'Audience',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  initialValue: _targetType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'project',
                      child: Text('Entire Project'),
                    ),
                    DropdownMenuItem(
                      value: 'group',
                      child: Text('Selected Groups'),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;

                          setState(() {
                            _targetType = value;

                            if (_targetType == 'project') {
                              _selectedGroupIDs = [];
                            }
                          });
                        },
                ),

                if (_targetType == 'group') ...[
                  const SizedBox(height: 14),

                  const Text(
                    'Select Groups',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 6),

                  if (availableGroups.isEmpty)
                    const Text(
                      'No groups are available for this project.',
                      style: TextStyle(color: AppColors.textMuted),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(
                        maxHeight: 180,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: availableGroups.map((group) {
                          return CheckboxListTile(
                            dense: true,
                            title: Text(group.groupName),
                            value: _selectedGroupIDs.contains(group.id),
                            onChanged: _isSaving
                                ? null
                                : (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        if (!_selectedGroupIDs
                                            .contains(group.id)) {
                                          _selectedGroupIDs.add(group.id);
                                        }
                                      } else {
                                        _selectedGroupIDs.remove(group.id);
                                      }
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                    ),
                ],

                const SizedBox(height: 16),

                const Text(
                  'Title',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _titleController,
                  enabled: !_isSaving,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    hintText: 'Enter announcement title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an announcement title.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                const Text(
                  'Message',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _contentController,
                  enabled: !_isSaving,
                  maxLines: 5,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    hintText: 'Write your announcement...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the announcement message.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveAnnouncement,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  _isEditing ? 'Save Changes' : 'Publish',
                ),
        ),
      ],
    );
  }
}