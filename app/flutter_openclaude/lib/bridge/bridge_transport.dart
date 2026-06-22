import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class BridgeTransport {
  Stream<String> get messages;

  void send(String message);

  Future<void> close();
}

final class WebSocketBridgeTransport implements BridgeTransport {
  WebSocketBridgeTransport(String url)
    : _channel = WebSocketChannel.connect(Uri.parse(url));

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages => _channel.stream.map((message) {
    if (message is String) return message;
    return message.toString();
  });

  @override
  void send(String message) {
    _channel.sink.add(message);
  }

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}
