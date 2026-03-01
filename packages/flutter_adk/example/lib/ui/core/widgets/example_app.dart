import 'package:flutter/material.dart';

import 'package:flutter_adk_example/ui/core/themes/app_theme.dart';
import 'package:flutter_adk_example/ui/home/widgets/examples_home_screen.dart';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter ADK Examples',
      theme: buildAppTheme(),
      home: const ExamplesHomeScreen(),
    );
  }
}
