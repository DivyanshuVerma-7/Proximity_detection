// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';


// new deps
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proximity Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const ProximityDashboard(),
    );
  }
}

class Detection {
  final int id;
  final double distance;
  final String zone;
  Detection({required this.id, required this.distance, required this.zone});
}

class ProximityDashboard extends StatefulWidget {
  const ProximityDashboard({super.key});
  @override
  State<ProximityDashboard> createState() => _ProximityDashboardState();
}

class _ProximityDashboardState extends State<ProximityDashboard> with SingleTickerProviderStateMixin {
  late List<Detection> _detections;
  Timer? _pollTimer;
  late final AnimationController _pulseController;

  // WebSocket fields
  WebSocketChannel? _channel;
  bool _wsConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int maxReconnectBackoffSeconds = 30;

  // runtime-config backend host (change on device without rebuilding)
  String backendHost = "192.168.0.238:8000";
  final String emulatorAndroidHost = "10.0.2.2:8000";

  // audio player
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _playedRecently = false;
  static const int beepCooldownMs = 1500;

  // SharedPreferences key
  static const String _prefsKeyBackendHost = "backend_host";

  @override
  void initState() {
    super.initState();
    _detections = [Detection(id: 1, distance: 5.0, zone: "green")];

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    // load saved host and connect after load
    _loadSavedHost();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    _closeWebSocket();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  // ---------------------------
  // Persistence: load/save host
  // ---------------------------
  Future<void> _loadSavedHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKeyBackendHost);
      if (saved != null && saved.isNotEmpty) {
        setState(() {
          backendHost = saved;
        });
      }
    } catch (e) {
      // ignore
    } finally {
      // Attempt WebSocket connection after loading host
      _connectWebSocket();
    }
  }

  Future<void> _saveHost(String host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyBackendHost, host);
    } catch (e) {
      // ignore
    }
  }

  // ---------------------------
  // Build URIs
  // ---------------------------
  Uri buildResultsUri() {
    return Uri.parse("http://$backendHost/results");
  }

  Uri buildWsUri() {
    return Uri.parse("ws://$backendHost/ws/results");
  }

  // ---------------------------
  // Polling (fallback)
  // ---------------------------
  void _startPolling({int milliseconds = 500}) {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    _pollTimer = Timer.periodic(Duration(milliseconds: milliseconds), (_) {
      if (!_wsConnected) _fetchDetections();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ---------------------------
  // WebSocket connect / reconnect
  // ---------------------------
  void _connectWebSocket() {
    try {
      _channel?.sink.close();
    } catch (e) {}

    final uri = buildWsUri();
    try {
      _channel = WebSocketChannel.connect(uri);
      _wsConnected = true;
      _reconnectAttempt = 0;
      _stopPolling();

      _channel!.stream.listen((message) {
        _handleWsMessage(message);
      }, onError: (err) {
        _scheduleReconnect();
      }, onDone: () {
        _scheduleReconnect();
      }, cancelOnError: true);
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _wsConnected = false;
    try {
      _channel?.sink.close();
    } catch (e) {}
    _channel = null;

    _startPolling();

    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;

    final backoff = Duration(
      seconds: (_reconnectAttempt < 6) ? (1 << _reconnectAttempt) : maxReconnectBackoffSeconds,
    );
    _reconnectAttempt++;
    _reconnectTimer = Timer(backoff, () {
      _connectWebSocket();
    });
  }

  void _closeWebSocket() {
    try {
      _channel?.sink.close();
    } catch (e) {}
    _channel = null;
    _wsConnected = false;
  }

  // ---------------------------
  // Handle incoming WS messages
  // ---------------------------
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  void _handleWsMessage(dynamic message) {
    try {
      final String msgStr = message is String ? message : message.toString();
      final data = jsonDecode(msgStr) as Map<String, dynamic>;
      List<dynamic> detsJson = [];

      if (data.containsKey('frames') && data['frames'] is List && (data['frames'] as List).isNotEmpty) {
        final frame = (data['frames'] as List).first;
        if (frame is Map<String, dynamic>) {
          if (frame.containsKey('detections') && frame['detections'] is List) {
            detsJson = frame['detections'];
          } else if (frame.containsKey('cars') && frame['cars'] is List) {
            detsJson = frame['cars'];
          }
        }
      } else if (data.containsKey('detections') && data['detections'] is List) {
        detsJson = data['detections'];
      } else if (data.containsKey('cars') && data['cars'] is List) {
        detsJson = data['cars'];
      }

      final List<Detection> dets = [];
      for (int i = 0; i < detsJson.length; i++) {
        final d = detsJson[i] as Map<String, dynamic>;
        final dist = _toDouble(d['distance_m'] ?? d['distance'] ?? d['dist'] ?? d['dist_m']);
        final zone = (d['zone'] ?? d['status'] ?? 'green').toString();
        dets.add(Detection(id: i + 1, distance: dist, zone: zone));
      }

      setState(() {
        _detections = dets.isEmpty ? [Detection(id: 1, distance: 5.0, zone: "green")] : dets;
        _updatePulseAndBeep();
      });
    } catch (e) {
      debugPrint("WS parse error: $e");
    }
  }

  // ---------------------------
  // Fetching + parsing backend (HTTP fallback)
  // ---------------------------
  Future<void> _fetchDetections() async {
    try {
      final uri = buildResultsUri();
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<Detection> dets = [];
        List<dynamic>? rawDetections;
        if (data is Map<String, dynamic>) {
          if (data['detections'] != null && data['detections'] is List) {
            rawDetections = data['detections'];
          } else if (data['frames'] != null && data['frames'] is List && (data['frames'] as List).isNotEmpty) {
            final frame = (data['frames'] as List).first;
            if (frame is Map<String, dynamic> && frame['detections'] is List) {
              rawDetections = frame['detections'];
            }
          } else if (data['cars'] != null && data['cars'] is List) {
            rawDetections = data['cars'];
          }
        }

        if (rawDetections != null) {
          for (int i = 0; i < rawDetections.length; i++) {
            final d = rawDetections[i];
            final dist = _toDouble(d['distance_m'] ?? d['distance'] ?? 0);
            final zone = (d['zone'] ?? 'green').toString();
            dets.add(Detection(id: i + 1, distance: dist, zone: zone));
          }
        }

        setState(() {
          _detections = dets.isEmpty ? [Detection(id: 1, distance: 5.0, zone: "green")] : dets;
          _updatePulseAndBeep();
        });
      }
    } catch (e) {
      debugPrint("HTTP fetch error: $e");
    }
  }

  // ---------------------------
  // Pulse animation + beep logic
  // ---------------------------
  void _updatePulseAndBeep() {
    final anyRed = _detections.any((d) => d.zone == 'red');
    if (anyRed) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      _maybePlayBeep();
    } else {
      if (_pulseController.isAnimating) _pulseController.stop();
    }
  }

  void _maybePlayBeep() {
    if (_playedRecently) return;
    _playedRecently = true;
    _playBeep();
    Future.delayed(const Duration(milliseconds: beepCooldownMs), () {
      _playedRecently = false;
    });
  }

  Future<void> _playBeep() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/fbeep.mp3'));
    } catch (e) {}
  }

  // ---------------------------
  // Helpers
  // ---------------------------
  Color _colorFor(String zone) {
    switch (zone) {
      case 'red':
        return Colors.redAccent;
      case 'yellow':
        return Colors.amber;
      default:
        return Colors.greenAccent;
    }
  }

  Color _textColorFor(String zone) {
    if (zone == 'yellow') return Colors.black;
    return Colors.white;
  }

  Detection get _primaryDetection {
    final sorted = List<Detection>.from(_detections)
      ..sort((a, b) => a.distance.compareTo(b.distance));
    return sorted.first;
  }

  // ---------------------------
  // Build UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final primary = _primaryDetection;
    final zone = primary.zone;
    final distance = primary.distance;
    final screen = MediaQuery.of(context).size;
    final circleSize = (screen.width * 0.62).clamp(200.0, 320.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Proximity Detection"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openHostDialog,
            tooltip: "Set backend host",
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey[850]!),
              ),
              child: const Center(
                child: Text('Live Camera Feed',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulse = (_pulseController.value * 0.08) + 1.0;
                  final scale = zone == 'red' ? pulse : 1.0;
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    color: _colorFor(zone),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _colorFor(zone).withOpacity(0.55),
                        blurRadius: 36,
                        spreadRadius: 12,
                      )
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${distance.toStringAsFixed(1)} m',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: _textColorFor(zone),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                zone == 'red'
                    ? '⚠️ Danger — Person very close'
                    : zone == 'yellow'
                        ? '⚠️ Caution — Person nearby'
                        : '✅ Safe — No immediate danger',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Detected People',
                          style: TextStyle(color: Colors.grey[300], fontSize: 14)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _detections.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.grey),
                        itemBuilder: (context, idx) {
                          final d = _detections[idx];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _colorFor(d.zone),
                              child: Icon(Icons.person,
                                  color: _textColorFor(d.zone)),
                            ),
                            title: Text('Person ${d.id}',
                                style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${d.distance.toStringAsFixed(2)} m',
                                style: TextStyle(color: Colors.grey[400])),
                            trailing: Text(
                              d.zone.toUpperCase(),
                              style: TextStyle(
                                  color: _colorFor(d.zone),
                                  fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Monitoring surroundings...',
                  style: TextStyle(color: Colors.grey[500])),
            ),
          ],
        ),
      ),
    );
  }
  void _openHostDialog() {
    final ctrl = TextEditingController(text: backendHost);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Backend Host (host:port)"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: "e.g. 192.168.0.238:8000"),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                setState(() {
                  backendHost = val;
                });
                _saveHost(val);
                _connectWebSocket(); // reconnect immediately
              }
              Navigator.of(ctx).pop();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
