class MessageAlert {
  const MessageAlert({
    required this.accountId,
    required this.conversationId,
    required this.messageId,
    required this.title,
    required this.body,
  });

  final String accountId;
  final String conversationId;
  final String messageId;
  final String title;
  final String body;

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'conversationId': conversationId,
    'messageId': messageId,
    'title': title,
    'body': body,
  };
}
