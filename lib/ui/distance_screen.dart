import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';

class DistanceScreen extends StatefulWidget {
  const DistanceScreen({super.key});

  @override
  DistanceScreenState createState() => DistanceScreenState();
}

class DistanceScreenState extends State<DistanceScreen> {
  double _distance = 0.0;
  Color _displayColor = Colors.green;
  String _warningText = "SAFE";

  @override
  void initState() {
    super.initState();
    // Start MQTT service here
    MQTTService(this);
  }

  // Called by MQTTService to update UI
  void updateDistance(double dist) {
    setState(() {
      _distance = dist;

      if (dist < 2) {
        _displayColor = Colors.red;
        _warningText = "DANGER!";
      } else if (dist >= 2 && dist < 8) {
        _displayColor = Colors.yellow;
        _warningText = "CAUTION!";
      } else {
        _displayColor = Colors.green;
        _warningText = "SAFE";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _displayColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _warningText,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Distance: ${_distance.toStringAsFixed(2)} m',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
