# ParkingBuddy — Project Overview

ParkingBuddy is a full-stack smart parking app for Skopje. A Flutter mobile client lets drivers find, reserve, start, pay for, and end parking sessions on a live Google Map, backed by a Spring Boot REST API that uses a PostgreSQL + PostGIS database for location-aware spot lookup.

---

## 1. Repository Layout

```
parking_buddy/
├── backend/                               ← Spring Boot REST API (Java 17, Maven)
│   ├── database_setup.sql                 ← one-time schema + PostGIS seed
│   ├── mvnw / mvnw.cmd                    ← Maven wrapper
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/parkingbuddy/parking_buddy/
│       │   ├── ParkingBuddyApplication.java
│       │   ├── entity/
│       │   │   ├── ParkingSpot.java
│       │   │   └── ParkingSession.java
│       │   ├── repository/
│       │   │   ├── ParkingSpotRepository.java
│       │   │   └── ParkingSessionRepository.java
│       │   ├── service/
│       │   │   ├── ParkingSpotService.java
│       │   │   └── ParkingSessionService.java
│       │   └── controller/
│       │       ├── ParkingSpotController.java
│       │       └── ParkingSessionController.java
│       └── resources/
│           ├── application.properties     ← reads DB_URL / DB_USERNAME / DB_PASSWORD
│           └── data.sql                   ← runs on every startup (resets state)
│
├── frontend/                              ← Flutter app (Dart, Material 3)
│   ├── pubspec.yaml
│   ├── android/ ios/ web/ windows/ macos/ linux/
│   ├── test/
│   └── lib/
│       ├── main.dart                      ← app entry, theme + MapScreen home
│       ├── theme.dart                     ← green palette + Noto Sans typography
│       ├── models/
│       │   ├── parking_spot.dart
│       │   └── parking_session.dart
│       ├── services/
│       │   └── api_service.dart           ← http client for the backend
│       ├── screens/
│       │   ├── map_screen.dart            ← Google Map + nearby spots + search
│       │   ├── reservation_screen.dart    ← 15-minute hold countdown
│       │   ├── active_session_screen.dart ← live running timer
│       │   ├── payment_screen.dart        ← mock payment + success animation
│       │   └── receipt_screen.dart        ← final summary
│       └── widgets/
│           ├── spot_bottom_sheet.dart     ← spot details + CTAs
│           └── license_plate_dialog.dart  ← plate capture before starting
│
└── README.md
```

---

## 2. Backend (Spring Boot)

### 2.1 What each class does

**`ParkingBuddyApplication`** — entry point that boots Spring and exposes the REST API.

**`ParkingSpot` (entity)** — one row in the `parking_spots` table: id, short code (e.g. `A12`), street name, zone, status (`available` / `reserved` / `occupied`), max duration in minutes, price per hour, and a PostGIS `geom` point.

**`ParkingSession` (entity)** — one row in the `parking_sessions` table: spot id, license plate, start time, end time, status (`active` / `completed`).

**`ParkingSpotRepository`** — extends `JpaRepository`, plus a native PostGIS query that returns available spots within a radius of a GPS coordinate, sorted by real-world distance.

**`ParkingSessionRepository`** — extends `JpaRepository`, plus `findByParkingSpotIdAndStatus` used to look up the active session when ending parking.

**`ParkingSpotService`** — runs the spatial query and maps raw result rows into JSON-friendly maps for the controller.

**`ParkingSessionService`** — owns the full parking lifecycle: `reserveSpot`, `startParking`, `endParking`, `cancelReservation`. Enforces status transitions and, on end, computes minutes parked and cost as `ceil(minutes / 60) * pricePerHour`.

**`ParkingSpotController`** — exposes `GET /api/spots/nearby`.

**`ParkingSessionController`** — exposes the four lifecycle endpoints under `/api/sessions/*`.

### 2.2 API endpoints

**Spot search**

| Method | URL | Parameters | Description |
|--------|-----|------------|-------------|
| `GET` | `/api/spots/nearby` | `lat`, `lon` (decimal); `radius` (meters, default 500); `limit` (default 20) | Returns available spots within the radius, sorted by distance. |

Example: `GET /api/spots/nearby?lat=41.9981&lon=21.4254`

**Session management**

