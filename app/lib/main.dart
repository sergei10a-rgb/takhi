// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/takhi_theme.dart';

void main() => runApp(const ProviderScope(child: TakhiApp()));

class TakhiApp extends StatelessWidget {
  const TakhiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Тахь',
    theme: takhiTheme(Brightness.light),
    darkTheme: takhiTheme(Brightness.dark),
    home: const Scaffold(body: Center(child: Text('Тахь'))),
  );
}
