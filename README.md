# shiftsharewin

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.



SwiftShare Desktop Documentation

SwiftShare is a cross-platform LAN-based file and message sharing tool built using Flutter (Windows Desktop) and Flutter (Android). This document provides an overview of the system, installation steps, features, and usage instructions.

--- Overview ---
SwiftShare enables seamless file and message transfer between Windows PCs and Android devices over LAN or hotspot connections. The system avoids internet usage by relying solely on TCP and UDP technologies.

--- Features ---
• Windows desktop app built with Flutter
• Android app with TCP/UDP communication
• Fast file transfer (supports large files)
• Folder selection for saving received files
• Live progress indicators
• Modern UI with Lottie animations
• Message sending between devices
• Multi-client connection support

--- Technologies Used ---
• Flutter (Windows Desktop)
• Flutter (Android)
• Python Socket Server (optional)
• TCP (File/Message Transfer)
• UDP (Device Discovery)
• Path Provider, File Picker, Shared Preferences
• Lottie, Google Fonts, Bitsdojo Window

--- Installation (Windows) ---
1. Install Flutter SDK (3.24+)
2. Install Visual Studio Build Tools
3. Clone the repository
4. Run:
   flutter pub get
   flutter run -d windows

--- Installation (Android) ---
1. Open Android folder in VS Code/Android Studio
2. Run:
   flutter pub get
3. Install APK:
   flutter build apk --release
   flutter install

--- Usage Flow ---
1. Open SwiftShare Desktop
2. Click 'Select Save Folder'
3. Click 'Start Server'
4. Open mobile app and connect
5. Send or receive files instantly

--- Networking ---
TCP Port: 4040  
UDP Port: 5050  
Firewall permission may be required for local network communication.

--- Future Enhancements ---
• QR Code connection mode
• macOS/Linux Desktop support
• Encrypted transfers
• Built-in file explorer

Developed by: Amarnath CK
