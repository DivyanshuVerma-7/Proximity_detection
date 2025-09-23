import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = "http://127.0.0.1:8000"; // Change to your backend host

  static Future<Map<String, dynamic>> getProximityResults() async {
    final response = await http.get(Uri.parse('$baseUrl/results'));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load results');
    }
  }
}
