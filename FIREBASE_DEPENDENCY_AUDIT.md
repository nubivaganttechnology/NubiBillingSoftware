# Firebase Dependency & SDK Usage Audit Report
**Project**: Shree Balaji Enterprises Billing ERP (`NubiBillingSoftware`)  
**Audit Mode**: `AUDIT_FIRST_THEN_SAFE_REFACTOR`  
**Execution Timestamp**: October 23, 2026  
**Auditor**: Antigravity Senior Mobile Architect & API Migration Specialist  
**Status**: COMPLETE (0 SDK Dependencies Found; 100% REST Protocol Architecture)

---

## 1. Executive Summary

This comprehensive audit was executed across all platform targets (Android, iOS, macOS, Windows, Linux, Web), configuration files, dependency manifests, build scripts, Dart source files, and test suites.

### Key Audit Findings:
1. **Total Direct Firebase SDK Dependencies**: **0**
2. **Total Transitive Firebase SDK Dependencies**: **0**
3. **Total Native Platform SDK Registrations**: **0**
4. **Current Remote Communication Mode**: **Pure REST API** via standard Dart `package:http`.
5. **Direct Network Calls in UI Widgets**: **0** (All UI interaction is decoupled through ViewModels / Controllers and Repositories).
6. **Backend Coupling**: Although zero Firebase SDKs exist, the network layer and data persistence layers are currently tightly coupled to **Google Cloud / Firebase REST wire formats** (e.g. Firestore field wrappers `{"stringValue": ...}`, Google Identity Toolkit REST endpoints, and Firestore `:commit` and `:runQuery` protocols).

---

## 2. Dependency Manifest & Lockfile Audit

### 2.1 `pubspec.yaml`
Inspection of `pubspec.yaml` reveals **zero** Firebase SDK packages. The network and data stack relies on:
- `http: ^1.2.2` (Standard HTTP client)
- `flutter_secure_storage: ^10.3.1` (Encrypted persistent storage for auth tokens)
- `sqflite: ^2.4.4`, `sqflite_common_ffi: ^2.4.3`, `sqflite_common_ffi_web: ^1.2.0` (Cross-platform SQLite local storage)
- `connectivity_plus: ^7.3.2` (Network connectivity monitoring)

No entries exist for:
`firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_storage`, `firebase_database`, `firebase_messaging`, `firebase_functions`, `firebase_analytics`.

### 2.2 `pubspec.lock`
A line-by-line regex scan of `pubspec.lock` confirmed **0 transitive Firebase dependencies**. Neither `firebase_core_platform_interface` nor any Google Services transitive plugin is present in the dependency tree.

