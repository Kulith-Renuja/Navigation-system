# 🧭 AI-Powered Mobility Assistant for the Visually Impaired

An advanced, multimodal Flutter application designed to provide seamless indoor and outdoor navigation for visually impaired users. This project combines custom A* graph-based indoor routing, GPS-driven outdoor navigation, and a highly memory-optimized headless YOLOv8 machine learning model to act as a real-time hazard guardian.

### 📥 App Download & Demo
**[Click Here to Download the App / View the Demo](YOUR_GOOGLE_DRIVE_LINK_HERE)**

---

## ✨ Key Features

* **🗣️ Conversational Voice UI:** A completely hands-free interface. Users can hold a button to speak their destination. The app utilizes fuzzy-matching and multi-step conversational logic to guide the user through map selection.
* **🏢 Indoor Navigation (Offline-Capable):** Uses a custom-built Graph mapping system. Computes optimal routes using the **A* Algorithm** and guides users step-by-step using hardware sensors (Pedometer for distance, Compass for orientation).
* **🌍 Outdoor Navigation:** Integrates the Google Maps Directions API and live GPS tracking for turn-by-turn outdoor routing with an automatic 15-meter arrival proximity threshold.
* **👁️ The "Silent Guardian" (Headless AI):** A background YOLOv8 TensorFlow Lite model that scans the camera feed for obstacles (chairs, people, laptops) without rendering a UI. It intelligently prioritizes TTS routing instructions to ensure hazard warnings never talk over navigation directions.
* **📳 Multimodal Feedback:** Utilizes distinct haptic vibration patterns (e.g., rapid pulses for hazards, long pulses for arrivals) and highly optimized Text-to-Speech (TTS) for accessible guidance.

---

## 🏗️ The Project Architecture & Breakdown

This application was built systematically in 8 distinct phases to ensure strict accessibility compliance and performance optimization.

### 1. Core Foundation & Routing
Established the Flutter application shell. Integrated the base theme strictly optimized for screen readers (Android TalkBack / iOS VoiceOver) using high-contrast `YellowAccent` on `Black` UI elements and robust `Semantics` wrappers.

### 2. User Account & Firebase Integration
Initialized the cloud backend. Built the Account screen to establish the Firestore database connection, handling user profiles and ensuring real-time read/write capabilities for dynamic map loading.

### 3. The "Add Maps" Builder (For Sighted Facilitators)
Developed a specialized tool for sighted users (supervisors/facility managers) to map out indoor locations. 
* **Graph Creation:** Allows users to define Nodes (e.g., "Entrance", "Elevator") and Edges (step counts and 90-degree directional turns).
* **Cloud Sync:** Formats the custom graph into JSON and dynamically uploads it to a structured Firebase hierarchy (`Location -> Building -> Floor`).

### 4. TFLite Vision Module (Isolated)
Integrated a YOLOv8 Nano `.tflite` model directly into the app assets. 
* **Memory Optimization:** Engineered a highly efficient YUV420 to RGB tensor conversion algorithm that pre-allocates memory blocks to prevent Garbage Collection (GC) thrashing and frame drops. Tested in isolation for maximum FPS.

### 5. Sensors & Feedback Core
Independently built and rigorously tested the hardware interaction layers:
* **TTS (Text-to-Speech):** For routing and hazard announcements.
* **Haptics:** For physical confirmation of steps and turns.
* **Pedometer & Compass:** For tracking indoor movement without relying on GPS signals.

### 6. Indoor Navigation Logic
The brain of the indoor experience. Fetches the hierarchical JSON map from Firebase and applies the **A* Search Algorithm** to find the shortest path. Converts the path into a `Queue` of actionable steps (Walk X steps, Turn Y degrees) verified by the pedometer and compass.

### 7. Outdoor Navigation Logic
The GPS-dependent module. Connects to the Google Maps Directions API to fetch walking routes. Parses HTML instructions into plain text and uses `Geolocator` streams to track live movement, automatically popping instructions off the queue as the user reaches GPS coordinates.

### 8. Final Orchestration
The culminating integration phase. 
* Connected the isolated TFLite vision module to the navigation states, firing it up when a route begins and gracefully disposing of the camera stream when navigation ends or the app is paused (AppLifecycle management).
* Implemented the "Voice Traffic Cop," a boolean lock ensuring hazard AI and navigation TTS never overlap.

---

## 🛠️ Tech Stack & Libraries

* **Framework:** Flutter / Dart
* **Backend:** Firebase (Cloud Firestore)
* **Machine Learning:** TensorFlow Lite (`tflite_flutter`), YOLOv8 Nano
* **Mapping & Location:** `Maps_flutter`, `geolocator`, `flutter_polyline_points`
* **Accessibility & Sensors:** `flutter_tts`, `speech_to_text`, `vibration`, `pedometer`, `flutter_compass`

---

## 🚀 Installation & Setup

To run this project locally:

1. Clone the repository.
2. Run `flutter pub get` to install all dependencies.
3. Ensure you have a valid `google-services.json` file in your `android/app` directory for Firebase integration.
4. Ensure your Google Maps API key is active in the `outdoor_nav_screen.dart` file and `AndroidManifest.xml`.
5. Connect a physical Android device (Sensors and Camera will not work properly on an emulator).
6. Run `flutter run`.

*(Note: Ensure Activity Recognition, Location, Camera, and Microphone permissions are granted on the device).*