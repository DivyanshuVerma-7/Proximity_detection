import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProximityPage extends StatefulWidget {
  const ProximityPage({super.key});

  @override
  State<ProximityPage> createState() => _ProximityPageState();
}

class _ProximityPageState extends State<ProximityPage> {
  Map<String, dynamic>? result;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchResults();
  }

  Future<void> fetchResults() async {
    try {
      final data = await ApiService.getProximityResults();
      setState(() {
        result = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Proximity Detection")),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : result == null
                ? const Text("Failed to load data")
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Objects Detected: ${result!['objects_detected']}"),
                      const SizedBox(height: 10),
                      Text(
                        result!['proximity_alert']
                            ? "⚠️ Proximity Alert!"
                            : "✅ Safe",
                        style: TextStyle(
                          color: result!['proximity_alert']
                              ? Colors.red
                              : Colors.green,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
