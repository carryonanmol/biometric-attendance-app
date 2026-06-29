Biometric Attendance App 📱📍

The mobile companion application for the  Biometric Attendance system. Built with Flutter, this app allows employees to securely log their attendance by capturing their facial biometrics and verifying their physical location against authorized organizational geofences.

🚀 Key Features

Seamless Onboarding: Secure 2-step login using Employee ID, PIN, and an SMS OTP verification.

Smart Biometric Capture: Integrates directly with the device camera to capture high-quality facial frames for backend liveness and identity verification.

High-Accuracy GPS Tracking: Captures device latitude and longitude to ensure the employee is physically present within the authorized deployment zone before allowing a punch-in.

Silent Token Refresh: Automatically manages JWT access and refresh tokens in the background, ensuring employees stay logged in securely without constant interruptions.

Real-Time Status: Displays the current shift status (Punched In / Punched Out) directly on the dashboard.

🛠️ Tech Stack

Framework: Flutter & Dart

Hardware Integration: camera (for facial capture), geolocator (for GPS coordinate extraction)

Networking: http (for communicating with the FastAPI backend)

Storage: shared_preferences (for secure local token storage)

⚙️ Local Setup Instructions

1. Prerequisites

Flutter SDK (Version 3.0+)

Android Studio (for Android build tools and emulation)

A physical device or emulator for testing

2. Installation

Clone the repository and install dependencies:

git clone [https://github.com/carryonanmol/sjvn-attendance-app.git](https://github.com/carryonanmol/biometric-attendance-app.git)
cd biometric-attendance-app
flutter pub get


3. Configuration

Before running the app, you must point it to your backend server.

Open lib/main.dart (or your config file).

Locate the BASE_URL constant.

Update it to match your live backend URL or local Ngrok tunnel:

const String BASE_URL = "[https://your-production-domain.com](https://your-production-domain.com)"; // Do not include a trailing slash


4. Build and Run

To run the app on an attached device or emulator:

flutter run


To build a standalone Release APK for Android deployment:

flutter build apk --release


The compiled APK will be located at build/app/outputs/flutter-apk/app-release.apk.
