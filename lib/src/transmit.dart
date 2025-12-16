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
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'http_client.dart';
import 'hook.dart';
import 'hook_event.dart';
import 'subscription.dart';
import 'transmit_status.dart';
import 'transmit_stub.dart'
    if (dart.library.html) 'transmit_web.dart'
    if (dart.library.io) 'transmit_io.dart';

/// Options for creating a Transmit client.
class TransmitOptions {
  final String baseUrl;
  final String Function()? uidGenerator;
  final dynamic Function(Uri, {bool withCredentials})? eventSourceFactory;
  final TransmitHttpClient Function(String baseUrl, String uid)? httpClientFactory;
  final void Function(http.Request)? beforeSubscribe;
  final void Function(http.Request)? beforeUnsubscribe;
  final int? maxReconnectAttempts;
  final Duration? reconnectInitialDelay;
  final Duration? reconnectMaxDelay;
  final double? reconnectBackoffMultiplier;
  final double? reconnectJitterFactor;
  final void Function(int)? onReconnectAttempt;
  final void Function()? onReconnectFailed;
  final void Function()? onReconnecting;
  final void Function()? onReconnected;
  final void Function()? onDisconnected;
  final void Function(http.Response)? onSubscribeFailed;
  final void Function(String)? onSubscription;
  final void Function(String)? onUnsubscription;

  TransmitOptions({
    required this.baseUrl,
    this.uidGenerator,
    this.eventSourceFactory,
    this.httpClientFactory,
    this.beforeSubscribe,
    this.beforeUnsubscribe,
    this.maxReconnectAttempts,
    this.reconnectInitialDelay,
    this.reconnectMaxDelay,
    this.reconnectBackoffMultiplier,
    this.reconnectJitterFactor,
    this.onReconnectAttempt,
    this.onReconnectFailed,
    this.onReconnecting,
    this.onReconnected,
    this.onDisconnected,
    this.onSubscribeFailed,
    this.onSubscription,
    this.onUnsubscription,
  });
}

/// Main Transmit client class.
class Transmit {
  final String _uid;
  final TransmitOptions _options;
  final Map<String, Subscription> _subscriptions = {};
  late final TransmitHttpClient _httpClient;
  final Hook _hooks;
  TransmitStatus _status = TransmitStatus.initializing;
  dynamic _eventSource;
  StreamSubscription<MessageEvent>? _messageSubscription;
  StreamSubscription<void>? _openSubscription;
  StreamSubscription<void>? _errorSubscription;
  final StreamController<TransmitStatus> _statusController = StreamController<TransmitStatus>.broadcast();
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  bool _isClosed = false;
  DateTime? _nextRetryTime;
  void Function()? _onReconnectingCallback;
  void Function()? _onReconnectedCallback;
  void Function()? _onDisconnectedCallback;

  /// Returns the unique identifier of the client.
  String get uid => _uid;

  /// Returns whether the client is currently reconnecting.
  bool get isReconnecting => _isReconnecting;

  /// Returns the current number of reconnect attempts.
  int get reconnectAttempts => _reconnectAttempts;

  /// Returns the timestamp when the next reconnect attempt will occur, or null if not reconnecting.
  DateTime? get nextRetryTime => _nextRetryTime;

  /// Returns whether the client is currently connected.
  bool get isConnected => _status == TransmitStatus.connected;

  static final _uuid = Uuid();

  /// Returns the status stream.
  Stream<TransmitStatus> get statusStream => _statusController.stream;

  /// Create a new Transmit client.
  Transmit(TransmitOptions options)
      : _options = options,
        _uid = options.uidGenerator?.call() ?? _uuid.v4(),
        _hooks = Hook() {
    // Initialize HTTP client after _uid is set
    _httpClient =
        options.httpClientFactory?.call(options.baseUrl, _uid) ?? TransmitHttpClient(baseUrl: options.baseUrl, uid: _uid);
    // Register hooks
    if (options.beforeSubscribe != null) {
      _hooks.register(HookEvent.beforeSubscribe, options.beforeSubscribe!);
    }
    if (options.beforeUnsubscribe != null) {
      _hooks.register(HookEvent.beforeUnsubscribe, options.beforeUnsubscribe!);
    }
    if (options.onReconnectAttempt != null) {
      _hooks.register(HookEvent.onReconnectAttempt, options.onReconnectAttempt!);
    }
    if (options.onReconnectFailed != null) {
      _hooks.register(HookEvent.onReconnectFailed, options.onReconnectFailed!);
    }
    // Store callbacks that are not hooks (they're called directly)
    if (options.onReconnecting != null) {
      _onReconnectingCallback = options.onReconnecting!;
    }
    if (options.onReconnected != null) {
      _onReconnectedCallback = options.onReconnected!;
    }
    if (options.onDisconnected != null) {
      _onDisconnectedCallback = options.onDisconnected!;
    }
    if (options.onSubscribeFailed != null) {
      _hooks.register(HookEvent.onSubscribeFailed, options.onSubscribeFailed!);
    }
    if (options.onSubscription != null) {
      _hooks.register(HookEvent.onSubscription, options.onSubscription!);
    }
    if (options.onUnsubscription != null) {
      _hooks.register(HookEvent.onUnsubscription, options.onUnsubscription!);
    }

    _connect();
  }

