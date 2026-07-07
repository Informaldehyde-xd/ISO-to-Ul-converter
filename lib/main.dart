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
      await r.setPosition(32768);
      final String txt = latin1.decode(await r.read(65536), allowInvalid: true);
      final m = RegExp(r'([A-Z]{4})_(\d{3})\.(\d{2})').firstMatch(txt);
      if (m != null) return "${m.group(1)}_${m.group(2)}.${m.group(3)}";
    } catch (_) {} finally { await r?.close(); }
    return "SLUS_000.00";
  }

  Future<void> _convert() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['iso']);
    if (res == null || res.files.single.path == null) return;
    
    final File src = File(res.files.single.path!);
    setState(() { _name = res.files.single.name.replaceAll('.iso', ''); _msg = "SCANNING FOR GAME ID..."; });
    
    final String gid = await _getId(src);
    setState(() { _msg = "ID FOUND: [$gid]. CHOOSE OUTPUT DESTINATION..."; });
    
    String? out = await FilePicker.platform.getDirectoryPath();
    if (out == null) return;

    setState(() { _run = true; _pct = 0.0; _msg = "OPENING ISO FILE TRACKS..."; });
    try {
      final int len = await src.length();
      const int limit = 1024 * 1024 * 1024;
      String title = _name.substring(0, _name.length > 32 ? 32 : _name.length).padRight(32, ' ');
      
      final RandomAccessFile ptr = await src.open(mode: FileMode.read);
      int done = 0; int idx = 0;

      while (done < len) {
        final int rem = (done + limit > len) ? (len - done) : limit;
        final String lbl = idx.toString().padLeft(2, '0');
        await Future.delayed(const Duration(milliseconds: 10));
        
        setState(() { _msg = "WRITING PART $lbl FOR GAME CODE: $gid"; _pct = done / len; });
        final Uint8List chunk = await ptr.read(rem);
        await File('$out/ul.$gid.$lbl').writeAsBytes(chunk, flush: true);
        done += rem; idx++;
      }
      await ptr.close();

      setState(() { _msg = "GENERATING OPL MASTER UL.CFG MAP..."; });
      final Uint8List cfg = Uint8List(64);
      final ByteData dv = ByteData.sublistView(cfg);
      cfg.setRange(0, 32, title.codeUnits);
      cfg.setRange(32, 32 + gid.codeUnits.length, gid.codeUnits);
      dv.setUint32(48, idx, Endian.little);
      await File('$out/ul.cfg').writeAsBytes(cfg, flush: true);

      setState(() { _pct = 1.0; _msg = "SUCCESS: ALL CHUNKS GENERATED SAFELY!"; });
    } catch (e) { setState(() { _msg = "WRITE ERROR: ${e.toString().toUpperCase()}"; _pct = 0.0; }); }
    finally { setState(() { _run = false; }); }
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
