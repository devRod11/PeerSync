class GroupMember {
  final String membershipID;
  final String groupID;
  final String projectID;
  final String studentID;
  final String displayName;
  final String email;
  final String memberRole;
  final DateTime? joinedAt;

  const GroupMember({
    required this.membershipID,
    required this.groupID,
    required this.projectID,
    required this.studentID,
    required this.displayName,
    required this.email,
    required this.memberRole,
    this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      membershipID: json['membershipID']?.toString() ?? '',
      groupID: json['groupID']?.toString() ?? '',
      projectID: json['projectID']?.toString() ?? '',
      studentID: json['studentID']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Unknown Student',
      email: json['email']?.toString() ?? '',
      memberRole: json['memberRole']?.toString() ?? 'Member',
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString())
          : null,
    );
  }
}

class Group {
  final String id;
  final String groupName;
  final String projectID;
  final String projectTitle;
  final String professorID;
  final String? leaderID;
  final List<String> memberIDs;
  final List<GroupMember> members;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Group({
    required this.id,
    required this.groupName,
    required this.projectID,
    required this.projectTitle,
    required this.professorID,
    this.leaderID,
    this.memberIDs = const [],
    this.members = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    final projectData = json['project'];

    return Group(
      id: json['id']?.toString() ?? '',
      groupName: json['groupName']?.toString() ?? '',
      projectID: json['projectID']?.toString() ?? '',
      projectTitle: projectData is Map<String, dynamic>
          ? projectData['title']?.toString() ?? 'Project unavailable'
          : 'Project unavailable',
      professorID: json['professorID']?.toString() ?? '',
      leaderID: json['leaderID']?.toString(),
      memberIDs: (json['memberIDs'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList() ??
          [],
      members: (json['members'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((member) => GroupMember.fromJson(member))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }
}