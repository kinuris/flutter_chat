library flutter_chat;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_openai/dart_openai.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_chat/api/entities.dart';
import 'package:flutter_chat/exceptions/exceptions.dart';

bool _initialized = false;

late final String _secret;

void initApi(
  String apiKey, {
  Duration timeout = const Duration(seconds: 60),
  String baseUrl = "https://api.openai.com/",
  String secret = "default",
}) {
  OpenAI.apiKey = apiKey;
  OpenAI.requestsTimeOut = timeout;
  OpenAI.baseUrl = baseUrl;

  _initialized = true;
  _secret = secret;
}

class MessageSession {
  final List<Message> _history;

  bool _responding = false;

  MessageSession._fromJsonEncrypted({
    required List<Message> history,
  }) : _history = history;

  Stream<String>? play({
    bool compounded = true,
  }) {
    if (_responding) {
      throw MessagedWhileStillRespondingException();
    }

    if (_history.isEmpty) {
      return null;
    }

    if (_history.last.role == "Assistant") {
      return null;
    }

    final responseStream = switch (compounded) {
      true => _sendMessageToAPICompounded(),
      false => _sendMessageToAPI(),
    };

    switch (compounded) {
      case true:
        _listenLockCompounded(responseStream);
      case false:
        _listenLock(responseStream);
    }

    return responseStream;
  }

  Stream<String> playRegardless({
    bool compounded = true,
  }) {
    if (_responding) {
      throw MessagedWhileStillRespondingException();
    }

    final responseStream = switch (compounded) {
      true => _sendMessageToAPICompounded(),
      false => _sendMessageToAPI(),
    };

    switch (compounded) {
      case true:
        _listenLockCompounded(responseStream);
      case false:
        _listenLock(responseStream);
    }

    return responseStream;
  }

  void queueUserMessage(
    String message, {
    bool compounded = true,
  }) {
    _history.add(
      Message(
        OpenAIChatMessageRole.user,
        message,
      ),
    );
  }

  void queueSystemMessage(
    String message, {
    bool compounded = true,
  }) {
    _history.add(
      Message(
        OpenAIChatMessageRole.system,
        message,
      ),
    );
  }

  Stream<String> sendUserMessage(
    String message, {
    bool compounded = true,
  }) {
    queueUserMessage(
      message,
      compounded: compounded,
    );

    return playRegardless();
  }

  Stream<String> sendSystemMessage(
    String message, {
    bool compounded = true,
  }) {
    queueSystemMessage(
      message,
      compounded: compounded,
    );

    return playRegardless();
  }

  Stream<String> _sendMessageToAPICompounded() {
    Stream<OpenAIStreamChatCompletionModel> completionStream =
        OpenAI.instance.chat.createStream(
      model: 'gpt-3.5-turbo-0125',
      messages: _toOpenAIMessages,
    );

    final streamController = StreamController<String>.broadcast();

    String message = '';
    completionStream.listen(
      (response) {
        streamController.add(message +=
            (response.choices.first.delta.content?.first?.text ?? ''));
      },
      onDone: () => streamController.close(),
    );

    return streamController.stream;
  }

  List<Message> get history => _history
      .where((record) => record.openAIRole != OpenAIChatMessageRole.system)
      .toList();

  List<OpenAIChatCompletionChoiceMessageModel> get _toOpenAIMessages => _history
      .map(
        (e) => OpenAIChatCompletionChoiceMessageModel(
          role: e.openAIRole,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(e.message),
          ],
        ),
      )
      .toList();

  Stream<String> _sendMessageToAPI() {
    Stream<OpenAIStreamChatCompletionModel> completionStream =
        OpenAI.instance.chat.createStream(
      model: 'gpt-3.5-turbo-0125',
      messages: _toOpenAIMessages,
    );

    final streamController = StreamController<String>.broadcast();

    completionStream.listen(
      (response) {
        streamController
            .add(response.choices.first.delta.content?.first?.text ?? '');
      },
      onDone: () => streamController.close(),
    );

    return streamController.stream;
  }

  _listenLockCompounded(Stream<String> current) {
    _responding = true;
    String message = '';

    current.listen(
      (responseToken) {
        message = responseToken;
      },
      onDone: () {
        _history.add(Message(
          OpenAIChatMessageRole.assistant,
          message,
        ));

        _responding = false;
      },
    );
  }

  _listenLock(Stream<String> current) {
    _responding = true;
    String message = '';

    current.listen(
      (responseToken) {
        message += responseToken;
      },
      onDone: () {
        _history.add(Message(
          OpenAIChatMessageRole.assistant,
          message,
        ));

        _responding = false;
      },
    );
  }

  MessageSession() : _history = [] {
    assert(_initialized, "initApi() must be called first");
  }

  static MessageSession fromJsonEncrypted(String encrypted) {
    final key = Key.fromUtf8(_secret.padLeft(32, '0'));

    final encrypter = Encrypter(AES(key));
    final decrypted = encrypter.decrypt(
      Encrypted.fromBase64(encrypted),
      iv: IV(
        Uint8List.fromList([0, 0, 0, 0]),
      ),
    );

    final decoded = jsonDecode(decrypted);
    final history = (decoded['history'] as List<dynamic>)
        .map((e) => jsonDecode(e))
        .cast<Map<String, dynamic>>()
        .map(Message.fromJson)
        .toList();

    return MessageSession._fromJsonEncrypted(history: history);
  }

  String toJsonEncrypted() {
    final plain = jsonEncode({
      'history': _history.map((msg) => msg.toJson()).toList(),
    });

    final key = Key.fromUtf8(_secret.padLeft(32, '0'));

    final encrypter = Encrypter(AES(key));
    final encrypted = encrypter.encrypt(
      plain,
      iv: IV(
        Uint8List.fromList([0, 0, 0, 0]),
      ),
    );

    return encrypted.base64;
  }
}
