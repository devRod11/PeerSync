class Milestone {
  final String id;
  final String projectID;
  final List<String> groupID;
  final String title;
  final String description;
  final int sequence;
  final DateTime startDate;
  final DateTime dueDate;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  const Milestone({
    required this.id,
    required this.projectID,
    required this.groupID,
    required this.title,
    required this.description,
    required this.sequence,
    required this.startDate,
    required this.dueDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  factory Milestone.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;

      return DateTime.tryParse(value?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    DateTime? parseOptionalDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return Milestone(
      id: json['id']?.toString() ?? '',
      projectID: json['projectID']?.toString() ?? '',
      groupID: (json['groupID'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList() ??
          [],
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      sequence: (json['sequence'] as num?)?.toInt() ?? 1,
      startDate: parseDate(json['startDate']),
      dueDate: parseDate(json['dueDate']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: parseOptionalDate(json['createdAt']),
      updatedAt: parseOptionalDate(json['updatedAt']),
      createdBy: json['createdBy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectID': projectID,
      'groupID': groupID,
      'title': title,
      'description': description,
      'sequence': sequence,
      'startDate': startDate.toUtc().toIso8601String(),
      'dueDate': dueDate.toUtc().toIso8601String(),
      'status': status,
    };
  }
}