class _OplConverterPageState extends State<OplConverterPage> {
  String _statusMessage = "READY: CHOOSE AN ISO GAME FILE TO SPLIT";
  bool _isConverting = false;
  double _progressValue = 0.0;
  String _selectedGameName = "No ISO Loaded";

  // Scans the ISO sectors to parse the true embedded SYSTEM.CNF configuration
  Future<String> _extractGenuineGameId(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      // PS2 ISO primary volume descriptors begin scanning around Sector 16 (32768 bytes)
      await raf.setPosition(32768);
      final Uint8List buffer = await raf.read(64 * 1024); // 64KB scan window
      final String rawText = latin1.decode(buffer, allowInvalid: true);
      
      final RegExp regExp = RegExp(r'([A-Z]{4})_(\d{3})\.(\d{2})');
      final match = regExp.firstMatch(rawText);
      
      if (match != null) {
        String prefix = match.group(1)!;
        String num1 = match.group(2)!;
        String num2 = match.group(3)!;
        return "${prefix}_$num1.$num2"; // Yields exact genuine ID e.g., SLUS_216.05
      }
    } catch (_) {
      // Fallback sector scan if primary volume descriptor is modified
      try {
        if (raf != null) {
          await raf.setPosition(0);
          final Uint8List smallBuffer = await raf.read(256 * 1024); // Scan first 256KB
          final String altText = latin1.decode(smallBuffer, allowInvalid: true);
          final RegExp altRegExp = RegExp(r'([A-Z]{4})_(\d{3})\.(\d{2})');
          final altMatch = altRegExp.firstMatch(altText);
          if (altMatch != null) {
            return "${altMatch.group(1)}_${altMatch.group(2)}.${altMatch.group(3)}";
          }
        }
      } catch (_) {}
    } finally {
      if (raf != null) {
        await raf.close();
      }
    }
    return "SLUS_000.00"; // Safeguard fallback if disk descriptor header is entirely custom
  }

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

    final File sourceIso = File(result.files.single.path!);
    final String baseName = result.files.single.name.replaceAll('.iso', '');

    setState(() {
      _selectedGameName = baseName;
      _statusMessage = "SCANNING DISK TRACKS FOR GENUINE GAME ID...";
    });

    // 2. Read the genuine identifier string directly from the file bytes
    final String genuineId = await _extractGenuineGameId(sourceIso);

    setState(() {
      _statusMessage = "GAME FOUND ID [$genuineId]. SELECT OUTPUT DESTINATION...";
    });

    // 3. Select Output Folder to Bypass Storage Restrictions
    String? targetDirectory = await FilePicker.platform.getDirectoryPath();
    if (targetDirectory == null) {
      setState(() { _statusMessage = "ERROR: OUTPUT FOLDER NOT SELECTED"; });
      return;
    }

    setState(() {
      _isConverting = true;
      _progressValue = 0.0;
      _statusMessage = "OPENING ISO FILE ENGINES...";
    });

    try {
      final int totalFileBytes = await sourceIso.length();
      const int targetChunkLimit = 1024 * 1024 * 1024; // Standard 1 GB split boundary
      
      String formattedGameTitle = baseName;
      if (formattedGameTitle.length > 32) formattedGameTitle = formattedGameTitle.substring(0, 32);
      formattedGameTitle = formattedGameTitle.padRight(32, ' ');
      
      final RandomAccessFile filePointer = await sourceIso.open(mode: FileMode.read);
      int bytesProcessed = 0;
      int sliceIndex = 0;

      // 4. Optimized Asynchronous Streaming File Loop Engine to prevent UI Freezing
      while (bytesProcessed < totalFileBytes) {
        final int batchRemainder = (bytesProcessed + targetChunkLimit > totalFileBytes) 
            ? (totalFileBytes - bytesProcessed) 
            : targetChunkLimit;

        final String sequentialLabel = sliceIndex.toString().padLeft(2, '0');
        
        // Micro-yield execution to the UI main thread to let the progress bar update instantly
        await Future.delayed(const Duration(milliseconds: 10));
        
        setState(() {
          _statusMessage = "PROCESSING: WRITING PART $sequentialLabel FOR ID: $genuineId";
          _progressValue = bytesProcessed / totalFileBytes;
        });

        // Binary extraction streaming segment updates directly to storage target path
        final Uint8List dataSegment = await filePointer.read(batchRemainder);
        final File segmentOutput = File('$targetDirectory/ul.$genuineId.$sequentialLabel');
        await segmentOutput.writeAsBytes(dataSegment, flush: true);

        bytesProcessed += batchRemainder;
        sliceIndex++;
      }
      await filePointer.close();

      // 5. Generate the structural matching index configuration file (ul.cfg)
      setState(() { _statusMessage = "COMPILING UL.CFG BINARY INDEX TABLE..."; });
      
      final Uint8List descriptorMapBytes = Uint8List(64);
      final ByteData structuredView = ByteData.sublistView(descriptorMapBytes);

      final List<int> processedTitleAscii = formattedGameTitle.codeUnits;
      for (int i = 0; i < 32; i++) {
        descriptorMapBytes[i] = i < processedTitleAscii.length ? processedTitleAscii[i] : 32;
      }

      final List<int> processedIdAscii = genuineId.codeUnits;
      for (int i = 0; i < 15; i++) {
        descriptorMapBytes[32 + i] = i < processedIdAscii.length ? processedIdAscii[i] : 0;
      }

      structuredView.setUint32(48, sliceIndex, Endian.little);

      final File configurationIndex = File('$targetDirectory/ul.cfg');
      await configurationIndex.writeAsBytes(descriptorMapBytes, flush: true);

      setState(() {
        _progressValue = 1.0;
        _statusMessage = "SUCCESS: ALL CHUNKS AND UL.CFG GENERATED SAFELY!";
      });
    } catch (failureTrace) {
      setState(() {
        _statusMessage = "WRITE ERROR: ${failureTrace.toString().toUpperCase()}";
        _progressValue = 0.0;
      });
    } finally {
      setState(() { _isConverting = false; });
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
                      "CURRENT LOADED GAME COMPONENT:",
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
                      Text("BDM USB LOADER", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
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

            
              
