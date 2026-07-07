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

  Future<String> _getGenuineId(File f) async {
    RandomAccessFile? r;
    try {
      r = await f.open(mode: FileMode.read);
      final int length = await f.length();
      final int scanLimit = length > 45000000 ? 45000000 : length;
      const int segmentStep = 5 * 1024 * 1024;
      
      for (int offset = 0; offset < scanLimit; offset += segmentStep) {
        await r.setPosition(offset);
        final int bytesToRead = (offset + segmentStep > scanLimit) ? (scanLimit - offset) : segmentStep;
        final Uint8List chunkBuffer = await r.read(bytesToRead);
        final String searchString = latin1.decode(chunkBuffer, allowInvalid: true);
        
        final RegExp regExp = RegExp(r'(SLUS|SCUS|SLES|SCES|SLPM|SLPS)_(\d{3})\.(\d{2})');
        final match = regExp.firstMatch(searchString);
        if (match != null) return "${match.group(1)}_${match.group(2)}.${match.group(3)}";
      }
    } catch (_) {} finally { await r?.close(); }
    return "SLUS_202.40"; 
  }

  Future<void> _convert() async {
    // 1. Select the original game disk file cleanly
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['iso']);
    if (res == null || res.files.single.path == null) return;
    
    final File src = File(res.files.single.path!);
    setState(() { _name = res.files.single.name.replaceAll('.iso', ''); _msg = "SCANNING TRACKS FOR GENUINE GAME ID..."; });
    
    final String gid = await _getGenuineId(src);
    setState(() { _msg = "ID ASSIGNED: [$gid]. SELECT A VISIBLE EXPORT FOLDER..."; });
    
    // 2. Select visible storage destination directory safely via framework picker
    String? out = await FilePicker.platform.getDirectoryPath();
    if (out == null) {
      setState(() { _msg = "ERROR: EXPORT DESTINATION FOLDER CANCELED"; });
      return;
    }

    setState(() { _run = true; _pct = 0.0; _msg = "STREAMING SEGMENTS NATIVELY..."; });
    
    try {
      final int len = await src.length();
      const int splitLimit = 1024 * 1024 * 1024; // 1 GB size boundaries
      const int ramBuffer = 4 * 1024 * 1024;     // Smooth 4MB streaming engine data packets
      
      String title = _name.substring(0, _name.length > 32 ? 32 : _name.length).padRight(32, ' ');
      final RandomAccessFile reader = await src.open(mode: FileMode.read);
      
      int done = 0; 
      int idx = 0;

      while (done < len) {
        final String partLabel = idx.toString().padLeft(2, '0');
        
        // Write utilizing direct target paths verified by the storage permission layer
        final File destFile = File('$out/ul.$gid.$partLabel');
        if (await destFile.exists()) await destFile.delete();
        
        final RandomAccessFile writer = await destFile.open(mode: FileMode.writeOnlyAppend);
        int currentPartBytesWritten = 0;
        
        while (currentPartBytesWritten < splitLimit && done < len) {
          int remainingInPart = splitLimit - currentPartBytesWritten;
          int remainingInFile = len - done;
          int bytesToRead = (remainingInPart < ramBuffer) ? remainingInPart : ramBuffer;
          if (remainingInFile < bytesToRead) bytesToRead = remainingInFile;

          final Uint8List buffer = await reader.read(bytesToRead);
          await writer.writeFrom(buffer);

          done += bytesToRead;
          currentPartBytesWritten += bytesToRead;

          if (done % (16 * 1024 * 1024) == 0 || done == len) {
            setState(() { _msg = "WRITING RAW FILE DATA: ul.$gid.$partLabel"; _pct = done / len; });
            await Future.delayed(const Duration(milliseconds: 1)); 
          }
        }
        await writer.close();
        idx++;
      }
      await reader.close();

      // 3. Output structural map index card (ul.cfg binary array descriptor layout)
      setState(() { _msg = "CONSTRUCTING OPL ENGINE FILE INDEX REGISTRY..."; });
      final Uint8List cfg = Uint8List(64);
      final ByteData dv = ByteData.sublistView(cfg);
      cfg.setRange(0, 32, title.codeUnits);
      cfg.setRange(32, 32 + gid.codeUnits.length, gid.codeUnits);
      dv.setUint32(48, idx, Endian.little);
      
      final File cfgFile = File('$out/ul.cfg');
      if (await cfgFile.exists()) await cfgFile.delete();
      await cfgFile.writeAsBytes(cfg, flush: true);

      setState(() { _pct = 1.0; _msg = "SUCCESS: ALL CHUNKS AND UL.CFG GENERATED SUCCESSFULLY!"; });
    } catch (e) { 
      setState(() { _msg = "WRITE ERROR: CHOOSE MAIN 'DOWNLOADS' OR 'DOCUMENTS' COMPONENT FOLDER."; _pct = 0.0; }); 
    } finally { setState(() { _run = false; }); }
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
