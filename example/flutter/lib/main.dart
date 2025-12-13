import 'package:flutter/material.dart';
import 'package:transmit_client/transmit.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transmit Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Transmit? _transmit;
  Subscription? _subscription;
  StreamSubscription<dynamic>? _streamSubscription;
  final List<String> _messages = [];
  String _status = 'Disconnected';
  bool _isConnected = false;
  Timer? _statusUpdateTimer;

  @override
  void initState() {
    super.initState();
    _connect();
    // Update status UI periodically to show reconnect info
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          // Trigger rebuild to update reconnect info
        });
      }
    });
  }

  void _connect() {
    setState(() {
      _status = 'Connecting...';
    });

    _transmit = Transmit(TransmitOptions(
      baseUrl: 'http://localhost:3333',
      maxReconnectAttempts: 5,
      onDisconnected: () {
        setState(() {
          _status = 'Disconnected';
          _isConnected = false;
        });
      },
      onReconnecting: () {
        setState(() {
          _status = 'Reconnecting...';
        });
      },
      onReconnected: () {
        setState(() {
          _status = 'Reconnected!';
          _isConnected = true;
        });
      },
      onReconnectAttempt: (attempt) {
        setState(() {
          _status = 'Reconnecting... (attempt $attempt)';
        });
      },
      onReconnectFailed: () {
        setState(() {
          _status = 'Reconnect failed';
          _isConnected = false;
        });
      },
    ));

    // Listen to connection events
    _transmit!.on('connected', () {
      setState(() {
        _status = 'Connected';
        _isConnected = true;
      });
    });

    _transmit!.on('disconnected', () {
      setState(() {
        _status = 'Disconnected';
        _isConnected = false;
      });
    });

    _transmit!.on('reconnecting', () {
      setState(() {
        _status = 'Reconnecting...';
      });
    });

    // Create subscription
    _subscription = _transmit!.subscription('test');

    // Listen to messages using Stream API
    _streamSubscription = _subscription!.stream.listen(
      (message) {
        setState(() {
          _messages.insert(0, '${DateTime.now().toString().substring(11, 19)} - $message');
        });
      },
      onError: (error) {
        setState(() {
          _messages.insert(0, '${DateTime.now().toString().substring(11, 19)} - Error: $error');
        });
      },
    );

    // Create subscription on server
    _subscription!.create().then((_) {
      setState(() {
        _messages.insert(0, '${DateTime.now().toString().substring(11, 19)} - Subscription created');
      });
    }).catchError((error) {
      setState(() {
        _messages.insert(0, '${DateTime.now().toString().substring(11, 19)} - Failed to create subscription: $error');
      });
    });
  }

  void _disconnect() {
    _streamSubscription?.cancel();
    _subscription?.delete();
    _transmit?.close();
    setState(() {
      _transmit = null;
      _subscription = null;
      _streamSubscription = null;
      _status = 'Disconnected';
      _isConnected = false;
    });
  }

  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    _streamSubscription?.cancel();
    _transmit?.close();
    super.dispose();
  }

  String _getReconnectInfo() {
    if (_transmit == null) return '';
    if (!_transmit!.isReconnecting) return '';
    
    final attempts = _transmit!.reconnectAttempts;
    final nextRetry = _transmit!.nextRetryTime;
    if (nextRetry == null) {
      return 'Attempt $attempts';
    }
    
    final now = DateTime.now();
    final remaining = nextRetry.difference(now);
    if (remaining.isNegative) {
      return 'Attempt $attempts (retrying now...)';
    }
    
    final seconds = remaining.inSeconds;
    if (seconds < 60) {
      return 'Attempt $attempts (next retry in ${seconds}s)';
    } else {
      final minutes = remaining.inMinutes;
      return 'Attempt $attempts (next retry in ${minutes}m ${seconds % 60}s)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Transmit Flutter Example'),
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _isConnected ? Colors.green.shade100 : Colors.red.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Status: $_status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isConnected ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                    if (_transmit != null)
                      Text(
                        'UID: ${_transmit!.uid.substring(0, 8)}...',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isConnected ? Colors.green.shade900 : Colors.red.shade900,
                        ),
                      ),
                  ],
                ),
                if (_transmit != null && _transmit!.isReconnecting) ...[
                  const SizedBox(height: 4),
                  Text(
                    _getReconnectInfo(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet.\nSend GET request to http://localhost:3333/test',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_messages[index]),
                        leading: const Icon(Icons.message, size: 20),
                      );
                    },
                  ),
          ),

          // Control buttons
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isConnected ? null : _connect,
                  icon: const Icon(Icons.connect_without_contact),
                  label: const Text('Connect'),
                ),
                if (_transmit != null && _transmit!.isReconnecting)
                  ElevatedButton.icon(
                    onPressed: () {
                      _transmit?.reconnect();
                      setState(() {
                        _status = 'Force reconnecting...';
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Force Reconnect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _disconnect : null,
                  icon: const Icon(Icons.close),
                  label: const Text('Disconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

