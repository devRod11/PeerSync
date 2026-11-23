class Project {
  final String id;
  final String title;
  final String description;
  final String academicYear;
  final String status;
  final String? professorID;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Project({
    required this.id,
    required this.title,
    required this.description,
    required this.academicYear,
    required this.status,
    this.professorID,
    this.createdAt,
    this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      academicYear: json['academicYear']?.toString() ?? '',
      status: json['status']?.toString() ?? 'ongoing',
      professorID: json['professorID']?.toString(),
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
      'title': title,
      'description': description,
      'academicYear': academicYear,
      'status': status,
    };
  }
}
