import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'ui/distance_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Distance Alert',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DistanceScreen(),
    );
  }
}

// MQTT connection and listener
class MQTTService {
  final DistanceScreenState screenState;
  late MqttServerClient client;

  MQTTService(this.screenState) {
    _connect();
  }

  void _connect() async {
    client = MqttServerClient('broker.hivemq.com', 'flutter_client_${DateTime.now().millisecondsSinceEpoch}');
    client.port = 1883;
    client.keepAlivePeriod = 30;
    client.logging(on: false);

    client.onDisconnected = () {
      print(" MQTT Disconnected — retrying in 5s...");
      Future.delayed(const Duration(seconds: 5), _connect);
    };

    try {
      print("Connecting to MQTT broker...");
      await client.connect();
      print("Connected to MQTT");

      client.subscribe('distance/topic', MqttQos.atLeastOnce);

      client.updates!.listen((messages) {
        final recMess = messages[0].payload as MqttPublishMessage;
        final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final dist = double.tryParse(pt.trim());

        if (dist != null) {
          // Update UI directly
          screenState.updateDistance(dist);
        } else {
          print("Invalid distance: $pt");
        }
      });
    } catch (e) {
      print(" MQTT connection failed: $e");
      client.disconnect();
      Future.delayed(const Duration(seconds: 5), _connect);
    }
  }
}