| Method | URL | Body / Params | Description |
|--------|-----|---------------|-------------|
| `POST` | `/api/sessions/reserve/{spotId}` | `spotId` in path | Flips `available` → `reserved`. |
| `POST` | `/api/sessions/start/{spotId}` | `licensePlate` query param | Flips `available`/`reserved` → `occupied`, creates active session. |
| `POST` | `/api/sessions/end/{spotId}` | `spotId` in path | Ends the active session, flips `occupied` → `available`, returns `{ sessionId, minutes, cost }`. |
| `POST` | `/api/sessions/cancel/{spotId}` | `spotId` in path | Cancels a reservation (`reserved` → `available`). |

### 2.3 PostGIS spatial query

```sql
SELECT ...,
       ST_Distance(geom::geography,
                   ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography) AS distance
FROM parking_spots
WHERE status = 'available'
  AND ST_DWithin(geom::geography,
                 ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography,
                 :radius)
ORDER BY distance
LIMIT :limit
```

- `ST_MakePoint` + `ST_SetSRID(..., 4326)` builds a WGS 84 (GPS) point.
- `::geography` switches to real-world, curved-Earth math so `:radius` and `distance` are in meters.
- `ST_DWithin` filters by radius, `ST_Distance` is the exact distance, and `ORDER BY distance` returns the closest spots first.

### 2.4 Seed data (`data.sql`)

Runs on every startup (`spring.sql.init.mode=always`) to give a realistic, street-by-street snapshot. Every spot is first reset to `available`, then each street is randomized independently with its own target distribution so the map looks plausible instead of uniformly random:

| Street | Total | Available | Occupied | Reserved |
|--------|------:|----------:|---------:|---------:|
| Радњанска | 32 | 6 | 22 | 4 |
| Костурски Херои | 19 | 6 | 10 | 3 |
| Отон Жупанчиќ | 15 | 3 | 10 | 2 |
| Антоние Грубишиќ | 27 | 8 | 18 | 1 |
| Наум Наумовски - Борче | 24 | 4 | 18 | 2 |
| Коле Неделковски | 9 | 2 | 6 | 1 |
| Пиринска | 9 | 3 | 6 | 0 |
| Аминта Трети | 15 | 5 | 7 | 3 |
| Михаил Цоков | 100 | 13 | 80 | 7 |

On every startup the script:

1. Clears all rows from `parking_sessions` so the database starts from a clean session state.
2. Resets every spot to `available`.
3. For each street, randomly picks N spots and sets them to `occupied`.
4. For each street, from the remaining available spots on that same street, randomly picks M and sets them to `reserved`.

### 2.5 Database configuration

- PostgreSQL + PostGIS, database `ParkingBuddy`.
- Connection read from environment variables — nothing hardcoded:
  - `DB_URL` (e.g. `jdbc:postgresql://localhost:5432/ParkingBuddy`)
  - `DB_USERNAME`
  - `DB_PASSWORD`
- `spring.jpa.hibernate.ddl-auto=validate` — Hibernate validates the schema but never creates or mutates tables. Schema is owned by `backend/database_setup.sql`.

---

## 3. Frontend (Flutter)

A single-screen-rooted app (`MapScreen` is `home`) that drives the whole parking flow through pushed routes. UI copy is in Macedonian; the layout follows a green Material 3 theme with Noto Sans.

### 3.1 Dependencies (`pubspec.yaml`)

- `google_maps_flutter` — interactive map and custom markers
- `geolocator` — GPS acquisition
- `permission_handler` — runtime location permission
- `http` — REST calls to the backend
- `google_fonts` — Noto Sans typography
- `intl` — formatting durations, money, timestamps

### 3.2 Files

**`main.dart`** — boots the app, makes the status bar transparent, installs the theme, and sets `MapScreen` as the home.

**`theme.dart`** — `AppColors` (primary green `#1B5E20`, accent, warning, danger, surfaces) and `buildAppTheme()` which wires the colors into a Material 3 `ThemeData` with Google Fonts Noto Sans.

**`models/parking_spot.dart`** — immutable `ParkingSpot` with `fromJson`, plus `isAvailable` / `isReserved` / `isOccupied` helpers.

**`models/parking_session.dart`** — immutable `ParkingSession` mirroring the backend entity.

**`services/api_service.dart`** — thin wrapper over `http.Client` with typed methods: `getNearbySpots`, `reserveSpot`, `cancelReservation`, `startParking`, `endParking`. Throws a typed `ApiException` on non-2xx. Base URL is `http://10.0.2.2:8080` (Android emulator loopback to the host).

