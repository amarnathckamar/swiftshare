import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SwiftShareDesktop());
  doWhenWindowReady(() {
    final win = appWindow;
    win.minSize = const Size(900, 600);
    win.size = const Size(1000, 650);
    win.alignment = Alignment.center;
    win.show();
  });
}

class SwiftShareDesktop extends StatelessWidget {
  const SwiftShareDesktop({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwiftShare PC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const SwiftShareDashboard(),
    );
  }
}

class SwiftShareDashboard extends StatefulWidget {
  const SwiftShareDashboard({super.key});

  @override
  State<SwiftShareDashboard> createState() => _SwiftShareDashboardState();
}

class _SwiftShareDashboardState extends State<SwiftShareDashboard> {
  final List<String> logs = [];
  final List<Socket> clients = [];
  bool running = false;
  ServerSocket? serverSocket;
  int port = 4040;
  String? selectedSavePath;
  final ValueNotifier<double> progress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _loadSavedPath();
  }

  Future<void> _loadSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => selectedSavePath = prefs.getString('savePath'));
  }

  Future<void> _savePathPreference(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savePath', path);
  }

  void log(String msg) {
    setState(() => logs.add("[${DateTime.now().hour}:${DateTime.now().minute}] $msg"));
  }

  Future<void> chooseSaveFolder() async {
    String? folderPath = await FilePicker.platform.getDirectoryPath();
    if (folderPath != null) {
      setState(() => selectedSavePath = folderPath);
      await _savePathPreference(folderPath);
      log("📁 Save folder set to: $folderPath");
    } else {
      log("⚠️ Folder selection canceled.");
    }
  }

  Future<String> getSavePath(String filename) async {
    if (selectedSavePath != null) return '$selectedSavePath/$filename';

    final downloads = await getDownloadsDirectory();
    final saveDir = Directory('${downloads!.path}/SwiftShare');
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
    return '${saveDir.path}/$filename';
  }

  // ✅ Start Server
  Future<void> startServer() async {
    if (running) {
      log("⚠️ Server already running.");
      return;
    }
    try {
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      running = true;
      log("🚀 Server started on port $port");
      serverSocket!.listen(handleClient);
    } catch (e) {
      log("❌ Failed to start server: $e");
    }
  }

  // ✅ Stop Server
  void stopServer() {
    for (var c in clients) {
      c.destroy();
    }
    clients.clear();
    serverSocket?.close();
    serverSocket = null;
    running = false;
    log("🛑 Server stopped.");
  }

  // ✅ Handle Clients
  void handleClient(Socket socket) {
    clients.add(socket);
    log("📡 Client connected: ${socket.remoteAddress.address}");

    final buffer = BytesBuilder();
    bool receivingFile = false;
    String? filename;
    int expectedFileSize = 0;
    IOSink? sink;
    int receivedBytes = 0;

    socket.listen((data) async {
      buffer.add(data);

      // Handle text or file mode
      while (buffer.length > 0) {
        // --- File transfer in progress ---
        if (receivingFile) {
          final remaining = expectedFileSize - receivedBytes;
          final chunk = buffer.toBytes();

          // Write chunk
          final toWrite = remaining < chunk.length ? remaining : chunk.length;
          sink!.add(chunk.sublist(0, toWrite));
          receivedBytes += toWrite;

          // Remove written bytes from buffer
          buffer.clear();
          if (chunk.length > toWrite) {
            buffer.add(chunk.sublist(toWrite));
          }

          // Update progress
          progress.value = receivedBytes / expectedFileSize;

          // Done?
          if (receivedBytes >= expectedFileSize) {
            await sink!.flush();
            await sink!.close();
            log("✅ File saved to: $filename");
            receivingFile = false;
            filename = null;
            expectedFileSize = 0;
            sink = null;
            receivedBytes = 0;
          }
          break;
        }

        // --- New message or file header ---
        if (buffer.length < 3) return;
        final header = utf8.decode(buffer.toBytes().sublist(0, 3), allowMalformed: true);

        // --- Text message ---
        if (header == "TXT") {
          if (buffer.length < 7) return; // wait for at least header + length
          final msgLenBytes = buffer.toBytes().sublist(3, 7);
          final msgLen = ByteData.sublistView(Uint8List.fromList(msgLenBytes)).getUint32(0, Endian.big);
          if (buffer.length < 7 + msgLen) return;
          final msg = utf8.decode(buffer.toBytes().sublist(7, 7 + msgLen), allowMalformed: true);
          log("💬 From ${socket.remoteAddress.address}: $msg");
          buffer.clear();
          return;
        }

        // --- File transfer header ---
        if (header == "FIL") {
          final bytes = buffer.toBytes();
          if (bytes.length < 3 + 4) return; // header + filename length
          final nameLen = ByteData.sublistView(Uint8List.fromList(bytes.sublist(3, 7))).getUint32(0, Endian.big);
          if (bytes.length < 7 + nameLen + 8) return; // header + name + size

          // Extract filename and filesize
          final nameBytes = bytes.sublist(7, 7 + nameLen);
          final name = utf8.decode(nameBytes, allowMalformed: true);
          final sizeBytes = bytes.sublist(7 + nameLen, 7 + nameLen + 8);
          final fileSize = ByteData.sublistView(Uint8List.fromList(sizeBytes)).getUint64(0, Endian.big);

          // Setup file saving
          final savePath = await getSavePath(name);
          final file = File(savePath);
          sink = file.openWrite();

          log("📦 Receiving $name (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)");

          filename = savePath;
          expectedFileSize = fileSize;
          receivingFile = true;
          receivedBytes = 0;

          // Remove processed header from buffer
          final used = 7 + nameLen + 8;
          buffer.clear();
          if (bytes.length > used) buffer.add(bytes.sublist(used));

          break;
        }

        // Unknown header — clear to avoid blocking
        buffer.clear();
        break;
      }
    }, onDone: () {
      log("🔌 Client disconnected: ${socket.remoteAddress.address}");
      clients.remove(socket);
    }, onError: (e) {
      log("⚠️ Socket error: $e");
      clients.remove(socket);
    });
  }


  // ✅ Receive File
  Future<void> _receiveFile(Socket socket) async {
    try {
      final nameLenBytes = await _readBytes(socket, 4);
      final nameLen = ByteData.sublistView(nameLenBytes).getUint32(0, Endian.big);

      final nameBytes = await _readBytes(socket, nameLen);
      final filename = utf8.decode(nameBytes);

      final sizeBytes = await _readBytes(socket, 8);
      final fileSize = ByteData.sublistView(sizeBytes).getUint64(0, Endian.big);

      final savePath = await getSavePath(filename);
      final file = File(savePath);
      final sink = file.openWrite();

      log("📦 Receiving $filename (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)");

      int received = 0;
      const chunk = 64 * 1024;

      while (received < fileSize) {
        final remaining = fileSize - received < chunk ? (fileSize - received).toInt() : chunk;
        final chunkData = await _readBytes(socket, remaining);
        sink.add(chunkData);
        received += chunkData.length;
        progress.value = received / fileSize;
      }

      await sink.flush();
      await sink.close();
      progress.value = 1.0;
      log("✅ File saved to: $savePath");
    } catch (e) {
      log("❌ File receive failed: $e");
    }
  }

  // ✅ Read Bytes Safely
  Future<Uint8List> _readBytes(Socket socket, int length) async {
    final completer = Completer<Uint8List>();
    final collected = BytesBuilder();

    late StreamSubscription sub;
    sub = socket.listen((data) {
      collected.add(data);
      if (collected.length >= length) {
        sub.cancel();
        completer.complete(Uint8List.fromList(collected.takeBytes().sublist(0, length)));
      }
    }, onError: completer.completeError, onDone: () {
      if (!completer.isCompleted) completer.completeError(Exception("Socket closed early"));
    });

    return completer.future;
  }

  // ✅ Send File to All Clients
  Future<void> sendFileToAll() async {
    if (clients.isEmpty) {
      log("⚠️ No clients connected.");
      return;
    }

    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = File(result.files.single.path!);
    final name = result.files.single.name;
    final size = await file.length();

    for (var client in clients) {
      log("📤 Sending $name to ${client.remoteAddress.address}");
      client.add(utf8.encode("FIL"));
      client.add(_int32Bytes(utf8.encode(name).length));
      client.add(utf8.encode(name));
      client.add(_int64Bytes(size));
      await client.flush();

      final raf = file.openSync();
      final buffer = List<int>.filled(64 * 1024, 0);
      int sent = 0;

      while (true) {
        final n = raf.readIntoSync(buffer);
        if (n == 0) break;
        client.add(buffer.sublist(0, n));
        sent += n;
        progress.value = sent / size;
        await client.flush();
      }

      raf.closeSync();
      log("✅ File $name sent (${(size / 1024 / 1024).toStringAsFixed(2)} MB)");
    }
  }

  // Byte Helpers
  List<int> _int32Bytes(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.big);
    return b.buffer.asUint8List();
  }

  List<int> _int64Bytes(int v) {
    final b = ByteData(8)..setUint64(0, v, Endian.big);
    return b.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("SwiftShare Desktop", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_rounded, color: Colors.tealAccent),
            onPressed: sendFileToAll,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Sidebar
            Container(
              width: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Lottie.asset('assets/server.json', width: 100, repeat: true),
                    const SizedBox(height: 10),
                    Text(
                      running ? "🟢 Running" : "🔴 Stopped",
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton.icon(
                      onPressed: chooseSaveFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text("Select Save Folder"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        minimumSize: const Size(180, 45),
                      ),
                    ),
                    if (selectedSavePath != null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          selectedSavePath!,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 10),

                    ElevatedButton.icon(
                      onPressed: startServer,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Start Server"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(180, 45),
                      ),
                    ),
                    const SizedBox(height: 10),

                    ElevatedButton.icon(
                      onPressed: stopServer,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text("Stop Server"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        minimumSize: const Size(180, 45),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      "Connected: ${clients.length}",
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Logs + Progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Server Logs", style: TextStyle(color: Colors.white70, fontSize: 18)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF292929),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (_, i) => Text(
                          logs[i],
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("File Transfer Progress", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      backgroundColor: Colors.white12,
                      color: Colors.tealAccent,
                      minHeight: 10,
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
