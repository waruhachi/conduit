import 'package:freezed_annotation/freezed_annotation.dart';

part 'folder.freezed.dart';
part 'folder.g.dart';

// Timestamp converter for Unix timestamps
class TimestampConverter implements JsonConverter<DateTime, dynamic> {
  const TimestampConverter();

  @override
  DateTime fromJson(dynamic json) {
    if (json is String) {
      return DateTime.parse(json);
    } else if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json * 1000);
    } else {
      throw ArgumentError('Invalid date format: $json');
    }
  }

  @override
  dynamic toJson(DateTime object) {
    return object.millisecondsSinceEpoch ~/ 1000;
  }
}

@freezed
sealed class Folder with _$Folder {
  const factory Folder({
    required String id,
    required String name,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
    String? parentId,
    @Default([]) List<String> conversationIds,
    @Default([]) List<Folder> subfolders,
    @Default({}) Map<String, dynamic> metadata,
  }) = _Folder;

  factory Folder.fromJson(Map<String, dynamic> json) => _$FolderFromJson(json);
}
