import 'package:cineshow/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cineshow/updates');
  testWidgets('mostra progresso e abre o instalador uma vez ao concluir', (tester) async {
    PackageInfo.setMockInitialValues(appName: 'CINESHOW', packageName: 'com.bichocutela.cineshow',
        version: '0.2.1', buildNumber: '3', buildSignature: 'test');
    var state = 'downloading';
    var installations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': state, 'bytes': 5242880, 'total': 10485760};
      if (call.method == 'install') { installations++; return 'installer'; }
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsPage())));
    await tester.pump();
    expect(find.text('50% · 5.0 / 10.0 MB'), findsOneWidget);
    state = 'ready';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(installations, 1);
    expect(find.text('Instalar atualização'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(installations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