### 2.3 Generated Registrants
The Flutter plugin registrants across all target platforms were inspected:
- **Android**: `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
- **iOS**: `ios/Runner/GeneratedPluginRegistrant.h` & `.m`
- **macOS**: `macos/Flutter/GeneratedPluginRegistrant.swift`
- **Linux / Windows**: Native CMake registrants

**Result**: Only native plugins for camera, printing, file selection, secure storage, and SQLite are registered. No native Firebase or Google Play Services plugins are registered.

---

## 3. Platform & Build Configuration Audit

| Platform / File | Target Path | Firebase SDK / Plugin Present | Notes |
| :--- | :--- | :---: | :--- |
| **Android Gradle** | `android/build.gradle.kts` | **NO** | No `com.google.gms.google-services` classpath |
| **Android App Gradle** | `android/app/build.gradle.kts` | **NO** | No `com.google.gms.google-services` plugin applied |
| **Android Manifest** | `android/app/src/main/AndroidManifest.xml` | **NO** | Standard permissions; no Firebase background services |
| **Android Config** | `android/app/google-services.json` | **NO** | File does not exist |
| **iOS Podfile** | `ios/Podfile` | **NO** | No Firebase Pod dependencies |
| **iOS Info.plist** | `ios/Runner/Info.plist` | **NO** | No Firebase keys or client IDs |
| **iOS Config** | `ios/Runner/GoogleService-Info.plist` | **NO** | File does not exist |
| **macOS Podfile** | `macos/Podfile` | **NO** | No Firebase pods |
| **Web Index** | `web/index.html` | **NO** | No Firebase JavaScript SDK `<script>` tags |
| **Windows CMake** | `windows/CMakeLists.txt` | **NO** | Pure desktop build |

---

## 4. Source Codebase Pattern Search (`lib/`, `test/`)

Every mandatory search string was tested against the entire codebase:

| Pattern | Scope | Matches Found | Calling File & Line Details |
| :--- | :--- | :---: | :--- |
| `firebase_core` | `lib/`, `test/` | 1 | `test/phase10k_production_migration_runner_test.dart:1103`<br>*(Asserts runner source does NOT contain `firebase_core`)* |
| `cloud_firestore` | `lib/`, `test/` | 1 | `test/phase10k_production_migration_runner_test.dart:1102`<br>*(Asserts runner source does NOT contain `cloud_firestore`)* |
| `firebase_auth` | `lib/`, `test/` | 0 | None |
| `firebase_storage` | `lib/`, `test/` | 0 | None |
| `firebase_database` | `lib/`, `test/` | 0 | None |
| `firebase_messaging` | `lib/`, `test/` | 0 | None |
| `firebase_functions` | `lib/`, `test/` | 0 | None |
| `firebase_analytics` | `lib/`, `test/` | 0 | None |
| `Firebase.initializeApp` | `lib/`, `test/` | 0 | None |
| `FirebaseFirestore.instance` | `lib/`, `test/` | 0 | None |
| `FirebaseAuth.instance` | `lib/`, `test/` | 0 | None |
| `FirebaseStorage.instance` | `lib/`, `test/` | 0 | None |
| `FirebaseDatabase.instance` | `lib/`, `test/` | 0 | None |
| `FirebaseApp` | `lib/`, `test/` | 0 | None |
| `GoogleServices` | All files | 0 | None |
| `Firebase JavaScript SDK` | `web/` | 0 | None |
| `Firestore SDK imports` | `lib/`, `test/` | 0 | None |
| `Direct HTTP in UI` | `lib/presentation/` | 0 | **0 occurrences**. Zero HTTP imports in UI widgets. |

---

## 5. Firebase Configuration & Metadata Files Found

The following configuration files exist on disk:
1. `.firebaserc`:
   ```json
   {
     "projects": {
       "default": "test1-bcebe"
     }
   }
   ```
2. `firebase.json`:
   ```json
   {
     "firestore": {
       "indexes": "firestore.indexes.json"
     }
   }
   ```
3. `firestore.indexes.json`:
   - Contains 58KB of Firestore composite index definitions required for multi-field queries across multi-tenant scopes (`tenantId`, `businessId`, `outletId`, `updatedAt`, `status`).
4. `docs/face_attendance/emulator/firebase.json` & `firestore.rules`:
   - Offline developer documentation and test mock definitions used for the face attendance feature emulator tests.

---

## 6. Firebase SDK vs. REST API Differentiation

| Architectural Attribute | Flutter Firebase SDK Approach | Current Project REST Approach |
| :--- | :--- | :--- |
| **Package Dependency** | `cloud_firestore`, `firebase_auth`, `firebase_core` | `http: ^1.2.2`, `sqflite: ^2.4.4` |
| **Native Binaries** | Heavy native Android/iOS static libraries | Zero native Firebase libraries |
| **Connection Type** | Persistent gRPC channel / WebSockets | Stateless HTTP/1.1 REST calls |
| **Offline Cache** | Closed-source Google LevelDB / IndexedDB cache | Open-source SQLite (`LocalDatabase`, `LocalDataSource`) |
| **Sync Control** | Opaque SDK synchronization | Transparent, auditable `SyncEngine` with SQLite outbox |
| **Auth Management** | Native `FirebaseAuth` session listener | Custom `TokenStorageService` & `AuthSession` with JWT parsing |
| **Migration Readiness** | Severely coupled to Google ecosystem | Highly portable; requires adapter & contract standardization |

---

## 7. Audit Conclusion & Impact on Migration

The project has **already achieved the primary objective of eliminating all Firebase SDKs**. 
However, the HTTP calls, JSON encoders/decoders, query builders, and collection names are currently modeled directly around Google's REST specifications. 

To prepare for future PHP and PostgreSQL migration, the remaining work is:
1. Abstract all remote HTTP requests behind a clean `BackendAdapter` interface.
2. Centralize configuration in `api_config.dart` and endpoints in `api_endpoints.dart`.
3. Normalize data models so they receive and return pure application maps rather than Firestore-typed objects.
4. Keep the existing SQLite local caching and `SyncEngine` intact, as it is already built on top of SQLite and completely decoupled from Firebase native storage.
