# AdonisJS Transmit Client (Dart)

A Dart client for the native Server-Sent-Event (SSE) module of AdonisJS. This package provides a simple and powerful API to receive real-time events from AdonisJS Transmit servers.

Working on both Dart VM (dart:io) and Web (dart:web).

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Creating a Client](#creating-a-client)
  - [Subscribing to Channels](#subscribing-to-channels)
  - [Listening to Messages](#listening-to-messages)
  - [Stream API (Recommended)](#stream-api-recommended)
  - [Callback API](#callback-api)
  - [Choosing Between APIs](#choosing-between-stream-and-callback-api)
  - [Unsubscribing](#unsubscribing)
  - [Connection Events](#connection-events)
- [API Reference](#api-reference)
  - [Transmit Class](#transmit-class)
  - [TransmitOptions](#transmitoptions)
  - [Subscription Class](#subscription-class)
  - [TransmitStatus](#transmitstatus)
  - [SubscriptionStatus](#subscriptionstatus)
- [Advanced Usage](#advanced-usage)
  - [Custom UID Generation](#custom-uid-generation)
  - [Reconnection Handling](#reconnection-handling)
  - [Request Hooks](#request-hooks)
  - [Testing](#testing)
- [Platform Support](#platform-support)
- [Examples](#examples)
  - [Complete Flutter Example](#complete-flutter-example)
  - [Basic Example](#basic-example)
  - [Multiple Channels](#multiple-channels)
  - [Typed Messages](#typed-messages)
  - [Error Handling](#error-handling)
  - [Flutter Code Examples](#flutter-example-with-stream-api)
  - [Advanced Stream Composition](#advanced-stream-composition-example)
- [License](#license)

## Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  transmit_client:
    git:
      url: https://github.com/adonisjs/transmit-client
      path: main
```

Or if published to pub.dev:

```yaml
dependencies:
  transmit_client: ^1.0.0
```

Then run:

```bash
dart pub get
```

## Quick Start

### Using Stream API (Recommended)

```dart
import 'package:transmit_client/transmit.dart';

void main() async {
  // Create a Transmit client
  final transmit = Transmit(TransmitOptions(
    baseUrl: 'http://localhost:3333',
  ));

  // Wait for connection
  transmit.on('connected', () {
    print('Connected to server');
  });

  // Create a subscription
  final subscription = transmit.subscription('chat/1');

  // Listen for messages using Stream API
  subscription.stream.listen((message) {
    print('Received: $message');
  });

  // Register the subscription on the server
  await subscription.create();
}
```

### Using Callback API

```dart
import 'package:transmit_client/transmit.dart';

void main() async {
  // Create a Transmit client
  final transmit = Transmit(TransmitOptions(
    baseUrl: 'http://localhost:3333',
  ));

  // Wait for connection
  transmit.on('connected', () {
    print('Connected to server');
  });

  // Create a subscription
  final subscription = transmit.subscription('chat/1');

  // Listen for messages using Callback API
  subscription.onMessage((message) {
    print('Received: $message');
  });

  // Register the subscription on the server
  await subscription.create();
}
```

## Usage

### Creating a Client

The `Transmit` class is the main entry point for connecting to an AdonisJS Transmit server.

```dart
final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
));
```

The client automatically connects to the server when instantiated. The connection URL is constructed as `${baseUrl}/__transmit/events?uid=${uid}`.

### Subscribing to Channels

Use the `subscription` method to create or get a subscription to a channel:

```dart
final subscription = transmit.subscription('chat/1');
```

The `subscription` method returns a `Subscription` instance. If a subscription for the channel already exists, it returns the existing one.

To register the subscription on the server, call `create()`:

```dart
await subscription.create();
```

**Note:** The subscription must be created on the server before it can receive messages. However, you can register message handlers before or after calling `create()`.

### Listening to Messages

The package provides two APIs for listening to messages: **Stream API** (recommended for Dart/Flutter) and **Callback API** (for compatibility). Both work simultaneously and receive the same messages.

#### Stream API (Recommended)

The Stream API is the idiomatic Dart way to handle messages. It provides better integration with Flutter, easier composition, and more powerful error handling.

##### Basic Stream Usage

```dart
// Basic stream listening
subscription.stream.listen((message) {
  print('Message received: $message');
});
```

##### Multiple Listeners (Broadcast Stream)

The `subscription.stream` is a **broadcast stream**, meaning multiple listeners can subscribe to it simultaneously:

```dart
// Listener 1
subscription.stream.listen((message) {
  print('Listener 1: $message');
});

// Listener 2
subscription.stream.listen((message) {
  print('Listener 2: $message');
});

// Listener 3
subscription.stream.listen((message) {
  print('Listener 3: $message');
});

// All three listeners will receive the same messages!
```

##### Error Handling

Streams provide built-in error handling:

```dart
subscription.stream.listen(
  (message) {
    print('Message: $message');
  },
  onError: (error) {
    print('Error: $error');
  },
  onDone: () {
    print('Stream closed');
  },
);
```

##### Typed Streams

Use `streamAs<T>()` for type-safe message handling:

```dart
// Typed stream
subscription.streamAs<Map<String, dynamic>>().listen((message) {
  print('User: ${message['user']}');
  print('Text: ${message['text']}');
});
```

##### Stream Composition

One of the biggest advantages of the Stream API is the ability to compose and transform streams:

```dart
// Filter messages
subscription.stream
  .where((msg) => msg.toString().contains('important'))
  .listen((msg) => print('Important: $msg'));

// Transform messages
subscription.streamAs<Map<String, dynamic>>()
  .map((msg) => msg['text'] as String)
  .listen((text) => print('Text: $text'));

// Take first N messages
subscription.stream.take(5).listen((msg) {
  print('First 5: $msg');
});

// Skip first N messages
subscription.stream.skip(3).listen((msg) {
  print('After first 3: $msg');
});

// Debounce messages (wait for pause in stream)
subscription.stream
  .transform(StreamTransformer.fromHandlers(
    handleData: (data, sink) {
      // Custom transformation logic
      sink.add('Processed: $data');
    },
  ))
  .listen((msg) => print(msg));
```

##### Stream Subscription Management

You can cancel stream subscriptions:

```dart
// Store the subscription
final streamSubscription = subscription.stream.listen((message) {
  print('Message: $message');
});

// Later, cancel it
await streamSubscription.cancel();
```

##### Flutter Integration with StreamBuilder

The Stream API integrates seamlessly with Flutter's `StreamBuilder`:

```dart
StreamBuilder(
  stream: subscription.stream,
  builder: (context, snapshot) {
    if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    }
    if (snapshot.hasData) {
      return Text('Message: ${snapshot.data}');
    }
    return CircularProgressIndicator();
  },
)
```

#### Callback API

The Callback API provides a simpler, function-based approach that matches the TypeScript implementation:

##### Basic Callback Usage

```dart
subscription.onMessage((message) {
  print('Message received: $message');
});
```

##### Multiple Handlers

You can register multiple handlers on the same subscription:

```dart
subscription.onMessage((message) {
  print('Handler 1: $message');
});

subscription.onMessage((message) {
  print('Handler 2: $message');
});
```

All registered handlers will be called when a message is received.

##### One-Time Handlers

Use `onMessageOnce` to register a handler that will only be called once:

```dart
subscription.onMessageOnce((message) {
  print('This will only be called once');
});
```

After the handler is called, it's automatically removed from the subscription.

##### Typed Messages

You can specify the message type for better type safety:

```dart
subscription.onMessage<Map<String, dynamic>>((message) {
  print('User: ${message['user']}');
  print('Text: ${message['text']}');
});
```

##### Removing Handlers

The `onMessage` method returns a function to remove the handler:

```dart
final unsubscribe = subscription.onMessage((message) {
  print('Message received');
});

// Later, remove the handler
unsubscribe();
```

#### Choosing Between Stream and Callback API

**Use Stream API when:**
- Building Flutter applications (works great with `StreamBuilder`)
- You need stream composition (filtering, mapping, transforming)
- You want better error handling
- You need multiple independent listeners
- You're building idiomatic Dart code

**Use Callback API when:**
- You need compatibility with TypeScript version
- You prefer simple function callbacks
- You don't need stream composition
- You're migrating from TypeScript code

**Note:** Both APIs work simultaneously - messages are delivered to both streams and callbacks!

### Unsubscribing

#### Removing a Message Handler

The `onMessage` method returns a function that you can call to remove the handler:

```dart
final unsubscribe = subscription.onMessage((message) {
  print('Message received');
});

// Later, remove the handler
unsubscribe();
```

#### Removing a Subscription from the Server

To completely remove the subscription from the server:

```dart
await subscription.delete();
```

After calling `delete()`, the subscription will no longer receive messages from the server.

#### Closing the Connection

To close the entire connection and clean up all resources:

```dart
transmit.close();
```

This will:
- Close the SSE connection
- Cancel all subscriptions
- Clean up all resources

### Connection Events

The `Transmit` class emits events that you can listen to:

```dart
// Listen for connection
transmit.on('connected', () {
  print('Connected to server');
});

// Listen for disconnection
transmit.on('disconnected', () {
  print('Disconnected from server');
});

// Listen for reconnection attempts
transmit.on('reconnecting', () {
  print('Reconnecting...');
});
```

The `on` method returns a `StreamSubscription` that you can cancel:

```dart
final subscription = transmit.on('connected', () {
  print('Connected');
});

// Later, stop listening
subscription.cancel();
```

## API Reference

### Transmit Class

The main client class for connecting to AdonisJS Transmit servers.

#### Constructor

```dart
Transmit(TransmitOptions options)
```

Creates a new Transmit client and automatically connects to the server.

#### Properties

- `String uid` - The unique identifier for this client instance
- `bool isConnected` - Whether the client is currently connected
- `bool isReconnecting` - Whether the client is currently attempting to reconnect
- `int reconnectAttempts` - The current number of reconnect attempts
- `DateTime? nextRetryTime` - The timestamp when the next reconnect attempt will occur (null if not reconnecting)

#### Methods

- `Subscription subscription(String channel)` - Create or get a subscription for a channel
- `StreamSubscription<TransmitStatus> on(String event, void Function() callback)` - Listen to connection events
- `Future<void> reconnect()` - Force an immediate reconnection attempt (useful when connectivity is restored)
- `void setHeaders(Map<String, String>? headers)` - Set headers for all HTTP requests
- `Map<String, String> getHeaders()` - Get the current headers
- `void close()` - Close the connection and clean up resources

#### Events

- `'connected'` - Emitted when the connection is established
- `'disconnected'` - Emitted when the connection is lost
- `'reconnecting'` - Emitted when attempting to reconnect

### TransmitOptions

Configuration options for the Transmit client.

```dart
class TransmitOptions {
  final String baseUrl;                              // Required: Server base URL
  final String Function()? uidGenerator;            // Optional: Custom UID generator
  final dynamic Function(Uri, {bool withCredentials})? eventSourceFactory; // Optional: For testing
  final HttpClient Function(String, String)? httpClientFactory; // Optional: For testing
  final void Function(http.Request)? beforeSubscribe; // Optional: Hook before subscribe
  final void Function(http.Request)? beforeUnsubscribe; // Optional: Hook before unsubscribe
  final int? maxReconnectAttempts;                  // Optional: Max reconnect attempts (default: 5)
  final Duration? reconnectInitialDelay;           // Optional: Initial delay (default: 1000ms)
  final Duration? reconnectMaxDelay;                // Optional: Max delay (default: 30s)
  final double? reconnectBackoffMultiplier;         // Optional: Exponential multiplier (default: 2.0)
  final double? reconnectJitterFactor;              // Optional: Jitter factor (default: 0.1)
  final void Function(int)? onReconnectAttempt;      // Optional: Called on each reconnect attempt
  final void Function()? onReconnecting;            // Optional: Called when reconnection starts
  final void Function()? onReconnected;              // Optional: Called when reconnection succeeds
  final void Function()? onDisconnected;             // Optional: Called when disconnected
  final void Function()? onReconnectFailed;         // Optional: Called when reconnection fails
  final void Function(http.Response)? onSubscribeFailed; // Optional: Called when subscription fails
  final void Function(String)? onSubscription;       // Optional: Called when subscription succeeds
  final void Function(String)? onUnsubscription;    // Optional: Called when unsubscription succeeds
}
```

#### Options

- **`baseUrl`** (required): The base URL of the AdonisJS server (e.g., `'http://localhost:3333'`)
- **`uidGenerator`**: Custom function to generate unique client IDs. Defaults to UUID v4
- **`maxReconnectAttempts`**: Maximum number of reconnection attempts. Defaults to `5`
- **`reconnectInitialDelay`**: Initial delay before first reconnect attempt. Defaults to `1000ms`
- **`reconnectMaxDelay`**: Maximum delay between reconnect attempts. Defaults to `30s`
- **`reconnectBackoffMultiplier`**: Exponential backoff multiplier. Defaults to `2.0`
- **`reconnectJitterFactor`**: Jitter factor to prevent thundering herd (0.0-1.0). Defaults to `0.1` (±10%)
- **`onReconnectAttempt`**: Callback called on each reconnection attempt with the attempt number
- **`onReconnecting`**: Callback called when reconnection process starts
- **`onReconnected`**: Callback called when reconnection succeeds (only called when transitioning from reconnecting to connected)
- **`onDisconnected`**: Callback called when the connection is lost
- **`onReconnectFailed`**: Callback called when all reconnection attempts have failed
- **`onSubscribeFailed`**: Callback called when a subscription request fails
- **`onSubscription`**: Callback called when a subscription is successfully created
- **`onUnsubscription`**: Callback called when a subscription is successfully removed
- **`beforeSubscribe`**: Hook called before sending a subscribe request. Can modify the request
- **`beforeUnsubscribe`**: Hook called before sending an unsubscribe request. Can modify the request

### Subscription Class

Represents a subscription to a channel.

#### Properties

- `bool isCreated` - Returns `true` if the subscription is created on the server
- `bool isDeleted` - Returns `true` if the subscription has been deleted
- `int handlerCount` - Returns the number of registered message handlers

#### Methods

- `Future<void> create()` - Create the subscription on the server (idempotent)
- `Future<void> delete()` - Remove the subscription from the server
- `Stream<dynamic> get stream` - Get a broadcast stream of messages (Stream API)
- `Stream<T> streamAs<T>()` - Get a typed broadcast stream of messages
- `void Function() onMessage<T>(void Function(T) handler)` - Register a message handler. Returns an unsubscribe function (Callback API)
- `void onMessageOnce<T>(void Function(T) handler)` - Register a one-time message handler (Callback API)

#### Stream Properties

- **`stream`**: A broadcast stream that emits all messages received on this subscription. Multiple listeners can subscribe to it simultaneously.
- **`streamAs<T>()`**: Returns a typed broadcast stream. Useful for type-safe message handling.

### TransmitStatus

Enum representing the connection status of the client.

```dart
enum TransmitStatus {
  initializing,  // Client is being initialized
  connecting,   // Attempting to connect to the server
  connected,    // Successfully connected to the server
  disconnected, // Connection lost
  reconnecting, // Attempting to reconnect
}
```

### SubscriptionStatus

Enum representing the status of a subscription.

```dart
enum SubscriptionStatus {
  pending(0),  // Subscription is pending (not yet created on server)
  created(1),  // Subscription is created on the server
  deleted(2),  // Subscription is deleted (unsubscribed from server)
}
```

## Advanced Usage

### Custom UID Generation

By default, the client uses UUID v4 to generate unique identifiers. You can provide a custom generator:

```dart
final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
  uidGenerator: () => 'custom-${DateTime.now().millisecondsSinceEpoch}',
));
```

### Reconnection Handling

The client automatically reconnects when the connection is lost. You can customize the reconnection behavior:

```dart
final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
  maxReconnectAttempts: 10,
  reconnectInitialDelay: Duration(seconds: 1),
  reconnectMaxDelay: Duration(seconds: 30),
  reconnectBackoffMultiplier: 2.0,
  reconnectJitterFactor: 0.1,
  onReconnectAttempt: (attempt) {
    print('Reconnect attempt $attempt');
  },
  onReconnecting: () {
    print('Started reconnecting...');
  },
  onReconnected: () {
    print('Successfully reconnected!');
  },
  onDisconnected: () {
    print('Disconnected from server');
  },
  onReconnectFailed: () {
    print('Failed to reconnect after all attempts');
  },
));
```

When the connection is lost:
1. The client enters `reconnecting` status
2. It attempts to reconnect with exponential backoff and jitter
3. All existing subscriptions are automatically re-registered on successful reconnection
4. If all attempts fail, `onReconnectFailed` is called

#### Reconnect State Properties

You can check the reconnect state at any time:

```dart
// Check if currently reconnecting
if (transmit.isReconnecting) {
  print('Currently reconnecting...');
  print('Attempt: ${transmit.reconnectAttempts}');
  
  // Get next retry time
  final nextRetry = transmit.nextRetryTime;
  if (nextRetry != null) {
    final remaining = nextRetry.difference(DateTime.now());
    print('Next retry in: ${remaining.inSeconds} seconds');
  }
}

// Check if connected
if (transmit.isConnected) {
  print('Connected to server');
}
```

#### Force Reconnect

You can force an immediate reconnection attempt:

```dart
// Force reconnect (useful when connectivity is restored)
await transmit.reconnect();
```

#### Flutter Connectivity Integration

In Flutter apps, you can integrate with `connectivity_plus` to reconnect immediately when connectivity is restored:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:transmit_client/transmit.dart';

final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
));

// Listen to connectivity changes
final connectivity = Connectivity();
connectivity.onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) {
    // Connectivity restored - force reconnect if needed
    if (transmit.isReconnecting) {
      transmit.reconnect();
    }
  }
});
```

#### Reconnect Configuration Options

- **`maxReconnectAttempts`**: Maximum number of reconnect attempts (default: 5)
- **`reconnectInitialDelay`**: Initial delay before first reconnect (default: 1000ms)
- **`reconnectMaxDelay`**: Maximum delay between reconnects (default: 30s)
- **`reconnectBackoffMultiplier`**: Exponential multiplier (default: 2.0)
- **`reconnectJitterFactor`**: Jitter factor to prevent thundering herd (default: 0.1 = ±10%)

The delay calculation follows: `initialDelay * (multiplier ^ (attempt - 1)) + jitter`

### Request Hooks

You can modify subscription requests before they're sent:

```dart
final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
  beforeSubscribe: (request) {
    // Add custom headers
    request.headers['Authorization'] = 'Bearer token';
    request.headers['X-Custom-Header'] = 'value';
  },
  beforeUnsubscribe: (request) {
    // Modify unsubscribe request
    print('Unsubscribing from channel');
  },
));
```

### Testing

The package provides factory functions for testing:

```dart
// Create a fake event source for testing
final fakeEventSource = FakeEventSource();

final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
  eventSourceFactory: (uri, {withCredentials}) => fakeEventSource,
  httpClientFactory: (baseUrl, uid) => FakeHttpClient(),
));
```

See the test files in the `test/` directory for examples of testing with mocks.

## Platform Support

The package automatically selects the appropriate implementation based on the platform:

- **Web (dart:html / Flutter Web)**: Uses native `EventSource` API with full support for XSRF token retrieval from cookies
- **Dart VM (dart:io)**: Uses HTTP-based SSE parsing for CLI applications and servers
- **Flutter Mobile/Desktop (Android/iOS/macOS/Windows/Linux)**: Uses HTTP-based SSE parsing
  - **Android**: Ensure internet permission is granted in `AndroidManifest.xml`
  - **iOS**: May require network security configuration for non-HTTPS connections
  - All platforms: The correct implementation is automatically selected via conditional imports

### Platform-Specific Notes

#### Web Platform

On web platforms, the client automatically retrieves XSRF tokens from cookies. The token is sent in the `X-XSRF-TOKEN` header with all requests.

#### Dart IO Platform

On `dart:io` platforms, the client manually parses Server-Sent Events from HTTP streams. This works for:
- CLI applications
- Server-side Dart applications
- Flutter mobile/desktop applications

The client automatically sets the following request headers for optimal SSE performance:
- `Accept: text/event-stream`
- `Cache-Control: no-cache, no-transform`
- `Connection: keep-alive`

### SSE Anti-Buffering Headers

For optimal real-time event delivery, your server should send the following response headers:

```
Content-Type: text/event-stream
Cache-Control: no-cache, no-transform
Connection: keep-alive
X-Accel-Buffering: no  # Important for Nginx proxies
```

#### Web Platform (Browser)

**Important**: The browser's `EventSource` API does not allow setting custom request headers. The server **must** send these headers in the response. This is a browser security limitation.

#### Dart IO Platform

The client automatically sets appropriate request headers (`Accept`, `Cache-Control`, `Connection`). However, the server should still send the response headers listed above, especially `X-Accel-Buffering: no` if you're behind an Nginx proxy.

**Nginx Configuration**: If using Nginx as a reverse proxy, ensure buffering is disabled:

```nginx
location /__transmit/events {
  proxy_pass http://your_backend;
  proxy_buffering off;
  proxy_cache off;
  proxy_read_timeout 24h;
}
```

## Examples

### Basic Example

```dart
import 'package:transmit_client/transmit.dart';

void main() async {
  final transmit = Transmit(TransmitOptions(
    baseUrl: 'http://localhost:3333',
  ));

  transmit.on('connected', () {
    print('Connected');
  });

  final subscription = transmit.subscription('notifications');
  
  subscription.onMessage((message) {
    print('Notification: $message');
  });

  await subscription.create();
  
  // Keep the app running
  await Future.delayed(Duration(minutes: 10));
  
  await subscription.delete();
  transmit.close();
}
```

### Multiple Channels

```dart
final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
));

// Subscribe to multiple channels
final chatSubscription = transmit.subscription('chat/1');
final notificationsSubscription = transmit.subscription('notifications');

chatSubscription.onMessage((message) {
  print('Chat: $message');
});

notificationsSubscription.onMessage((message) {
  print('Notification: $message');
});

await Future.wait([
  chatSubscription.create(),
  notificationsSubscription.create(),
]);
```

### Typed Messages

```dart
// Define your message type
class ChatMessage {
  final String user;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.user,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      user: json['user'] as String,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

// Use typed handlers
final subscription = transmit.subscription('chat/1');

subscription.onMessage<Map<String, dynamic>>((json) {
  final message = ChatMessage.fromJson(json);
  print('${message.user}: ${message.text}');
});
```

### Error Handling

```dart
final transmit = Transmit(TransmitOptions(
  baseUrl: 'http://localhost:3333',
  onSubscribeFailed: (response) {
    print('Subscription failed: ${response.statusCode}');
  },
  onReconnectFailed: () {
    print('Failed to reconnect. Please check your connection.');
  },
));

try {
  final subscription = transmit.subscription('test');
  await subscription.create();
} catch (e) {
  print('Error: $e');
}
```

### Complete Flutter Example

A complete, runnable Flutter example is available in `example/flutter/`. To run it:

```bash
cd example/flutter
flutter pub get
flutter run
```

The example demonstrates:
- Real-time message display
- Connection status management
- Stream API integration
- Proper cleanup and resource management

### Flutter Example with Stream API

```dart
import 'package:flutter/material.dart';
import 'package:transmit_client/transmit.dart';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Transmit? _transmit;
  Subscription? _subscription;
  StreamSubscription<dynamic>? _streamSubscription;
  final List<String> _messages = [];
  String _status = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _transmit = Transmit(TransmitOptions(
      baseUrl: 'http://localhost:3333',
    ));
    
    _subscription = _transmit!.subscription('test');
    
    // Listen to messages using Stream API
    _streamSubscription = _subscription!.stream.listen((message) {
      setState(() {
        _messages.insert(0, message.toString());
      });
    });
    
    _subscription!.create();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _transmit?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Column(
        children: [
          // Status indicator
          Container(
            padding: EdgeInsets.all(16),
            color: _status == 'Connected' ? Colors.green : Colors.red,
            child: Text('Status: $_status'),
          ),
          // Messages list
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(_messages[index]));
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### Flutter Example with State Management

```dart
import 'package:flutter/material.dart';
import 'package:transmit_client/transmit.dart';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late Transmit _transmit;
  late Subscription _subscription;
  StreamSubscription<dynamic>? _streamSubscription;
  final List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _transmit = Transmit(TransmitOptions(
      baseUrl: 'http://localhost:3333',
    ));
    
    _subscription = _transmit.subscription('chat/1');
    
    // Listen to stream and update state
    _streamSubscription = _subscription.stream.listen((message) {
      setState(() {
        _messages.add(message.toString());
      });
    });
    
    _subscription.create();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _transmit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: ListView.builder(
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          return ListTile(title: Text(_messages[index]));
        },
      ),
    );
  }
}
```

### Advanced Stream Composition Example

```dart
import 'package:transmit_client/transmit.dart';

void main() async {
  final transmit = Transmit(TransmitOptions(
    baseUrl: 'http://localhost:3333',
  ));

  final subscription = transmit.subscription('notifications');

  // Example 1: Filter important notifications
  subscription.streamAs<Map<String, dynamic>>()
    .where((msg) => msg['priority'] == 'high')
    .listen((msg) {
      print('🔴 High priority: ${msg['message']}');
    });

  // Example 2: Transform and format messages
  subscription.streamAs<Map<String, dynamic>>()
    .map((msg) => '${msg['user']}: ${msg['text']}')
    .listen((formatted) {
      print('💬 $formatted');
    });

  // Example 3: Rate limiting - take only first message per second
  var lastMessageTime = DateTime.now();
  subscription.stream
    .where((_) {
      final now = DateTime.now();
      if (now.difference(lastMessageTime).inSeconds >= 1) {
        lastMessageTime = now;
        return true;
      }
      return false;
    })
    .listen((msg) {
      print('📨 (Rate limited): $msg');
    });

  // Example 4: Combine multiple subscriptions
  final chatSub = transmit.subscription('chat/1');
  final notifSub = transmit.subscription('notifications');
  
  // Merge streams using StreamController
  final mergedController = StreamController<dynamic>.broadcast();
  
  chatSub.stream.listen((msg) => mergedController.add('Chat: $msg'));
  notifSub.stream.listen((msg) => mergedController.add('Notif: $msg'));
  
  mergedController.stream.listen((msg) {
    print('Merged: $msg');
  });

  await Future.wait([
    subscription.create(),
    chatSub.create(),
    notifSub.create(),
  ]);
}
```

## License

MIT
