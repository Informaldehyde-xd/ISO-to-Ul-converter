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

  String _generateUlHashId(String title) {
    int hash = 5381;
    String cleanTitle = title.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (int i = 0; i < cleanTitle.length; i++) {
      hash = ((hash << 5) + hash) + cleanTitle.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; 
    }
    return hash.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

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

  Future<bool> _isGameAlreadyInstalled(String cfgPath, String hashId) async {
    final File file = File(cfgPath);
    if (!await file.exists()) return false;
    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length % 64 != 0) return false;
      String targetPrefix = "ul.$hashId".trim();
      for (int i = 0; i < bytes.length; i += 64) {
        final List<int> idBlock = bytes.sublist(i + 32, i + 47);
        final String existingId = latin1.decode(idBlock).split('\x00').first.trim();
        if (existingId == targetPrefix) return true;
      }
    } catch (_) {}
    return false;
  }

  void _startProcess() {
    if (_isIsoToUl) {
      _convertIsoToUl();
    } else {
      _convertUlToIso();
    }
  }

  Future<void> _convertIsoToUl() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['iso']);
    if (res == null || res.files.single.path == null) return;
    
    final File src = File(res.files.single.path!);
    setState(() { _name = res.files.single.name.replaceAll('.iso', ''); _msg = "SCANNING DISK TRACKS FOR GENUINE ID..."; });
    
    final String gid = await _getGenuineId(src);
    final String hashId = _generateUlHashId(_name);
    final String filePrefix = "ul.$hashId.$gid"; 
    
    setState(() { _msg = "ID FOUND: [$gid]. CHOOSE YOUR OPL ROOT USB DIRECTORY..."; });
    
    String? out = await FilePicker.platform.getDirectoryPath();
    if (out == null) return;

    final String cfgPath = '$out/ul.cfg';

    if (await _isGameAlreadyInstalled(cfgPath, hashId)) {
      setState(() { _msg = "HALTED: THIS GAME ID IS ALREADY INSTALLED IN UL.CFG!"; });
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

      while (done < len) {
        final String partLabel = idx.toString().padLeft(2, '0');
        final File destFile = File('$out/$filePrefix.$partLabel');
        
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
            setState(() { _msg = "WRITING: $filePrefix.$partLabel"; _pct = done / len; });
            await Future.delayed(const Duration(milliseconds: 1)); 
          }
        }
        await writer.close();
        idx++;
      }
      await reader.close();

      setState(() { _msg = "COMPILING FILE MAP INDEX CARD FOR MENU UPGRADE..."; });
      
      // ======================================================================
      // COMPILER BLOCK: MATCHES YOUR REFERENCE IMAGE FORMAT EXACTLY (ul.GAME_ID)
      // ======================================================================
      final Uint8List newGameEntryBytes = Uint8List(64);
      
      // 1. Bytes 0-31: Game Title (Max 32 chars, null padded)
      String title = _name.toUpperCase();
      if (title.length > 32) title = title.substring(0, 32);
      List<int> titleBytes = latin1.encode(title);
      for (int i = 0; i < 32; i++) {
        newGameEntryBytes[i] = i < titleBytes.length ? titleBytes[i] : 0x00;
      }
      
      // 2. Bytes 32-46: Must be "ul." + Game ID (e.g., "ul.SLUS_211.34")
      String configIdString = "ul.${gid.trim()}"; 
      if (configIdString.length > 15) configIdString = configIdString.substring(0, 15);
      List<int> idBytes = latin1.encode(configIdString);
      for (int i = 0; i < 15; i++) {
        newGameEntryBytes[32 + i] = i < idBytes.length ? idBytes[i] : 0x00;
      }
      
      // 3. Byte 47: Total Parts Count
      newGameEntryBytes[47] = idx; 
      
      // 4. Byte 48: Disk Media Flag (0x14 = DVD, 0x12 = CD)
      newGameEntryBytes[48] = (len > 734003200) ? 0x14 : 0x12; 
      
      // 5. Bytes 49-52: Structural Null Padding
      for (int i = 49; i <= 52; i++) { newGameEntryBytes[i] = 0x00; }
      
      // 6. Byte 53: USBUtil Verification Constant Anchor
      newGameEntryBytes[53] = 0x08; 
      
      // 7. Bytes 54-63: Remainder Suffix padding space
      for (int i = 54; i < 64; i++) { newGameEntryBytes[i] = 0x00; }
      // ======================================================================
      
      try {
        final File cfgFile = File(cfgPath);
        if (!await cfgFile.exists()) {
          await cfgFile.create(recursive: true);
        }
        await cfgFile.writeAsBytes(newGameEntryBytes, mode: FileMode.append, flush: true);
        setState(() { _pct = 1.0; _msg = "SUCCESS: CONFIG UPDATED! NEW GAME LINKED TO OPL MENU."; });
      } catch (configError) {
        setState(() { _msg = "WRITE ERROR: GAME SPLIT OK, BUT UL.CFG WRITE PERMISSION DENIED."; _pct = 0.0; });
      }

    } catch (e) { 
      setState(() { _msg = "WRITE ERROR: VERIFY PERMISSIONS IN EXPORT LOCATION."; _pct = 0.0; }); 
    } finally { setState(() { _run = false; }); }
  }

  Future<void> _convertUlToIso() async {
    setState(() { _msg = "SELECT THE OPL FOLDER CONTAINING YOUR UL FILES..."; });
    String? srcDir = await FilePicker.platform.getDirectoryPath();
    if (srcDir == null) return;

    final File cfgFile = File('$srcDir/ul.cfg');
    if (!await cfgFile.exists()) {
      setState(() { _msg = "HALTED: ul.cfg NOT FOUND IN SELECTED FOLDER!"; });
      return;
    }

    List<Map<String, dynamic>> structuralGamesList = [];
    try {
      final Uint8List bytes = await cfgFile.readAsBytes();
      final Directory dir = Directory(srcDir);
      final List<FileSystemEntity> actualDirectoryContents = await dir.list().toList();

      for (int i = 0; i < bytes.length; i += 64) {
        if (i + 64 > bytes.length) break;
        
        final List<int> nameBlock = bytes.sublist(i, i + 32);
        final String title = latin1.decode(nameBlock).split('\x00').first.trim();
        
        final List<int> idBlock = bytes.sublist(i + 32, i + 47);
        final String hashPrefix = latin1.decode(idBlock).split('\x00').first.trim();
        
        final int partsCount = bytes[i + 47];
        
        if (title.isNotEmpty && hashPrefix.startsWith("ul.")) {
          String resolvedFullPrefixOnDisk = "";
          
          for (var item in actualDirectoryContents) {
            if (item is File) {
              String filename = item.path.split('/').last;
              if (filename.startsWith("$hashPrefix.") && filename.endsWith(".00")) {
                resolvedFullPrefixOnDisk = filename.substring(0, filename.length - 3);
                break;
              }
            }
          }

          if (resolvedFullPrefixOnDisk.isNotEmpty) {
            structuralGamesList.add({
              'title': title,
              'prefix': resolvedFullPrefixOnDisk, 
              'parts': partsCount,
            });
          }
        }
      }
    } catch (_) {}

    if (structuralGamesList.isEmpty) {
      setState(() { _msg = "HALTED: NO MATCHING UL SPLIT FILES RECOGNIZED IN THIS FOLDER."; });
      return;
    }

    Map<String, dynamic>? chosenGame = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("SELECT GAME TO RESTORE", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF161E2E),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: structuralGamesList.length,
              itemBuilder: (context, index) {
                final game = structuralGamesList[index];
                return ListTile(
                  leading: const Icon(Icons.gamepad, color: Color(0xFF4C9EFF)),
                  title: Text(game['title'], style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text("${game['prefix']} • ${game['parts']} parts", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  onTap: () => Navigator.of(context).pop(game),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent)))
          ],
        );
      },
    );

    if (chosenGame == null) {
      setState(() { _msg = "READY: EXTRACTION CANCELED BY USER."; });
      return;
    }

    String cleanTitle = chosenGame['title'];
    String fullFilePrefix = chosenGame['prefix']; 
    int totalParts = chosenGame['parts'];

    setState(() { 
      _name = cleanTitle; 
      _msg = "GAME MATCHED. SELECT THE OUTPUT FOLDER FOR THE RESTORED ISO..."; 
    });

    String? outDir = await FilePicker.platform.getDirectoryPath();
    if (outDir == null) return;

    setState(() { _run = true; _pct = 0.0; _msg = "VERIFYING ALL SPLIT CHUNKS IN FOLDER..."; });

    try {
      List<File> sequentialParts = [];
      
      for (int idx = 0; idx < totalParts; idx++) {
        final String partLabel = idx.toString().padLeft(2, '0');
        File targetPartFile = File('$srcDir/$fullFilePrefix.$partLabel');
        
        if (await targetPartFile.exists()) {
          sequentialParts.add(targetPartFile);
        } else {
          setState(() { _msg = "HALTED: MISSING CHUNK: $fullFilePrefix.$partLabel"; });
          _run = false;
          return;
        }
      }

      int totalTargetSize = 0;
      for (var filePart in sequentialParts) { totalTargetSize += await filePart.length(); }

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
                    _name = "No OPL Folder Loaded";
                    _pct = 0.0;
                    _msg = "READY: SELECT THE OPL ROOT USB DIRECTORY";
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
                  label: Text(_run ? "PROCESSING" : (_isIsoToUl ? "START CONVERSION" : "LOAD OPL DIRECTORY")),
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
