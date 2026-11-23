import 'package:flutter/material.dart';
import '../models/announcement.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';

class StudentAnnouncementsPage extends StatefulWidget {
  const StudentAnnouncementsPage({super.key});

  @override
  State<StudentAnnouncementsPage> createState() =>
      _StudentAnnouncementsPageState();
}

class _StudentAnnouncementsPageState
    extends State<StudentAnnouncementsPage> {
  late Future<List<Announcement>> _announcementsFuture;

  final TextEditingController _searchController =
      TextEditingController();

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // The backend identifies the currently logged-in student
  // through the Firebase ID token and filters announcements
  // according to the student's project/group memberships.
  void _loadAnnouncements() {
    _announcementsFuture = ApiService.getAnnouncements();
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Date unavailable';
    }

    final localDate = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDate);

    if (difference.inMinutes < 1 && !difference.isNegative) {
      return 'Just now';
    }

    if (difference.inMinutes < 60 && !difference.isNegative) {
      return '${difference.inMinutes}m ago';
    }

    if (difference.inHours < 24 && !difference.isNegative) {
      return '${difference.inHours}h ago';
    }

    if (difference.inDays < 7 && !difference.isNegative) {
      return '${difference.inDays}d ago';
    }

    return '${localDate.day}/${localDate.month}/${localDate.year}';
  }

  List<Announcement> _filterAnnouncements(
    List<Announcement> announcements,
  ) {
    if (_searchQuery.trim().isEmpty) {
      return announcements;
    }

    final query = _searchQuery.toLowerCase().trim();

    return announcements.where((announcement) {
      return announcement.title.toLowerCase().contains(query) ||
          announcement.content.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildAnnouncementCard(Announcement announcement) {
    final isGroupAnnouncement =
        announcement.targetType.toLowerCase() == 'group';

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BadgeX(
                isGroupAnnouncement
                    ? 'GROUP ANNOUNCEMENT'
                    : 'PROJECT ANNOUNCEMENT',
              ),
              const Spacer(),
              Text(
                _formatDate(announcement.createdAt),
                style: subStyle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            announcement.title,
            style: titleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            isGroupAnnouncement
                ? 'Professor · Selected groups'
                : 'Professor · Project-wide',
            style: subStyle,
          ),
          const SizedBox(height: 10),
          Text(
            announcement.content,
            style: subStyle,
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
          detail: 'Updates from your professors and classes.',
        ),

        // Search announcements
        TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          decoration: InputDecoration(
            hintText: 'Search announcements',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();

                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Announcement list
        FutureBuilder<List<Announcement>>(
          future: _announcementsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 45),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError) {
              return InfoCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 38,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Unable to load announcements.',
                      style: titleStyle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.error.toString(),
                      style: subStyle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _loadAnnouncements();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              );
            }

            final announcements = snapshot.data ?? [];
            final filteredAnnouncements =
                _filterAnnouncements(announcements);

            if (announcements.isEmpty) {
              return const InfoCard(
                child: Column(
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      size: 42,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No announcements yet.',
                      style: titleStyle,
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Announcements from your projects and groups '
                      'will appear here.',
                      style: subStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            if (filteredAnnouncements.isEmpty) {
              return const InfoCard(
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 38,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No matching announcements.',
                      style: titleStyle,
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Try searching with another title or keyword.',
                      style: subStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filteredAnnouncements.length} announcement(s)',
                      style: subStyle,
                    ),
                    IconButton(
                      tooltip: 'Refresh announcements',
                      onPressed: () {
                        setState(() {
                          _loadAnnouncements();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),

                ...filteredAnnouncements.map(
                  (announcement) =>
                      _buildAnnouncementCard(announcement),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 10),
      ],
    );
  }
}