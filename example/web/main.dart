/*
 * transmit_client
 *
 * (c) mohamed lounnas <mohamad@feeef.org>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:transmit_client/transmit.dart';

Transmit? transmit;
Subscription? subscription;
StreamSubscription<dynamic>? streamSubscription;

void main() {
  // Set up button event listeners
  final connectBtn = web.document.getElementById('connectBtn') as web.HTMLButtonElement?;
  final disconnectBtn = web.document.getElementById('disconnectBtn') as web.HTMLButtonElement?;
  final triggerBtn = web.document.getElementById('triggerBtn') as web.HTMLButtonElement?;
  final clearBtn = web.document.getElementById('clearBtn') as web.HTMLButtonElement?;
  
  connectBtn?.onclick = ((web.Event event) => connect()).toJS;
  disconnectBtn?.onclick = ((web.Event event) => disconnect()).toJS;
  triggerBtn?.onclick = ((web.Event event) => triggerEvent()).toJS;
  clearBtn?.onclick = ((web.Event event) => clearMessages()).toJS;
  
  // Auto-connect on page load
  connect();
}

void connect() {
  if (transmit != null) {
    addMessage('Already connected', 'info');
    return;
  }

  updateStatus('connecting', 'Connecting...');
  final connectBtn = web.document.getElementById('connectBtn') as web.HTMLButtonElement?;
  final disconnectBtn = web.document.getElementById('disconnectBtn') as web.HTMLButtonElement?;
  final triggerBtn = web.document.getElementById('triggerBtn') as web.HTMLButtonElement?;
  
  connectBtn?.disabled = true;

  transmit = Transmit(TransmitOptions(
    baseUrl: 'http://localhost:3333',
    maxReconnectAttempts: 5,
    onReconnectAttempt: (attempt) {
      addMessage('Reconnect attempt $attempt', 'warning');
    },
    onReconnectFailed: () {
      addMessage('Reconnect failed', 'error');
      updateStatus('disconnected', 'Disconnected');
    },
  ));

  // Update UID display
  final uidElement = web.document.getElementById('uid');
  if (uidElement != null) {
    uidElement.textContent = transmit!.uid;
  }

  // Listen to connection events
  transmit!.on('connected', () {
    updateStatus('connected', 'Connected');
    connectBtn?.disabled = true;
    disconnectBtn?.disabled = false;
    triggerBtn?.disabled = false;
    addMessage('Connected to server', 'success');
  });

  transmit!.on('disconnected', () {
    updateStatus('disconnected', 'Disconnected');
    connectBtn?.disabled = false;
    disconnectBtn?.disabled = true;
    triggerBtn?.disabled = true;
    addMessage('Disconnected from server', 'error');
  });

  transmit!.on('reconnecting', () {
    updateStatus('connecting', 'Reconnecting...');
    addMessage('Reconnecting...', 'warning');
  });

  // Create subscription
  subscription = transmit!.subscription('test');

  // Example 1: Using Stream API (recommended)
  streamSubscription = subscription!.stream.listen(
    (message) {
      addMessage('📨 Stream: ${message.toString()}', 'message');
    },
    onError: (error) {
      addMessage('❌ Stream error: $error', 'error');
    },
    onDone: () {
      addMessage('✅ Stream closed', 'info');
    },
  );

  // Example 2: Typed stream with filtering
  subscription!.streamAs<Map<String, dynamic>>()
    .where((msg) => msg.containsKey('type'))
    .listen((msg) {
      addMessage('📝 Typed: ${msg['type']} - ${msg['data']}', 'message');
    });

  // Example 3: Callback API (also available for compatibility)
  subscription!.onMessage((message) {
    addMessage('📞 Callback: ${message.toString()}', 'message');
  });

  // Create subscription on server
  subscription!.create().then((_) {
    addMessage('Subscription created for channel: test', 'success');
  }).catchError((error) {
    addMessage('Failed to create subscription: $error', 'error');
  });
}

void disconnect() {
  if (transmit == null) {
    return;
  }

  // Cancel stream subscription
  streamSubscription?.cancel();
  streamSubscription = null;

  // Delete subscription
  subscription?.delete();
  
  // Close connection
  transmit?.close();
  transmit = null;
  subscription = null;

  updateStatus('disconnected', 'Disconnected');
  final connectBtn = web.document.getElementById('connectBtn') as web.HTMLButtonElement?;
  final disconnectBtn = web.document.getElementById('disconnectBtn') as web.HTMLButtonElement?;
  final triggerBtn = web.document.getElementById('triggerBtn') as web.HTMLButtonElement?;
  
  connectBtn?.disabled = false;
  disconnectBtn?.disabled = true;
  triggerBtn?.disabled = true;

  addMessage('Disconnected', 'info');
}

void triggerEvent() async {
  try {
    final response = await web.window.fetch('http://localhost:3333/test'.toJS).toDart;
    if (response.status == 200) {
      addMessage('Test event triggered', 'success');
    } else {
      addMessage('Failed to trigger event: ${response.status}', 'error');
    }
  } catch (error) {
    addMessage('Error triggering event: $error', 'error');
  }
}

void clearMessages() {
  final messagesDiv = web.document.getElementById('messages');
  if (messagesDiv != null) {
    messagesDiv.innerHTML = ''.toJS;
  }
}

void updateStatus(String status, String text) {
  final statusDiv = web.document.getElementById('status');
  if (statusDiv != null) {
    statusDiv.className = 'status $status';
    statusDiv.textContent = text;
  }
}

void addMessage(String message, String type) {
  final messagesDiv = web.document.getElementById('messages');
  if (messagesDiv == null) return;

  final messageDiv = web.HTMLDivElement()
    ..className = 'message message-$type'
    ..innerHTML = '''
      <div class="message-time">${DateTime.now().toLocal().toString().substring(11, 19)}</div>
      <div class="message-content">$message</div>
    '''.toJS;

  messagesDiv.insertAdjacentElement('afterbegin', messageDiv);

  // Auto-scroll to top
  messagesDiv.scrollTop = 0;
}
