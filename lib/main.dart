import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const PortraitLightApp(),
    ),
  );
}

class PortraitLightApp extends StatefulWidget {
  const PortraitLightApp({super.key});

  @override
  State<PortraitLightApp> createState() => _PortraitLightAppState();
}

class _PortraitLightAppState extends State<PortraitLightApp> {
  @override
  void initState() {
    super.initState();
    // 应用启动后立即初始化模型
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().initModel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portrait Light',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
