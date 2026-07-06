import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const ConverterPage(),
    );
  }
}

class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  String _status = "Select a PS2 ISO file to begin conversion.";
  bool _isProcessing = false;

  Future<void> _convertIso() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['iso'],
    );

    if (result == null || result.files.single.path == null) {
      setState(() {
        _status = "No file selected.";
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "Analyzing ISO file...";
    });

    try {
      final isoFile = File(result.files.single.path!);
      final outputDir = isoFile.parent.path;
      final totalSize = await isoFile.length();
      
      // Fixed 1 GB chunk size configuration
      const int chunkSize = 1024 * 1024 * 1024; 
      
      // Format configurations for standard USBUtil layout
      String cleanName = result.files.single.name.replaceAll('.iso', '');
      if (cleanName.length > 32) cleanName = cleanName.substring(0, 32);
      cleanName = cleanName.padRight(32, ' ');
      
      const String gameId = "SLUS_123.45"; 
      
      final raf = await isoFile.open(mode: FileMode.read);
      int offset = 0;
      int chunkIdx = 0;

      while (offset < totalSize) {
        setState(() {
          _status = "Writing segment part ${chunkIdx + 1}...";
        });

        final currentChunkSize = (offset + chunkSize > totalSize) 
            ? (totalSize - offset) 
            : chunkSize;

        final bytes = await raf.read(currentChunkSize);
        
        final partPad = chunkIdx.toString().padLeft(2, '0');
        final outPartFile = File('$outputDir/ul.$gameId.$partPad');
        await outPartFile.writeAsBytes(bytes, flush: true);

        offset += currentChunkSize;
        chunkIdx++;
      }
      await raf.close();

      // Offline creation of matching 64-byte structured ul.cfg file
      setState(() {
        _status = "Finalizing configuration index map...";
      });

      final cfgBytes = Uint8List(64);
      final byteData = ByteData.sublistView(cfgBytes);

      List<int> nameEncoded = cleanName.codeUnits;
      for (int i = 0; i < 32; i++) {
        cfgBytes[i] = i < nameEncoded.length ? nameEncoded[i] : 32;
      }

      List<int> idEncoded = gameId.codeUnits;
      for (int i = 0; i < 15; i++) {
        cfgBytes[32 + i] = i < idEncoded.length ? idEncoded[i] : 0;
      }

      byteData.setUint32(48, chunkIdx, Endian.little);

      final cfgFile = File('$outputDir/ul.cfg');
      await cfgFile.writeAsBytes(cfgBytes, flush: true);

      setState(() {
        _status = "Success! Files saved directly to your source directory.";
      });
    } catch (e) {
      setState(() {
        _status = "An error occurred: $e";
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Offline ISO Splitter")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _convertIso,
                icon: const Icon(Icons.file_open),
                label: const Text("Select & Convert ISO"),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
