import 'package:flutter_test/flutter_test.dart';
void main() { test('Base configuration is HTTPS', () { const url = String.fromEnvironment('SCL_API_URL', defaultValue: 'https://api.smartcarlock.ir'); expect(url.startsWith('https://'), isTrue); }); }
