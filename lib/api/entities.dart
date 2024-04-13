import 'dart:convert';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_chat/exceptions/exceptions.dart';

class Message {
  final OpenAIChatMessageRole _role;
  final String _message;

  String get role => switch (_role) {
        OpenAIChatMessageRole.assistant => "Assistant",
        OpenAIChatMessageRole.user => "User",
        OpenAIChatMessageRole.system => "System",
        _ => throw UnknownRoleException(),
      };

  String get message => _message;
  OpenAIChatMessageRole get openAIRole => _role;

  Message(this._role, this._message);

  String toJson() {
    return jsonEncode({
      'role': role,
      'message': message,
    });
  }

  static Message fromJson(Map<String, dynamic> map) {
    return Message(
      _fromStringToRole(map['role']),
      map['message'],
    );
  }
}

OpenAIChatMessageRole _fromStringToRole(String role) {
  switch (role) {
    case "System":
      return OpenAIChatMessageRole.system;
    case "User":
      return OpenAIChatMessageRole.user;
    case "Assistant":
      return OpenAIChatMessageRole.assistant;
    default:
      throw UnknownOpenAIChatMessageRoleException();
  }
}
