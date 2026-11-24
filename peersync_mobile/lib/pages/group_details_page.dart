import 'package:flutter/material.dart';

import '../core/utils/error_messages.dart';
import '../models/group.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class GroupDetailsPage extends StatefulWidget {
  final String groupId;

  const GroupDetailsPage({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupDetailsPage> createState() =>
      _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  Group? group;
  bool isLoading = true;
  String? errorMessage;

  static const Color primaryColor = Color(0xFF0A2342);
  static const Color backgroundColor = Color(0xFFF2F5FF);

  @override
  void initState() {
    super.initState();
    loadGroupDetails();
  }

  Future<void> loadGroupDetails() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await ApiService.getGroup(widget.groupId);

      if (!mounted) return;

      setState(() {
        group = result;
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

  Future<void> _showAddMembersDialog() async {
    try {
      // Retrieve available active students.
      final currentGroup = group;
      if (currentGroup == null) return;
      final students = await ApiService.getAvailableStudents(projectID: currentGroup.projectID,);

      if (!mounted) return;

      // Exclude students who are already members.
      final existingMemberIDs = {
        ...group!.memberIDs,
        ...group!.members.map((member) => member.studentID),
      };

      final availableStudents = students
          .where((student) =>
              !existingMemberIDs.contains(student.uid))
          .toList();

      if (availableStudents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No available students to add.'),
          ),
        );
        return;
      }

      final selectedStudentIDs = <String>{};

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Add Group Members'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView(
                    shrinkWrap: true,
                    children: availableStudents.map((student) {
                      final isSelected =
                          selectedStudentIDs.contains(student.uid);

                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: primaryColor,
                        controlAffinity:
                            ListTileControlAffinity.leading,
                        title: Text(student.displayName),
                        subtitle: Text(student.email),
                        onChanged: (selected) {
                          setDialogState(() {
                            if (selected == true) {
                              selectedStudentIDs.add(student.uid);
                            } else {
                              selectedStudentIDs.remove(student.uid);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: selectedStudentIDs.isEmpty
                      ? null
                      : () async {
                          try {
                            await ApiService.addGroupMembers(
                              groupId: widget.groupId,
                              memberIDs: selectedStudentIDs.toList(),
                            );

                            // Check the dialog's context before closing it.
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            // Check the page's State before refreshing.
                            if (!mounted) return;

                            await loadGroupDetails();

                            // Check again after the asynchronous refresh.
                            if (!mounted) return;

                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Group members added successfully.'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;

                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to add members: ${friendlyErrorMessage(e)}'),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                    child: const Text('Add Selected'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load available students: ${friendlyErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _removeGroupMember(GroupMember member) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Group Member'),
          content: Text(
            'Are you sure you want to remove '
            '${member.displayName} from this group?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true || !mounted) return;

    try {
      await ApiService.removeGroupMember(
        groupId: widget.groupId,
        studentID: member.studentID,
      );

      if (!mounted) return;

      await loadGroupDetails();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member.displayName} was removed from the group.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove group member: ${friendlyErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showAssignLeaderDialog() async {
    final currentGroup = group;

    if (currentGroup == null) return;

    if (currentGroup.members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add group members before assigning a leader.'),
        ),
      );
      return;
    }

    final selectedLeaderID = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? selectedStudentID = currentGroup.leaderID;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Assign Group Leader'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select a member to become the group leader.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStudentID,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Group Member',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select a member'),
                    items: currentGroup.members.map((member) {
                      return DropdownMenuItem<String>(
                        value: member.studentID,
                        child: Text(
                          member.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedStudentID = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: selectedStudentID == null
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(
                            selectedStudentID,
                          );
                        },
                  child: const Text('Assign Leader'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedLeaderID == null || !mounted) return;

    // Avoid sending an unnecessary request if the leader hasn't changed.
    if (selectedLeaderID == currentGroup.leaderID) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This student is already the group leader.'),
        ),
      );
      return;
    }

    try {
      await ApiService.assignGroupLeader(
        groupId: widget.groupId,
        studentID: selectedLeaderID,
      );

      if (!mounted) return;

      await loadGroupDetails();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group leader updated successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign group leader: ${friendlyErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showRenameGroupDialog() async {
    final currentGroup = group;

    if (currentGroup == null) return;

    final newGroupName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return RenameGroupDialog(
          currentGroupName: currentGroup.groupName,
        );
      },
    );

    if (newGroupName == null || !mounted) return;

    if (newGroupName == currentGroup.groupName) {
      return;
    }

    try {
      await ApiService.updateGroup(
        groupId: widget.groupId,
        groupName: newGroupName,
      );

      if (!mounted) return;

      await loadGroupDetails();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group renamed successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to rename group: ${friendlyErrorMessage(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Group Details'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const LoadingView(message: 'Loading group details\u2026')
          : errorMessage != null
              ? _buildError()
              : group == null
                  ? const Center(
                      child: Text('Group not found.'),
                    )
                  : _buildDetails(),
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
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: loadGroupDetails,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails() {
    final currentGroup = group!;

    final leader = currentGroup.members
        .where((member) => member.studentID == currentGroup.leaderID)
        .firstOrNull;

    return RefreshIndicator(
      onRefresh: loadGroupDetails,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _showAddMembersDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Add Members'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

const SizedBox(height: 12),
          // Group information
          _buildSectionCard(
            title: 'Group Information',
            icon: Icons.groups,
            children: [
              _buildInfoRow(
                'Group Name',
                currentGroup.groupName,
              ),
              _buildInfoRow(
                'Project',
                currentGroup.projectTitle,
              ),
              _buildInfoRow(
                'Total Members',
                '${currentGroup.members.length}',
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showRenameGroupDialog,
                  icon: const Icon(Icons.edit),
                  label: const Text('Rename Group'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: const BorderSide(color: primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Group leader
          _buildSectionCard(
            title: 'Group Leader',
            icon: Icons.workspace_premium,
            children: [
              if (leader != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: primaryColor,
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    leader.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(leader.email),
                  trailing: const Chip(
                    label: Text('Leader'),
                  ),
                )
              else
                const Text('No Group Leader assigned.'),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showAssignLeaderDialog,
                  icon: const Icon(Icons.manage_accounts),
                  label: Text(
                    leader == null
                        ? 'Assign Group Leader'
                        : 'Change Group Leader',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: const BorderSide(color: primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Members
          _buildSectionCard(
            title: 'Group Members',
            icon: Icons.people,
            children: [
              if (currentGroup.members.isEmpty)
                const Text('No members added yet.')
              else
                ...currentGroup.members.map((member) {
                  final isLeader =
                      member.studentID == currentGroup.leaderID;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isLeader
                          ? primaryColor
                          : AppColors.textSecondary,
                      child: Text(
                        member.displayName.isNotEmpty
                            ? member.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    title: Text(
                      member.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      member.email.isEmpty
                          ? 'No email available'
                          : member.email,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLeader)
                          const Icon(
                            Icons.workspace_premium,
                            color: AppColors.warning,
                          )
                        else
                          const Icon(
                            Icons.person_outline,
                            color: AppColors.textMuted,
                          ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Remove member',
                          icon: const Icon(
                            Icons.person_remove,
                            color: AppColors.danger,
                          ),
                          onPressed: () => _removeGroupMember(member),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ],
        
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class RenameGroupDialog extends StatefulWidget {
  final String currentGroupName;

  const RenameGroupDialog({
    super.key,
    required this.currentGroupName,
  });

  @override
  State<RenameGroupDialog> createState() =>
      _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<RenameGroupDialog> {
  late final TextEditingController controller;

  static const Color primaryColor = Color(0xFF0A2342);

  @override
  void initState() {
    super.initState();

    controller = TextEditingController(
      text: widget.currentGroupName,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _saveChanges() {
    final newName = controller.text.trim();

    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group name cannot be empty.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(newName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Group'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Group Name',
          hintText: 'Enter new group name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _saveChanges(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _saveChanges,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}