**`screens/map_screen.dart`** — Google Map centered on Skopje (`41.9981, 21.4254`) at zoom level 16.5, requests location permission, fetches nearby spots, renders colored markers by status, has an in-app search bar that filters by street / code / zone, and opens the spot bottom sheet on marker tap. The recenter FAB animates the camera back to the user's GPS position (or the Skopje fallback) at zoom 16.5 **and** re-requests nearby spots, which resets marker visibility — handy for reloading after the backend re-seeds statuses.

**`widgets/spot_bottom_sheet.dart`** — spot details (code, street, zone, distance, price, max duration) and the primary CTAs (Reserve, Start now).

**`widgets/license_plate_dialog.dart`** — modal that captures and validates the license plate before starting a session.

**`screens/reservation_screen.dart`** — 15-minute hold with a live countdown, a primary "I arrived" action that opens the plate dialog and calls `startParking`, and a cancel action that calls `cancelReservation`.

**`screens/active_session_screen.dart`** — live elapsed timer for the active session, spot + plate summary, and an end-parking action that calls `endParking` and forwards the returned cost and duration to payment.

**`screens/payment_screen.dart`** — mock payment method picker (card / Apple Pay / Google Pay), a processing state, and a success animation before navigating to the receipt.

**`screens/receipt_screen.dart`** — final summary: spot, plate, total time, total cost, payment method, transaction id.

### 3.3 UX flow

```
MapScreen
   │  tap marker
   ▼
SpotBottomSheet ──Reserve──► ReservationScreen ──I arrived──► LicensePlateDialog ──►
                                       │  cancel                                   │
                                       └─► MapScreen                               ▼
                                                                          ActiveSessionScreen
                                                                                   │  end
                                                                                   ▼
                                                                             PaymentScreen
                                                                                   │  success
                                                                                   ▼
                                                                             ReceiptScreen
```

---

## 4. Complete Parking Lifecycle (end to end)

```
1. FIND A SPOT
   App asks for location permission, reads GPS, and calls
   GET /api/spots/nearby?lat=...&lon=...
   → markers render on the Google Map, sorted by distance.

2. RESERVE (optional)
   User taps a marker → SpotBottomSheet → Reserve
   POST /api/sessions/reserve/{spotId}
   → spot: available → reserved, 15-minute hold starts in the app.

3. START PARKING
   User taps "I arrived", enters license plate
   POST /api/sessions/start/{spotId}?licensePlate=XYZ123
   → spot: reserved/available → occupied, new active ParkingSession,
     ActiveSessionScreen starts the running timer.

4. END PARKING
   User taps "End"
   POST /api/sessions/end/{spotId}
   → end time recorded, duration calculated, cost = ceil(minutes/60) * pricePerHour,
     spot: occupied → available, response { sessionId, minutes, cost }
     drives PaymentScreen.

5. PAY
   Mock method selection and success animation in PaymentScreen.

6. RECEIPT
   ReceiptScreen shows spot, plate, duration, cost, payment method, transaction id.

-- ALTERNATIVE --
   Cancel reservation before starting:
   POST /api/sessions/cancel/{spotId}
   → spot: reserved → available.
```

---

## 5. Running the Project Locally

### 5.1 Prerequisites

- JDK 17+
- PostgreSQL 14+ with the **PostGIS** extension installed
- Flutter SDK 3.11+
- Android Studio or a configured Android emulator (the frontend defaults to `10.0.2.2:8080`, the emulator's loopback to the host)

### 5.2 Database

```bash
# from repo root
psql -U postgres -c "CREATE DATABASE \"ParkingBuddy\";"
psql -U postgres -d ParkingBuddy -c "CREATE EXTENSION IF NOT EXISTS postgis;"
psql -U postgres -d ParkingBuddy -f backend/database_setup.sql
```

### 5.3 Backend

```bash
cd backend

# set DB credentials (PowerShell shown; use the equivalent in your shell)
$env:DB_URL="jdbc:postgresql://localhost:5432/ParkingBuddy"
$env:DB_USERNAME="postgres"
$env:DB_PASSWORD="your_password"

./mvnw spring-boot:run
```

The API listens on `http://localhost:8080`. `data.sql` reshuffles spot statuses on every boot.

### 5.4 Frontend

```bash
cd frontend
flutter pub get
flutter run          # on an Android emulator so 10.0.2.2 resolves to the backend
```

On a physical device or non-Android platform, update `_baseUrl` in `lib/services/api_service.dart` to your machine's LAN IP.
