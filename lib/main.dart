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
      title: 'OPL ISO Utility',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F141D), 
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161E2E),
          elevation: 4,
          titleTextStyle: TextStyle(
            color: Color(0xFF4C9EFF), 
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      home: const OplConverterPage(),
    );
  }
}

class OplConverterPage extends StatefulWidget {
  const OplConverterPage({super.key});

  @override
  State<OplConverterPage> createState() => _OplConverterPageState();
}

class _OplConverterPageState extends State<OplConverterPage> {
  String _statusMessage = "READY: CHOOSE AN ISO GAME FILE TO SPLIT";
  bool _isConverting = false;
  double _progressValue = 0.0;
  String _selectedGameName = "No ISO Loaded";

  Future<void> _processIsoWithTracking() async {
    // 1. Pick the Input ISO File
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['iso'],
    );

    if (result == null || result.files.single.path == null) {
      setState(() { _statusMessage = "ERROR: ISO SELECTION CANCELED"; });
      return;
    }

    final String isoPath = result.files.single.path!;
    final File sourceIso = File(isoPath);
    final String baseName = result.files.single.name.replaceAll('.iso', '');

    setState(() {
      _selectedGameName = baseName;
      _statusMessage = "CHOOSE WHERE TO SAVE THE CONVERTED UL FILES...";
    });

    // 2. Select Output Folder to Bypass Storage Permissions Safely
    String? targetDirectory = await FilePicker.platform.getDirectoryPath();

    if (targetDirectory == null) {
      setState(() { _statusMessage = "ERROR: OUTPUT FOLDER NOT SELECTED"; });
      return;
    }

    setState(() {
      _isConverting = true;
      _progressValue = 0.0;
      _statusMessage = "OPENING ISO FILE SEGMENTS...";
    });

    try {
      final int totalFileBytes = await sourceIso.length();
      const int targetChunkLimit = 1024 * 1024 * 1024; // 1 GB chunks
      
      String formattedGameTitle = baseName;
      if (formattedGameTitle.length > 32) formattedGameTitle = formattedGameTitle.substring(0, 32);
      formattedGameTitle = formattedGameTitle.padRight(32, ' ');
      
      // Default PS2 System identifier template string
      const String operationalId = "SLUS_123.45"; 
      
      final RandomAccessFile filePointer = await sourceIso.open(mode: FileMode.read);
      int bytesProcessed = 0;
      int sliceIndex = 0;

      // Real File Splitting Data Loop Execution Engine
      while (bytesProcessed < totalFileBytes) {
        final int batchRemainder = (bytesProcessed + targetChunkLimit > totalFileBytes) 
            ? (totalFileBytes - bytesProcessed) 
            : targetChunkLimit;

        final String sequentialLabel = sliceIndex.toString().padLeft(2, '0');
        setState(() {
          _statusMessage = "WRITING REAL STORAGE FILE: ul.$operationalId.$sequentialLabel";
        });

        // Binary buffer extraction logic
        final Uint8List dataSegment = await filePointer.read(batchRemainder);
        final File segmentOutput = File('$targetDirectory/ul.$operationalId.$sequentialLabel');
        await segmentOutput.writeAsBytes(dataSegment, flush: true);

        bytesProcessed += batchRemainder;
        sliceIndex++;

        setState(() {
          _progressValue = bytesProcessed / totalFileBytes;
        });
      }
      await filePointer.close();

      // Write matching ul.cfg config descriptor binary block
      setState(() { _statusMessage = "GENERATING OPL COMPATIBLE UL.CFG CONFIG FILE..."; });
      
      final Uint8List descriptorMapBytes = Uint8List(64);
      final ByteData structuredView = ByteData.sublistView(descriptorMapBytes);

      final List<int> processedTitleAscii = formattedGameTitle.codeUnits;
      for (int i = 0; i < 32; i++) {
        descriptorMapBytes[i] = i < processedTitleAscii.length ? processedTitleAscii[i] : 32;
      }

      final List<int> processedIdAscii = operationalId.codeUnits;
      for (int i = 0; i < 15; i++) {
        descriptorMapBytes[32 + i] = i < processedIdAscii.length ? processedIdAscii[i] : 0;
      }

      structuredView.setUint32(48, sliceIndex, Endian.little);

      final File configurationIndex = File('$targetDirectory/ul.cfg');
      await configurationIndex.writeAsBytes(descriptorMapBytes, flush: true);

      setState(() {
        _progressValue = 1.0;
        _statusMessage = "SUCCESS: ALL CHUNKS AND UL.CFG CREATED IN OUTPUT FOLDER!";
      });
    } catch (failureTrace) {
      setState(() {
        _statusMessage = "FATAL WRITE EXCEPTION: ${failureTrace.toString().toUpperCase()}";
      });
    } finally {
      setState(() {
        _isConverting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("OPEN PS2 LOADER UTILITY"),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F141D), Color(0xFF07090E)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "SELECTED TARGET COMPONENT:",
                      style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedGameName.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 40),
                    
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressValue,
                        minHeight: 12,
                        backgroundColor: const Color(0xFF1A2333),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4C9EFF)), 
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(color: Color(0xFF00FFCC), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "${(_progressValue * 100).toStringAsFixed(0)}%",
                          style: const TextStyle(color: Color(0xFF4C9EFF), fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            Container(
              color: const Color(0xFF111622),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.gamepad, color: Colors.grey, size: 16),
                      SizedBox(width: 6),
                      Text("BDM USB GAMES", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  
                  ElevatedButton.icon(
                    onPressed: _isConverting ? null : _processIsoWithTracking,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(_isConverting ? "CONVERTING" : "START CONVERSION"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C9EFF),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: const Color(0xFF1E293B),
                      disabledForegroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