  /// Change the status and emit an event.
  void _changeStatus(TransmitStatus status) {
    final previousStatus = _status;
    _status = status;
    _statusController.add(status);

    // Call callbacks for specific status transitions
    if (status == TransmitStatus.disconnected && previousStatus != TransmitStatus.disconnected) {
      _onDisconnectedCallback?.call();
    } else if (status == TransmitStatus.reconnecting && previousStatus != TransmitStatus.reconnecting) {
      _onReconnectingCallback?.call();
    } else if (status == TransmitStatus.connected && previousStatus == TransmitStatus.reconnecting) {
      _onReconnectedCallback?.call();
    }
  }

  /// Connect to the server.
  Future<void> _connect() async {
    if (_isClosed) {
      return;
    }

    // Reset reconnecting flag when we start a connection attempt
    // This allows _onError to schedule a new reconnect if this attempt fails
    final wasReconnecting = _isReconnecting;
    _isReconnecting = false;

    _changeStatus(TransmitStatus.connecting);

    // Clean up previous connection
    await _cleanupConnection();

    final url = Uri.parse('${_options.baseUrl}/__transmit/events').replace(queryParameters: {'uid': _uid});

    try {
      if (_options.eventSourceFactory != null) {
        _eventSource = _options.eventSourceFactory!(url, withCredentials: true);
      } else {
        // Use platform-specific EventSource (IO or Web)
        _eventSource = EventSourceStub(url, withCredentials: true);
      }

      // Wait for ready (for IO, this is async; for web, it's also async)
      await _eventSource.ready;

      if (_isClosed) {
        await _cleanupConnection();
        return;
      }

      _changeStatus(TransmitStatus.connected);
      _reconnectAttempts = 0;
      _isReconnecting = false;
      _nextRetryTime = null;

      await _reRegisterSubscriptions();

      // Listen to messages
      _messageSubscription = _eventSource.stream.listen(
        _onMessage,
        onError: _onError,
        cancelOnError: false,
      );

      // Listen to open events
      _openSubscription = _eventSource.onOpen.listen((_) async {
        if (_isClosed) return;
        _changeStatus(TransmitStatus.connected);
        _reconnectAttempts = 0;
        _isReconnecting = false;
        _nextRetryTime = null;
        await _reRegisterSubscriptions();
      });

      // Listen to error events
      _errorSubscription = _eventSource.onError.listen((_) {
        _onError(null);
      });
    } catch (error) {
      if (!_isClosed) {
        // If this was a reconnect attempt that failed, allow _onError to schedule a new one
        // by ensuring _isReconnecting is false (it was reset at the start of _connect)
        _onError(error);
      } else {
        // If closed, restore the reconnecting flag if it was set
        if (wasReconnecting) {
          _isReconnecting = true;
        }
      }
    }
  }

  /// Clean up the current connection.
  Future<void> _cleanupConnection() async {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _openSubscription?.cancel();
    _openSubscription = null;
    _errorSubscription?.cancel();
    _errorSubscription = null;
    try {
      _eventSource?.close();
    } catch (e) {
      // Ignore errors during cleanup
    }
    _eventSource = null;
  }

  /// Handle incoming messages.
  void _onMessage(MessageEvent event) {
    try {
      final eventData = event.data ?? '';
      if (eventData.isEmpty) {
        return;
      }

      final data = jsonDecode(eventData) as Map<String, dynamic>;
      final channel = data['channel'] as String?;
      final payload = data['payload'];

      if (channel == null) {
        return;
      }

      final subscription = _subscriptions[channel];
      if (subscription == null) {
        return;
      }

      subscription.$runHandler(payload);
    } catch (error) {
      // Error handling - silently ignore parsing errors
    }
  }

  /// Handle connection errors.
  void _onError(dynamic error) {
    if (_isClosed) {
      return;
    }

    // Prevent multiple simultaneous reconnection attempts
    if (_isReconnecting) {
      return;
    }

    _isReconnecting = true;

    if (_status != TransmitStatus.reconnecting) {
      _changeStatus(TransmitStatus.disconnected);
    }

    _changeStatus(TransmitStatus.reconnecting);

    final maxAttempts = _options.maxReconnectAttempts ?? 5;
    if (_reconnectAttempts >= maxAttempts) {
      _isReconnecting = false;
      _nextRetryTime = null;
      _eventSource?.close();
      _hooks.onReconnectFailed();
      _changeStatus(TransmitStatus.disconnected);
      return;
    }

    _reconnectAttempts++;
    _hooks.onReconnectAttempt(_reconnectAttempts);

    // Calculate exponential backoff with jitter
    final delay = _calculateReconnectDelay(_reconnectAttempts);
    _nextRetryTime = DateTime.now().add(delay);

    // Cancel any existing reconnect timer
    _reconnectTimer?.cancel();

    // Schedule reconnect with exponential backoff
    _reconnectTimer = Timer(delay, () async {
      if (!_isClosed && _status == TransmitStatus.reconnecting) {
        _nextRetryTime = null;
        // Reset _isReconnecting here as well to ensure _onError can schedule a new attempt if this one fails
        _isReconnecting = false;
        await _connect();
      }
    });
  }

