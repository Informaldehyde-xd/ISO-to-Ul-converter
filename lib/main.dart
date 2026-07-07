import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

// ... [Imports and main()]

class OplConverterPage extends StatefulWidget {
  const OplConverterPage({super.key});
  @override
  State<OplConverterPage> createState() => _OplConverterPageState();
}

class _OplConverterPageState extends State<OplConverterPage> {
  // ... [State variables and simulation logic]

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OPEN PS2 LOADER UTILITY")),
      body: Container(
        decoration: const BoxDecoration(color: Color(0xFF0A0F1D)),
        child: Column(
          children: [
            Expanded(child: Center(child: Text(_selectedGameName, style: const TextStyle(color: Colors.white)))),
            LinearProgressIndicator(value: _progressValue),
            ElevatedButton(
              onPressed: _isConverting ? null : _processIsoWithTracking,
              child: Text(_isConverting ? "CONVERTING..." : "LOAD ISO"),
            ),
          ],
        ),
      ),
    );
  }
}
