import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeatherData {
  final String condition;
  final double tempF;
  final double tempC;
  final int humidity;
  final String icon;
  final String city;
  final String summary;

  const WeatherData({
    required this.condition,
    required this.tempF,
    required this.tempC,
    required this.humidity,
    required this.icon,
    required this.city,
    required this.summary,
  });

  factory WeatherData.fromJson(Map<String, dynamic> j) => WeatherData(
        condition: j['condition'] ?? '',
        tempF: (j['tempF'] ?? 0).toDouble(),
        tempC: (j['tempC'] ?? 0).toDouble(),
        humidity: j['humidity'] ?? 0,
        icon: j['icon'] ?? '01d',
        city: j['city'] ?? '',
        summary: j['summary'] ?? '',
      );

  String get iconUrl =>
      'https://openweathermap.org/img/wn/$icon@2x.png';
}

class WeatherService {
  WeatherService._();
  static final instance = WeatherService._();

  WeatherData? _cached;
  DateTime? _cachedAt;

  WeatherData? get current => _cached;

  Future<WeatherData?> getWeather({
    required double lat,
    required double lon,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!).inMinutes < 30) {
      return _cached;
    }

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('getWeather');
      final result = await fn.call({'lat': lat, 'lon': lon});
      final data = WeatherData.fromJson(
          Map<String, dynamic>.from(result.data as Map));
      _cached = data;
      _cachedAt = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weather_cache', jsonEncode({
        'condition': data.condition,
        'tempF': data.tempF,
        'tempC': data.tempC,
        'humidity': data.humidity,
        'icon': data.icon,
        'city': data.city,
        'summary': data.summary,
      }));
      await prefs.setString('weather_cached_at', DateTime.now().toIso8601String());

      return data;
    } catch (e) {
      debugPrint('[Weather] Error: $e');
      return _loadCached();
    }
  }

  WeatherData? _loadCached() {
    return _cached;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('weather_cache');
      final cachedAt = prefs.getString('weather_cached_at');
      if (raw != null) {
        _cached = WeatherData.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw)));
        _cachedAt = cachedAt != null ? DateTime.parse(cachedAt) : null;
      }
    } catch (_) {}
  }
}
