/// One shared packing/prep item on a trip's checklist.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.tripId,
    required this.label,
    required this.done,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String label;
  final bool done;
  final DateTime createdAt;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String,
    tripId: json['trip_id'] as String,
    label: json['label'] as String,
    done: json['done'] as bool? ?? false,
    createdAt: json['created_at'] is String
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.fromMillisecondsSinceEpoch(0),
  );
}
