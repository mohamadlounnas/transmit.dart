/*
 * transmit_client
 *
 * (c) mohamed lounnas <mohamad@feeef.org>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

import 'dart:async';
import 'http_client.dart';
import 'hook.dart';
import 'subscription_status.dart';
import 'transmit_status.dart';

/// Options for creating a subscription.
class SubscriptionOptions {
  final String channel;
  final TransmitHttpClient httpClient;
  final TransmitStatus Function() getEventSourceStatus;
  final Hook? hooks;
  final void Function(String channel)? onDeleted;

  SubscriptionOptions({
    required this.channel,
    required this.httpClient,
    required this.getEventSourceStatus,
    this.hooks,
    this.onDeleted,
  });
}

/// A subscription to a channel.
class Subscription {
  final TransmitHttpClient _httpClient;
  final Hook? _hooks;
  final String _channel;
  final TransmitStatus Function() _getEventSourceStatus;
  final void Function(String channel)? _onDeleted;
  final Set<void Function(dynamic)> _handlers = {};
  final StreamController<dynamic> _messageStreamController = StreamController<dynamic>.broadcast();
  SubscriptionStatus _status = SubscriptionStatus.pending;

  Subscription(SubscriptionOptions options)
      : _httpClient = options.httpClient,
        _hooks = options.hooks,
        _channel = options.channel,
        _getEventSourceStatus = options.getEventSourceStatus,
        _onDeleted = options.onDeleted;
  
  /// Returns the channel name for this subscription.
  String get channel => _channel;

  /// Returns if the subscription is created or not.
  bool get isCreated => _status == SubscriptionStatus.created;

  /// Returns if the subscription is deleted or not.
  bool get isDeleted => _status == SubscriptionStatus.deleted;

  /// Returns the number of registered handlers.
  int get handlerCount => _handlers.length;

  /// Run all registered handlers for the subscription.
  /// This is an internal method exposed for testing.
  void $runHandler(dynamic message) {
    // Emit to stream first
    if (!_messageStreamController.isClosed) {
      _messageStreamController.add(message);
    }
    
    // Then run callbacks (iterate over a snapshot to allow handlers to remove themselves safely)
    for (final handler in List<void Function(dynamic)>.from(_handlers)) {
      handler(message);
    }
  }

  /// Get a stream of messages for this subscription.
  /// This is the idiomatic Dart way to listen for messages.
  /// 
  /// Example:
  /// ```dart
  /// subscription.stream.listen((message) {
  ///   print('Received: $message');
  /// });
  /// ```
  /// 
  /// For Flutter, you can use StreamBuilder:
  /// ```dart
  /// StreamBuilder(
  ///   stream: subscription.stream,
  ///   builder: (context, snapshot) {
  ///     if (snapshot.hasData) {
  ///       return Text('Message: ${snapshot.data}');
  ///     }
  ///     return CircularProgressIndicator();
  ///   },
  /// )
  /// ```
  Stream<dynamic> get stream => _messageStreamController.stream;

  /// Get a typed stream of messages for this subscription.
  /// 
  /// Example:
  /// ```dart
  /// subscription.streamAs<Map<String, dynamic>>().listen((message) {
  ///   print('User: ${message['user']}');
  /// });
  /// ```
  Stream<T> streamAs<T>() => _messageStreamController.stream.cast<T>();

  /// Create the subscription on the server.
  Future<void> create() async {
    if (isCreated) {
      return;
    }
    return forceCreate();
  }

  /// Force create the subscription, waiting for connection if needed.
  Future<void> forceCreate() async {
    if (_getEventSourceStatus() != TransmitStatus.connected) {
      await Future.delayed(const Duration(milliseconds: 100));
      return create();
    }

    final request = _httpClient.createRequest('/__transmit/subscribe', {
      'channel': _channel,
    });

    _hooks?.beforeSubscribe(request);

    try {
      final response = await _httpClient.send(request);

      // Dump the response text
      await response.body;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _hooks?.onSubscribeFailed(response);
        return;
      }

      _status = SubscriptionStatus.created;
      _hooks?.onSubscription(_channel);
    } catch (error) {
      // Error handling
    }
  }

  /// Delete the subscription from the server.
  Future<void> delete() async {
    if (isDeleted || !isCreated) {
      return;
    }

    final request = _httpClient.createRequest('/__transmit/unsubscribe', {
      'channel': _channel,
    });

    _hooks?.beforeUnsubscribe(request);

    try {
      final response = await _httpClient.send(request);

      // Dump the response text
      await response.body;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      _status = SubscriptionStatus.deleted;
      _hooks?.onUnsubscription(_channel);
      
      // Notify Transmit to remove this subscription from its internal map
      _onDeleted?.call(_channel);
      
      // Close the stream controller when subscription is deleted
      if (!_messageStreamController.isClosed) {
        _messageStreamController.close();
      }
    } catch (error) {
      // Error handling
    }
  }

  /// Register a message handler. Returns a function to unsubscribe.
  void Function() onMessage<T>(void Function(T) handler) {
    _handlers.add(handler as void Function(dynamic));
    return () {
      _handlers.remove(handler);
    };
  }

  /// Register a message handler that runs only once.
  void onMessageOnce<T>(void Function(T) handler) {
    void Function()? deleteHandler;
    deleteHandler = onMessage<T>((message) {
      handler(message);
      deleteHandler?.call();
    });
  }
}

