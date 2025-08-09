import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

@freezed
sealed class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String role, // 'user', 'assistant', 'system'
    required String content,
    required DateTime timestamp,
    String? model,
    @Default(false) bool isStreaming,
    List<String>? attachmentIds,
    Map<String, dynamic>? metadata,
    List<Map<String, dynamic>>? sources,
    Map<String, dynamic>? usage,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
