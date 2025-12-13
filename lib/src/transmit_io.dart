/*
 * transmit_client
 *
 * (c) mohamed lounnas <mohamad@feeef.org>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// IO implementation using HTTP for SSE.
/// This replaces EventSourceStub when running on dart:io.
class EventSourceIO {
  final Uri _url;
  final StreamController<MessageEvent> _messageController =
      StreamController<MessageEvent>.broadcast();
  final StreamController<void> _openController = StreamController<void>.broadcast();
  final StreamController<void> _errorController = StreamController<void>.broadcast();
  final Completer<void> _readyCompleter = Completer<void>();
  StreamSubscription<String>? _subscription;
  http.StreamedResponse? _response;
  http.Client? _client;
  bool _closed = false;

  EventSourceIO(Uri url, {bool withCredentials = false}) : _url = url {
    _connect();
  }

  Future<void> _connect() async {
    try {
      // Clean up any existing connection first
      await _cleanup();
      
      _client = http.Client();
      final request = http.Request('GET', _url);
      // SSE anti-buffering request headers
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache, no-transform';
      request.headers['Connection'] = 'keep-alive';
      // Note: X-Accel-Buffering is a response header that the server should send
      // It cannot be set as a request header

      _response = await _client!.send(request);
      
      if (_response!.statusCode != 200) {
        throw Exception('SSE connection failed: ${_response!.statusCode}');
      }

      if (_closed) {
        await _cleanup();
        return;
      }

      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
      _openController.add(null);

      // Parse SSE stream
      _subscription = _response!.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (_closed) return;
              _parseSSELine(line);
            },
            onError: (error) {
              if (!_closed) {
                _errorController.add(null);
              }
            },
            onDone: () {
              if (!_closed) {
                _errorController.add(null);
              }
            },
            cancelOnError: false,
          );
    } catch (error) {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(error);
      }
      if (!_closed) {
        _errorController.add(null);
      }
    }
  }
  
  Future<void> _cleanup() async {
    _subscription?.cancel();
    _subscription = null;
    _response = null;
    try {
      _client?.close();
    } catch (e) {
      // Ignore errors during cleanup
    }
    _client = null;
  }

  String? _lastEventId;
  String? _eventType;
  final StringBuffer _dataBuffer = StringBuffer();

  void _parseSSELine(String line) {
    if (line.isEmpty) {
      // Empty line means end of message
      if (_dataBuffer.isNotEmpty) {
        final data = _dataBuffer.toString().trim();
        _messageController.add(MessageEvent(
          data: data.isEmpty ? null : data,
          event: _eventType,
          id: _lastEventId,
        ));
        _dataBuffer.clear();
        _eventType = null;
      }
      return;
    }

    if (line.startsWith(':')) {
      // Comment line (heartbeat) - still counts as connection activity
      // We parse it but don't emit an event, just acknowledge we received data
      // Send an empty message event to signal activity (transmit.dart will track this)
      _messageController.add(MessageEvent(
        data: null, // Empty data indicates heartbeat
        event: null,
        id: null,
      ));
      return;
    }

    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) {
      // No colon, treat as field name with empty value
      _processField(line, '');
      return;
    }

    final field = line.substring(0, colonIndex).trim();
    var value = line.substring(colonIndex + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    _processField(field, value);
  }

  void _processField(String field, String value) {
    switch (field) {
      case 'data':
        if (_dataBuffer.isNotEmpty) {
          _dataBuffer.write('\n');
        }
        _dataBuffer.write(value);
        break;
      case 'event':
        _eventType = value;
        break;
      case 'id':
        _lastEventId = value;
        break;
      case 'retry':
        // Ignore retry for now
        break;
    }
  }

  Stream<MessageEvent> get stream => _messageController.stream;
  Stream<void> get onOpen => _openController.stream;
  Stream<void> get onError => _errorController.stream;
  Future<void> get ready => _readyCompleter.future;

  void close() {
    _closed = true;
    _cleanup();
    _messageController.close();
    _openController.close();
    _errorController.close();
  }
}

/// Message event wrapper for IO platform.
class MessageEvent {
  final String? data;
  final String? event;
  final String? id;

  MessageEvent({this.data, this.event, this.id});
}

/// Export EventSourceIO as EventSourceStub for conditional imports.
typedef EventSourceStub = EventSourceIO;

