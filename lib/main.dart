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
      title: 'OPL Library Utility',
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
  bool _isIsoToUl = true; 

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

  Future<bool> _isGameAlreadyInstalled(String cfgPath, String gameId) async {
    final File file = File(cfgPath);
    if (!await file.exists()) return false;
    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length % 64 != 0) return false;
      String targetPrefix = "ul.$gameId".trim();
      for (int i = 0; i < bytes.length; i += 64) {
        final List<int> idBlock = bytes.sublist(i + 32, i + 47);
        final String existingId = latin1.decode(idBlock).split('\x00').first.trim();
        if (existingId == targetPrefix) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<String> _getGameTitleFromCfg(String cfgPath, String gameId) async {
    final File file = File(cfgPath);
    if (!await file.exists()) return "REASSEMBLED_GAME";
    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length % 64 != 0) return "REASSEMBLED_GAME";
      String targetPrefix = "ul.$gameId".trim();
      for (int i = 0; i < bytes.length; i += 64) {
        final List<int> idBlock = bytes.sublist(i + 32, i + 47);
        final String existingId = latin1.decode(idBlock).split('\x00').first.trim();
        if (existingId == targetPrefix) {
          final List<int> nameBlock = bytes.sublist(i, i + 32);
          return latin1.decode(nameBlock).split('\x00').first.trim();
        }
      }
    } catch (_) {}
    return "REASSEMBLED_GAME";
  }

  void _startProcess() {
    if (_isIsoToUl) {
      _convertIsoToUl();
    } else {
      _convertUlToIso();
    }
  }

  // Refactored ISO -> UL Converter (OPL Compatible Layout)
  Future<void> _convertIsoToUl() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['iso']);
    if (res == null || res.files.single.path == null) return;
    
    final File src = File(res.files.single.path!);
    setState(() { _name = res.files.single.name.replaceAll('.iso', ''); _msg = "SCANNING DISK TRACKS FOR GENUINE ID..."; });
    
    final String gid = await _getGenuineId(src);
    setState(() { _msg = "ID ASSIGNED: [$gid]. CHOOSE YOUR OPL ROOT USB DIRECTORY..."; });
    
    String? out = await FilePicker.platform.getDirectoryPath();
    if (out == null) return;

    final String cfgPath = '$out/ul.cfg';

    if (await _isGameAlreadyInstalled(cfgPath, gid)) {
      setState(() { _msg = "HALTED: GAME ID [$gid] IS ALREADY INSTALLED IN THIS UL.CFG MENU!"; });
      return;
    }

    setState(() { _run = true; _pct = 0.0; _msg = "INITIALIZING HIGH SPEED DATA STREAMS..."; });
    
    try {
      final int len = await src.length();
      const int splitLimit = 1024 * 1024 * 1024; 
      const int ramBuffer = 4 * 1024 * 1024;     
      
      final RandomAccessFile reader = await src.open(mode: FileMode.read);
      int done = 0; 
      int idx = 0;

      // Write sequential files using the standardized matching layout prefix (ul.GAME_ID.Part)
      while (done < len) {
        final String partLabel = idx.toString().padLeft(2, '0');
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
            setState(() { _msg = "WRITING SPLIT FILE: ul.$gid.$partLabel"; _pct = done / len; });
            await Future.delayed(const Duration(milliseconds: 1)); 
          }
        }
        await writer.close();
        idx++;
      }
      await reader.close();

      setState(() { _msg = "COMPILING FILE MAP INDEX CARD FOR MENU UPGRADE..."; });
      
      // Generate exact 64-Byte structure mapped to USBExtreme/OPL parameters
      final Uint8List newGameEntryBytes = Uint8List(64);
      
      // 1. Display Name (Bytes 0-31): ASCII Null-Padded
      String title = _name.toUpperCase();
      if (title.length > 32) title = title.substring(0, 32);
      List<int> titleBytes = title.codeUnits;
      for (int i = 0; i < 32; i++) {
        newGameEntryBytes[i] = i < titleBytes.length ? titleBytes[i] : 0x00;
      }
      
      // 2. File Target Prefix (Bytes 32-46): "ul.GAME_ID" Null-Padded
      String fullIdString = "ul.$gid";
      List<int> idBytes = fullIdString.codeUnits;
      for (int i = 0; i < 15; i++) {
        newGameEntryBytes[32 + i] = i < idBytes.length ? idBytes[i] : 0x00;
      }
      
      // 3. Number of total chunk segments (Byte 47)
      newGameEntryBytes[47] = idx; 
      
      // 4. Media Allocation identifier flag (Byte 48): 0x12 = CD, 0x14 = DVD
      newGameEntryBytes[48] = (len > 734003200) ? 0x14 : 0x12;
      
      // 5. USBExtreme Magic Identification signature (Byte 53)
      newGameEntryBytes[53] = 0x08;
      
      final File cfgFile = File(cfgPath);
      final RandomAccessFile cfgWriter = await cfgFile.open(mode: FileMode.writeOnlyAppend);
      await cfgWriter.writeFrom(newGameEntryBytes);
      await cfgWriter.close();

      setState(() { _pct = 1.0; _msg = "SUCCESS: CONFIG UPDATED! NEW GAME LINKED TO OPL MENU."; });
    } catch (e) { 
      setState(() { _msg = "WRITE ERROR: VERIFY PERMISSIONS IN EXPORT LOCATION."; _pct = 0.0; }); 
    } finally { setState(() { _run = false; }); }
  }

  // Refactored UL -> ISO Reassembler (Reads standard OPL filenames)
  Future<void> _convertUlToIso() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res == null || res.files.single.path == null) return;

    final String selectedPath = res.files.single.path!;
    final String fileName = res.files.single.name;

    if (!fileName.startsWith("ul.")) {
      setState(() { _msg = "HALTED: SELECTED FILE IS NOT A VALID OPL UL FILE!"; });
      return;
    }

    int lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot < 3) {
      setState(() { _msg = "HALTED: UNABLE TO DETECT SPLIT PART INDEX FORMAT."; });
      return;
    }

    String baseName = fileName.substring(0, lastDot + 1); 
    String srcDir = Directory(selectedPath).parent.path;

    String gameId = "";
    try {
      gameId = fileName.substring(3, lastDot); 
    } catch (_) {}

    final String cfgPath = '$srcDir/ul.cfg';
    setState(() { _msg = "SEARCHING INDEX FOR GAME METADATA..."; });
    String cleanTitle = await _getGameTitleFromCfg(cfgPath, gameId);

    setState(() { 
      _name = cleanTitle; 
      _msg = "TARGET MATCHED. CHOOSE EXPORT DIRECTORY FOR RECONSTRUCTED ISO..."; 
    });

    String? outDir = await FilePicker.platform.getDirectoryPath();
    if (outDir == null) return;

    setState(() { _run = true; _pct = 0.0; _msg = "MAPPING SEQUENTIAL FILES FROM STORAGE..."; });

    try {
      List<File> sequentialParts = [];
      int idx = 0;
      
      while (true) {
        String partLabel = idx.toString().padLeft(2, '0');
        File targetPartFile = File('$srcDir/$baseName$partLabel');
        if (await targetPartFile.exists()) {
          sequentialParts.add(targetPartFile);
          idx++;
        } else {
          break;
        }
      }

      if (sequentialParts.isEmpty) {
        setState(() { _msg = "HALTED: NO STRUCTURAL PART TRACKS ENCOUNTERED."; });
        return;
      }

      int totalTargetSize = 0;
      for (var filePart in sequentialParts) {
        totalTargetSize += await filePart.length();
      }

      File outputIso = File('$outDir/$cleanTitle.iso');
      if (await outputIso.exists()) await outputIso.delete();

      final RandomAccessFile isoWriter = await outputIso.open(mode: FileMode.writeOnlyAppend);
      int integratedBytes = 0;
      const int ramBuffer = 4 * 1024 * 1024; 

      for (int i = 0; i < sequentialParts.length; i++) {
        File currentPart = sequentialParts[i];
        String segmentName = currentPart.path.split('/').last;
        final RandomAccessFile partReader = await currentPart.open(mode: FileMode.read);
        int currentPartLength = await currentPart.length();
        int bytesReadFromPart = 0;

        while (bytesReadFromPart < currentPartLength) {
          int structuralGap = currentPartLength - bytesReadFromPart;
          int bytesToRead = (structuralGap < ramBuffer) ? structuralGap : ramBuffer;

          final Uint8List intermediateCache = await partReader.read(bytesToRead);
          await isoWriter.writeFrom(intermediateCache);

          bytesReadFromPart += bytesToRead;
          integratedBytes += bytesToRead;

          if (integratedBytes % (16 * 1024 * 1024) == 0 || integratedBytes == totalTargetSize) {
            setState(() { 
              _msg = "REASSEMBLING IMAGE DATA: $segmentName"; 
              _pct = integratedBytes / totalTargetSize; 
            });
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
        await partReader.close();
      }
      await isoWriter.close();

      setState(() { _pct = 1.0; _msg = "SUCCESS: REBUILD COMPLETE! ISO EXPORTED TO FOLDER."; });
    } catch (e) {
      setState(() { _msg = "WRITE ERROR: PIPELINE INTERRUPTED OR INSUFFICIENT MEMORY."; _pct = 0.0; });
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
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text("ISO ➔ UL CONVERTER"),
                selected: _isIsoToUl,
                onSelected: _run ? null : (selected) {
                  setState(() {
                    _isIsoToUl = true;
                    _name = "No ISO Loaded";
                    _pct = 0.0;
                    _msg = "READY: SELECT A PS2 ISO GAME FILE";
                  });
                },
                selectedColor: const Color(0xFF4C9EFF),
                labelStyle: TextStyle(color: _isIsoToUl ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text("UL ➔ ISO REASSEMBLER"),
                selected: !_isIsoToUl,
                onSelected: _run ? null : (selected) {
                  setState(() {
                    _isIsoToUl = false;
                    _name = "No UL Parts Loaded";
                    _pct = 0.0;
                    _msg = "READY: SELECT ANY SPLIT FILE EXTENSION (.00)";
                  });
                },
                selectedColor: const Color(0xFF4C9EFF),
                labelStyle: TextStyle(color: !_isIsoToUl ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isIsoToUl ? "CURRENT LOADED GAME:" : "TARGET EXTRACTION NAME:", style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
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
                  onPressed: _run ? null : _startProcess, icon: const Icon(Icons.folder_open, size: 18), 
                  label: Text(_run ? "PROCESSING" : (_isIsoToUl ? "START CONVERSION" : "REASSEMBLE ISO")),
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
