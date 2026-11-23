class StudentOption {
  final String uid;
  final String displayName;
  final String email;

  const StudentOption({
    required this.uid,
    required this.displayName,
    required this.email,
  });

  factory StudentOption.fromJson(Map<String, dynamic> json) {
    return StudentOption(
      uid: json['uid']?.toString() ?? '',
      displayName: json['displayName']?.toString() ??
          'Unknown Student',
      email: json['email']?.toString() ?? '',
    );
  }
}