  /// Calculate the reconnect delay using exponential backoff with jitter.
  Duration _calculateReconnectDelay(int attempt) {
    // Default values
    final initialDelay = _options.reconnectInitialDelay ?? const Duration(milliseconds: 1000);
    final maxDelay = _options.reconnectMaxDelay ?? const Duration(seconds: 30);
    final multiplier = _options.reconnectBackoffMultiplier ?? 2.0;
    final jitterFactor = _options.reconnectJitterFactor ?? 0.1;

    // Calculate exponential backoff: initialDelay * (multiplier ^ (attempt - 1))
    final baseDelayMs = initialDelay.inMilliseconds * pow(multiplier, attempt - 1).round();
    
    // Apply maximum delay cap
    final cappedDelayMs = baseDelayMs.clamp(initialDelay.inMilliseconds, maxDelay.inMilliseconds);
    
    // Add jitter to prevent thundering herd problem
    final random = Random();
    final jitterRange = (cappedDelayMs * jitterFactor).round();
    final jitter = random.nextInt(jitterRange * 2 + 1) - jitterRange;
    final finalDelayMs = (cappedDelayMs + jitter).clamp(0, maxDelay.inMilliseconds);

    return Duration(milliseconds: finalDelayMs);
  }

  /// Re-register subscriptions that have already been created.
  Future<void> _reRegisterSubscriptions() async {
    for (final subscription in _subscriptions.values) {
      if (subscription.isCreated) {
        await subscription.forceCreate();
      }
    }
  }

  /// Create or get a subscription for a channel.
  Subscription subscription(String channel) {
    if (_subscriptions.containsKey(channel)) {
      return _subscriptions[channel]!;
    }

    final subscription = Subscription(SubscriptionOptions(
      channel: channel,
      httpClient: _httpClient,
      hooks: _hooks,
      getEventSourceStatus: () => _status,
    ));

    _subscriptions[channel] = subscription;
    return subscription;
  }

  /// Listen to status events.
  StreamSubscription<TransmitStatus> on(String event, void Function() callback) {
    if (event == 'connected') {
      return _statusController.stream.where((status) => status == TransmitStatus.connected).listen((_) => callback());
    } else if (event == 'disconnected') {
      return _statusController.stream
          .where((status) => status == TransmitStatus.disconnected)
          .listen((_) => callback());
    } else if (event == 'reconnecting') {
      return _statusController.stream
          .where((status) => status == TransmitStatus.reconnecting)
          .listen((_) => callback());
    }
    throw ArgumentError('Unknown event: $event');
  }

  /// Set headers that will be included in all HTTP requests.
  /// Useful for setting authentication headers when user logs in/out.
  /// [headers] - Map with header key-value pairs, or null to clear headers
  ///
  /// Example:
  /// ```dart
  /// // When user logs in
  /// transmit.setHeaders({
  ///   'Authorization': 'Bearer token-123',
  ///   'X-User-Id': '123'
  /// });
  ///
  /// // When user logs out
  /// transmit.setHeaders(null);
  /// ```
  void setHeaders(Map<String, String>? headers) {
    _httpClient.setHeaders(headers);
  }

  /// Get the current headers that are set via setHeaders.
  Map<String, String> getHeaders() {
    return _httpClient.getHeaders();
  }

  /// Force a reconnection attempt. This will cancel any pending reconnect timer
  /// and immediately attempt to reconnect.
  /// 
  /// This is useful when you detect that connectivity has been restored
  /// (e.g., using connectivity_plus in Flutter) and want to reconnect immediately
  /// instead of waiting for the next scheduled retry.
  /// 
  /// Example:
  /// ```dart
  /// // In Flutter with connectivity_plus
  /// connectivity.onConnectivityChanged.listen((result) {
  ///   if (result != ConnectivityResult.none && transmit.isReconnecting) {
  ///     transmit.reconnect();
  ///   }
  /// });
  /// ```
  Future<void> reconnect() async {
    if (_isClosed) {
      print('Transmit is closed, cannot reconnect');
      return;
    }

    // Cancel any pending reconnect timer
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _nextRetryTime = null;

    // If already connected, no need to reconnect
    if (_status == TransmitStatus.connected) {
      // return;
    }

    // Reset reconnect attempts to allow fresh reconnection
    _reconnectAttempts = 0;
    _isReconnecting = false;

    // Force immediate connection
    await _connect();
  }

  /// Close the connection.
  void close() {
    _isClosed = true;
    _isReconnecting = false;
    _nextRetryTime = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _messageSubscription?.cancel();
    _openSubscription?.cancel();
    _errorSubscription?.cancel();
    try {
      _eventSource?.close();
    } catch (e) {
      // Ignore errors during close
    }
    _statusController.close();
  }
}
