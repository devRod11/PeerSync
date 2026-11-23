class Announcement {
  final String id;
  final String authorID;
  final String projectID;
  final String targetType;
  final List<String>? groupID;
  final String title;
  final String content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Announcement({
    required this.id,
    required this.authorID,
    required this.projectID,
    required this.targetType,
    this.groupID,
    required this.title,
    required this.content,
    this.createdAt,
    this.updatedAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id']?.toString() ?? '',
      authorID: json['authorID']?.toString() ?? '',
      projectID: json['projectID']?.toString() ?? '',
      targetType: json['targetType']?.toString() ?? 'project',
      groupID: (json['groupID'] as List<dynamic>?)
          ?.map((id) => id.toString())
          .toList(),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectID': projectID,
      'targetType': targetType,
      'groupID': groupID,
      'title': title,
      'content': content,
    };
  }
}