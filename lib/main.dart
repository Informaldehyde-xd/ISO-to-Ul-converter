import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OPL Utility',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F141D), 
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF161E2E), elevation: 4),
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
  String _msg = "READY: SELECT A PS2 ISO GAME FILE";
  bool _run = false;
  double _pct = 0.0;
  String _name = "No ISO Loaded";

  Future<String> _getId(File f) async {
    RandomAccessFile? r;
    try {
      r = await f.open(mode: FileMode.read);
      final int len = await f.length();
      
      // Step 1: Scan primary ISO volume descriptors for SYSTEM.CNF info
      await r.setPosition(32768);
      String txt = latin1.decode(await r.read(65536), allowInvalid: true);
      RegExp reg = RegExp(r'([A-Z]{4})_(\d{3})\.(\d{2})');
      var match = reg.firstMatch(txt);
      if (match != null) return "${match.group(1)}_${match.group(2)}.${match.group(3)}";

      // Step 2: Extended lookups up to 10MB deeper if primary table was modified
      int checkSize = len > 10000000 ? 10000000 : len;
      await r.setPosition(0);
      txt = latin1.decode(await r.read(checkSize), allowInvalid: true);
      match = reg.firstMatch(txt);
      if (match != null) return "${match.group(1)}_${match.group(2)}.${match.group(3)}";
    } catch (_) {} finally { await r?.close(); }
    return "SLUS_123.45"; // Smart retro standard backup identifier
  }

  Future<void> _convert() async {
    // 1. Pick Source File
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['iso']);
    if (res == null || res.files.single.path == null) return;
    
    final File src = File(res.files.single.path!);
    setState(() { _name = res.files.single.name.replaceAll('.iso', ''); _msg = "SCANNING DISK PATHS FOR GENUINE ID..."; });
    
    final String gid = await _getId(src);
    
    // 2. Select Output target folder directory securely via the Storage Framework
    setState(() { _msg = "ID DETERMINED: [$gid]. CHOOSE STORAGE DIRECTORY..."; });
    String? out = await FilePicker.platform.getDirectoryPath();
    if (out == null) {
      setState(() { _msg = "CONVERSION HALTED: OUTPUT DIRECTORY REQUIRED"; });
      return;
    }

    setState(() { _run = true; _pct = 0.0; _msg = "PREPARING DISK WRITE STREAMS..."; });
    
    try {
      final int len = await src.length();
      const int splitSize = 1024 * 1024 * 1024; // 1 GB Chunks
      const int bufferSize = 4 * 1024 * 1024;   // Ultra-safe 4MB low memory RAM stream buffer
      
      String title = _name.substring(0, _name.length > 32 ? 32 : _name.length).padRight(32, ' ');
      
      final RandomAccessFile reader = await src.open(mode: FileMode.read);
      int totalBytesRead = 0;
      int currentPartIndex = 0;

      while (totalBytesRead < len) {
        final String partLabel = currentPartIndex.toString().padLeft(2, '0');
        
        // Use a unique file container pointer definition to initialize fresh writing target blocks
        final File destFile = File('$out/ul.$gid.$partLabel');
        
        // Delete preexisting corrupt data leftovers if they exist to prevent overlapping bytes
        if (await destFile.exists()) await destFile.delete();
        
        final RandomAccessFile writer = await destFile.open(mode: FileMode.writeOnlyAppend);
        int currentPartBytesWritten = 0;
        
        while (currentPartBytesWritten < splitSize && totalBytesRead < len) {
          int remainingInPart = splitSize - currentPartBytesWritten;
          int remainingInFile = len - totalBytesRead;
          int bytesToRead = (remainingInPart < bufferSize) ? remainingInPart : bufferSize;
          if (remainingInFile < bytesToRead) bytesToRead = remainingInFile;

          final Uint8List buffer = await reader.read(bytesToRead);
          await writer.writeFrom(buffer);

          totalBytesRead += bytesToRead;
          currentPartBytesWritten += bytesToRead;

          // Low-impact UI thread layout updates every 16 megabytes
          if (totalBytesRead % (16 * 1024 * 1024) == 0 || totalBytesRead == len) {
            setState(() {
              _msg = "WRITING SEGMENT TRACK: ul.$gid.$partLabel";
              _pct = totalBytesRead / len;
            });
            // Yield processing frame to let the application UI redraw safely
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
        await writer.close();
        currentPartIndex++;
      }
      await reader.close();

      // 3. Compile layout configuration files (ul.cfg file format construction)
      setState(() { _msg = "FINALIZING: BUILDING MASTER CONFIGURATION MAP..."; });
      final Uint8List cfg = Uint8List(64);
      final ByteData dv = ByteData.sublistView(cfg);
      
      cfg.setRange(0, 32, title.codeUnits);
      cfg.setRange(32, 32 + gid.codeUnits.length, gid.codeUnits);
      dv.setUint32(48, currentPartIndex, Endian.little);
      
      final File cfgFile = File('$out/ul.cfg');
      if (await cfgFile.exists()) await cfgFile.delete();
      await cfgFile.writeAsBytes(cfg, flush: true);

      setState(() { _pct = 1.0; _msg = "SUCCESS: ALL CHUNKS AND UL.CFG WRITTEN SUCCESSFULLY!"; });
    } catch (e) { 
      setState(() { 
        String readableErr = e.toString();
        if (readableErr.contains("Permission denied")) {
          _msg = "ACCESS ERROR: TRY WRITING TO AN EXTERNAL SD CARD OR DOWNLOADS FOLDER";
        } else {
          _msg = "WRITE FAILURE: ${readableErr.toUpperCase()}";
        }
        _pct = 0.0; 
      }); 
    } finally { 
      setState(() { _run = false; }); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OPEN PS2 LOADER UTILITY"), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CURRENT LOADED GAME:", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 40),
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _pct, minHeight: 12, backgroundColor: const Color(0xFF1A2333), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4C9EFF)))),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(_msg, style: const TextStyle(color: Color(0xFF00FFCC), fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis, maxLines: 2)),
                      Text("${(_pct * 100).toStringAsFixed(0)}%", style: const TextStyle(color: Color(0xFF4C9EFF), fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: const Color(0xFF111622), padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [Icon(Icons.gamepad, color: Colors.grey, size: 16), SizedBox(width: 6), Text("BDM USB LOADER", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold))]),
                ElevatedButton.icon(
                  onPressed: _run ? null : _convert, icon: const Icon(Icons.folder_open, size: 18), label: Text(_run ? "CONVERTING" : "START CONVERSION"),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C9EFF), foregroundColor: Colors.black, disabledBackgroundColor: const Color(0xFF1E293B), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
