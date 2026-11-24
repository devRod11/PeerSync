import 'package:flutter/material.dart';

import '../core/utils/error_messages.dart';
import '../models/group.dart';
import '../models/project.dart';
import '../models/student_option.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';
import 'group_details_page.dart';

class GroupManagementPage extends StatefulWidget {
  const GroupManagementPage({super.key});

  @override
  State<GroupManagementPage> createState() =>
      _GroupManagementPageState();
}

class _GroupManagementPageState
    extends State<GroupManagementPage> {
    List<Group> groups = [];
    List<Project> projects = [];
    List<StudentOption> students = [];

    bool isLoading = true;
    String? errorMessage;

    @override
    void initState() {
      super.initState();
      loadGroupManagementData();
    }

    Future<void> loadGroupManagementData() async {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      try {
        final results = await Future.wait([
          ApiService.getGroups(),
          ApiService.getProjects(),
        ]);

        if (!mounted) return;

        setState(() {
          groups = results[0] as List<Group>;
          projects = results[1] as List<Project>;
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
  
    void _showCreateGroupDialog() {
      if (projects.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Create a project first before creating a group.',
            ),
          ),
        );
        return;
      }

      showDialog<void>(
        context: context,
        builder: (dialogContext) => CreateGroupDialog(
          projects: projects,
          onCreated: loadGroupManagementData,
        ),
      );
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F5FF),
        appBar: AppBar(
          title: const Text('Group Management'),
          backgroundColor: const Color(0xFF0A2342),
          foregroundColor: Colors.white,
        ),
        body: isLoading
            ? const LoadingView(message: 'Loading groups\u2026')
            : errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: AppColors.danger,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: loadGroupManagementData,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildGroupList(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateGroupDialog,
          backgroundColor: const Color(0xFF0A2342),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.group_add),
          label: const Text('Create Group'),
        ),
      );
    }

    Widget _buildGroupList() {
      if (groups.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 64,
                color: AppColors.textMuted,
              ),
              SizedBox(height: 12),
              Text(
                'No groups created yet.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: loadGroupManagementData,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF0A2342),
                  child: Icon(
                    Icons.groups,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  group.groupName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${group.projectTitle}\n'
                  '${group.members.length} members',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupDetailsPage(
                        groupId: group.id,
                      ),
                    ),
                  );

                  // Refresh the group list when returning.
                  if (mounted) {
                    await loadGroupManagementData();
                  }
                },
              ),
            );
          },
        ),
      );
  }
}

class CreateGroupDialog extends StatefulWidget {
  final List<Project> projects;
  final Future<void> Function() onCreated;

  const CreateGroupDialog({
    super.key,
    required this.projects,
    required this.onCreated,
  });

  @override
  State<CreateGroupDialog> createState() =>
      _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _groupNameController =
      TextEditingController();

  String? selectedProjectID;
  String? selectedLeaderID;

  final Set<String> selectedMemberIDs = {};
  List<StudentOption> availableStudents = [];

  bool isLoadingStudents = false;
  bool isSaving = false;
  String? errorMessage;

  static const Color primaryColor = Color(0xFF0A2342);

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableStudents(String? projectID) async {
    setState(() {
      selectedProjectID = projectID;
      selectedLeaderID = null;
      selectedMemberIDs.clear();
      availableStudents = [];
      errorMessage = null;
      isLoadingStudents = projectID != null;
    });

    if (projectID == null) return;

    try {
      final result = await ApiService.getAvailableStudents(
        projectID: projectID,
      );

      if (!mounted || selectedProjectID != projectID) return;

      setState(() {
        availableStudents = result;
      });
    } catch (e) {
      if (!mounted || selectedProjectID != projectID) return;

      setState(() {
        errorMessage = 'Unable to load available students: ${friendlyErrorMessage(e)}';
      });
    } finally {
      if (mounted && selectedProjectID == projectID) {
        setState(() {
          isLoadingStudents = false;
        });
      }
    }
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedProjectID == null) {
      setState(() {
        errorMessage = 'Please select a project.';
      });
      return;
    }

    if (selectedMemberIDs.isNotEmpty &&
        selectedLeaderID == null) {
      setState(() {
        errorMessage = 'Please assign a Group Leader.';
      });
      return;
    }

    if (selectedLeaderID != null &&
        !selectedMemberIDs.contains(selectedLeaderID)) {
      setState(() {
        errorMessage =
            'The Group Leader must be a selected member.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
    });

    try {
      await ApiService.createGroup(
        projectID: selectedProjectID!,
        groupName: _groupNameController.text.trim(),
        memberIDs: selectedMemberIDs.toList(),
        leaderID: selectedLeaderID,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      await widget.onCreated();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = friendlyErrorMessage(e);
        isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Group'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _groupNameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    hintText: 'Enter group name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.groups),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Please enter a group name.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: selectedProjectID,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select Project',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.folder),
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
                  onChanged: isSaving
                    ? null
                    : (value) {
                        _loadAvailableStudents(value);
                      },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a project.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                const Text(
                  'Select Student Members',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 8),

                if (selectedProjectID == null)
                  const Text(
                    'Select a project to view eligible students.',
                  )
                else if (isLoadingStudents)
                  const LoadingView(
                    message: 'Loading eligible students\u2026',
                  )
                else if (availableStudents.isEmpty)
                  const Text(
                    'No unassigned active students available for this project.',
                  )
                else
                  Container(
                    constraints: const BoxConstraints(
                      maxHeight: 220,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.textMuted,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableStudents.length,
                      itemBuilder: (context, index) {
                        final student = availableStudents[index];

                        final isSelected =
                            selectedMemberIDs.contains(student.uid);

                        return CheckboxListTile(
                          value: isSelected,
                          dense: true,
                          title: Text(student.displayName),
                          subtitle: Text(student.email),
                          controlAffinity:
                              ListTileControlAffinity.leading,
                          onChanged: isSaving
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      selectedMemberIDs.add(student.uid);
                                    } else {
                                      selectedMemberIDs.remove(student.uid);

                                      if (selectedLeaderID == student.uid) {
                                        selectedLeaderID = null;
                                      }
                                    }
                                  });
                                },
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: selectedLeaderID,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Assign Group Leader',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.workspace_premium),
                  ),
                  items: availableStudents
                    .where(
                      (student) =>
                          selectedMemberIDs.contains(student.uid),
                    )
                      .map((student) {
                    return DropdownMenuItem<String>(
                      value: student.uid,
                      child: Text(student.displayName),
                    );
                  }).toList(),
                  onChanged: isSaving ||
                          selectedMemberIDs.isEmpty
                      ? null
                      : (value) {
                          setState(() {
                            selectedLeaderID = value;
                          });
                        },
                ),

                const SizedBox(height: 12),

                if (errorMessage != null)
                  Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),

                Text(
                  '${selectedMemberIDs.length} student(s) selected',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: isSaving ? null : _createGroup,
          icon: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save),
          label: Text(
            isSaving ? 'Creating...' : 'Create Group',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
