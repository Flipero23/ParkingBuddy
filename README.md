# ParkingBuddy — Project Overview

ParkingBuddy is a full-stack smart parking app for Debar Maalo (Skopje). A Flutter mobile client lets drivers register, log in, save a license plate to their profile, top up a prepaid balance, find spots on a live Google Map, search by place name (Google Places Autocomplete), reserve them, start and (optionally) extend pre-paid parking sessions, and review their personal history. It is backed by a Spring Boot REST API with JWT authentication on top of a PostgreSQL + PostGIS database for location-aware spot lookup.

---

## 1. Repository Layout

```
parking_buddy/
├── backend/                                  ← Spring Boot REST API (Java 17, Maven)
│   ├── database_setup.sql                    ← one-time schema + PostGIS seed
│   ├── mvnw / mvnw.cmd                       ← Maven wrapper
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/parkingbuddy/parking_buddy/
│       │   ├── ParkingBuddyApplication.java
│       │   ├── entity/
│       │   │   ├── ParkingSpot.java
│       │   │   ├── ParkingSession.java       ← + userId, durationHours, paidAmount
│       │   │   └── User.java                 ← phone, password, name, card, balance, licensePlate
│       │   ├── repository/
│       │   │   ├── ParkingSpotRepository.java
│       │   │   ├── ParkingSessionRepository.java
│       │   │   └── UserRepository.java
│       │   ├── service/
│       │   │   ├── ParkingSpotService.java
│       │   │   ├── ParkingSessionService.java ← prepaid charging, extend, history, plate validation
│       │   │   ├── AuthService.java           ← register, login, profile, card, deposit, plate
│       │   │   └── LicensePlateValidator.java ← MK + foreign plate normalization & validation
│       │   ├── controller/
│       │   │   ├── ParkingSpotController.java
│       │   │   ├── ParkingSessionController.java
│       │   │   ├── SessionHistoryController.java
│       │   │   └── AuthController.java        ← + PUT /api/auth/profile
│       │   ├── dto/
│       │   │   ├── AuthResponse.java          ← + licensePlate
│       │   │   ├── LoginRequest.java
│       │   │   ├── RegisterRequest.java
│       │   │   ├── SaveCardRequest.java
│       │   │   ├── DepositRequest.java
│       │   │   └── UpdateProfileRequest.java  ← profile updates (currently licensePlate)
│       │   ├── exception/
│       │   │   ├── SpotUnavailableException.java ← thrown on reserve/start race → HTTP 409
│       │   │   ├── ResourceNotFoundException.java ← spot/user/session missing → HTTP 404
│       │   │   └── GlobalExceptionHandler.java   ← @RestControllerAdvice, JSON {message}
│       │   └── security/
│       │       ├── SecurityConfig.java        ← stateless JWT filter chain + BCrypt
│       │       ├── JwtUtil.java               ← sign/parse HS256 tokens
│       │       └── JwtAuthFilter.java         ← reads Authorization: Bearer …
│       └── resources/
│           ├── application.properties         ← DB_URL/USER/PASSWORD + jwt.secret
│           └── data.sql                       ← runs every startup, seeds users table + spot statuses
│
├── frontend/                                  ← Flutter app (Dart, Material 3)
│   ├── pubspec.yaml
│   ├── android/ ios/ web/ windows/ macos/ linux/
│   ├── test/
│   └── lib/
│       ├── main.dart                          ← bootstraps auth + notifications
│       ├── theme.dart                         ← green palette + Noto Sans typography
│       ├── models/
│       │   ├── parking_spot.dart              ← + toJson for active session persistence
│       │   ├── parking_session.dart
│       │   ├── active_session.dart            ← in-memory snapshot (toJson/fromJson)
│       │   └── place_suggestion.dart          ← Google Places autocomplete result
│       ├── services/
│       │   ├── api_service.dart               ← parking endpoints (sends Bearer token)
│       │   ├── auth_service.dart              ← login/register/profile/card/deposit/plate/history
│       │   ├── active_session_storage.dart    ← SharedPreferences persistence for active session
│       │   ├── notification_service.dart      ← 15-min "session ending" local notification
│       │   ├── places_service.dart            ← Google Places Autocomplete + Place Details
│       │   └── maps_config.dart               ← resolves the Maps API key (compile-time / native)
│       ├── screens/
│       │   ├── welcome_screen.dart            ← login / register / guest entry
│       │   ├── login_screen.dart
│       │   ├── register_screen.dart
│       │   ├── map_screen.dart                ← Google Map + nearby spots + place search + pan-to-refresh
│       │   ├── reservation_screen.dart        ← 15-minute hold countdown
│       │   ├── active_session_screen.dart     ← prepaid countdown + extend
│       │   ├── payment_screen.dart            ← prepayment confirmation + success animation
│       │   ├── deposit_processing_screen.dart ← top-up confirmation + success animation
│       │   ├── receipt_screen.dart            ← final summary
│       │   ├── profile_screen.dart            ← balance, card, license plate, deposit, history, logout
│       │   └── history_screen.dart            ← past sessions for the logged-in user
│       └── widgets/
│           ├── spot_bottom_sheet.dart         ← spot details + CTAs (with plate prefill)
│           ├── license_plate_dialog.dart      ← plate capture/edit; MK + foreign validation
│           ├── duration_picker_dialog.dart    ← 1h or 2h prepaid choice
│           ├── payment_method_dialog.dart     ← saved card / new card / Apple Pay / Google Pay
│           ├── card_input_dialog.dart         ← card capture & validation
│           └── deposit_dialog.dart            ← top-up amount entry
│
└── README.md
```

---

## 2. Backend (Spring Boot)

### 2.1 What each class does

**`ParkingBuddyApplication`** — entry point that boots Spring and exposes the REST API.

**Entities**

- **`ParkingSpot`** — one row in `parking_spots`: id, short code (e.g. `MC-082`), street name, zone, status (`available` / `reserved` / `occupied`), max duration (minutes), price per hour, and a PostGIS `geom` point.
- **`ParkingSession`** — one row in `parking_sessions`: spot id, user id, license plate, start time, end time, status (`active` / `completed`), prepaid `durationHours` (1 or 2), and `paidAmount`.
- **`User`** — one row in `users`: id, phone number (unique, normalized to `+389…`), BCrypt password hash, first name, last name, optional masked card details (`**** **** **** 1234`, `MM/YY`, cardholder name), `balance` (MKD), and an optional saved `licensePlate` used to pre-fill the start-parking dialog.

**Repositories** — Spring Data JPA over the entities. `ParkingSpotRepository` adds a native PostGIS query for nearby available spots **and a `findByIdForUpdate` finder annotated with `@Lock(LockModeType.PESSIMISTIC_WRITE)`** that issues `SELECT … FOR UPDATE`, used by every mutating session operation to serialize concurrent access on the same row. `ParkingSessionRepository` adds `findByParkingSpotIdAndStatus` and `findByUserIdOrderByStartTimeDesc`. `UserRepository` adds `findByPhoneNumber` and `existsByPhoneNumber`.

**Services**

- **`ParkingSpotService`** — runs the spatial query and shapes raw rows into JSON-friendly maps.
- **`ParkingSessionService`** — owns the parking lifecycle. Every mutating method is `@Transactional` and reads the spot through the locking finder, so two users tapping the same spot can never both succeed:
  - `reserveSpot` — locks the spot row, verifies status is still `available`, then flips to `reserved`. Throws `SpotUnavailableException` (→ HTTP 409) if the spot has been claimed in the meantime.
  - `startParking` — accepts `licensePlate`, `durationHours` (1 or 2) and `userId`. The plate is normalized + validated through `LicensePlateValidator` (mirrors the Flutter rules; `IllegalArgumentException` on bad input → HTTP 400). Locks the spot, re-checks the status under the lock (rejects with 409 if no longer `available`/`reserved`), charges `pricePerHour × durationHours` from the user's balance (throws on insufficient funds), flips the spot to `occupied`, and stores the prepaid amount on the session.
  - `extendParking` — adds one extra hour to an active 1-hour session (max 2). Authorizes the call against the session's userId and charges another hour from the user's balance.
  - `endParking` — closes the active session, flips the spot back to `available`, and returns `{ sessionId, minutes, cost, durationHours }` driven from the prepaid values.
  - `cancelReservation` — `reserved` → `available` under the row lock.
  - `getHistoryForUser` — joins sessions with their spots and returns a sorted list (most recent first) including spot code, street, zone, license plate, start/end times, paid duration, and total cost.
- **`LicensePlateValidator`** — pure utility used by both the start-parking flow and the profile-update endpoint. Trims, strips inner whitespace, uppercases, and validates: Macedonian plates must be `[A-Z]{2}\d{3,4}[A-Z]{2}` with a city code from the allowed set (BE, BT, DB, …); foreign plates must match `[A-Z0-9-]{2,12}`. Rejects everything else with a user-facing message (mapped to HTTP 400 by the global handler).
- **`AuthService`** — owns user-facing auth and account state:
  - `register` — validates phone, password (≥4 chars), first/last name; rejects duplicate phone numbers; BCrypts the password; issues a 30-day JWT.
  - `login` — verifies BCrypted password; issues a 30-day JWT.
  - `getUserProfile` — returns the user (without token) for the authenticated id.
  - `updateProfile` — currently carries `licensePlate` only. A null/blank value clears the saved plate; anything else is normalized + validated through `LicensePlateValidator`. Returns the refreshed `AuthResponse`.
  - `saveCard` / `deleteCard` — stores only a masked card number (`**** **** **** 1234`) plus expiry and cardholder name; never persists the raw PAN.
  - `deposit` — validates amount (`> 0`, `≤ 2000` MKD per transaction), increments balance.
  - Phone numbers are normalized at registration and login (`07X…`, `389…`, `00389…`, `+389…` all collapse to `+389…`).

**Security**

- **`SecurityConfig`** — stateless filter chain. CSRF disabled (token-based, mobile client). All requests `permitAll`; controllers enforce auth themselves by reading `request.getAttribute("userId")` (set by the JWT filter) and returning `401` when it is absent. `BCryptPasswordEncoder` is exposed as a bean.
- **`JwtUtil`** — signs and parses HS256 JWTs (`subject = userId`, custom claim `phoneNumber`, 30-day expiry). The signing key comes from `${jwt.secret}`.
- **`JwtAuthFilter`** — `OncePerRequestFilter` that reads `Authorization: Bearer <token>`, validates it, populates `SecurityContextHolder`, and stashes `userId` / `phoneNumber` as request attributes for the controllers.

**Controllers**

- **`ParkingSpotController`** — `GET /api/spots/nearby`.
- **`ParkingSessionController`** — `reserve`, `start`, `extend`, `end`, `cancel`.
- **`SessionHistoryController`** — `GET /api/sessions/history` (per-user).
- **`AuthController`** — `register`, `login`, `profile` (GET + PUT), `card` (save/delete), `deposit`.

**Exception handling**

A `@RestControllerAdvice` (`GlobalExceptionHandler`) maps domain exceptions to consistent JSON error bodies of the form `{"message": "..."}`:

| Exception | Status | Use |
|-----------|-------:|-----|
| `SpotUnavailableException` | 409 | Spot already reserved/occupied — race protection on reserve/start. |
| `ResourceNotFoundException` | 404 | Spot, user, or active session does not exist. |
| `IllegalArgumentException` | 400 | Invalid duration, bad license plate, insufficient balance, validation failures. |
| Other `RuntimeException`    | 400 | Generic fallback (no stack traces leak to clients). |

### 2.2 API endpoints

**Spot search**

| Method | URL | Parameters | Description |
|--------|-----|------------|-------------|
| `GET` | `/api/spots/nearby` | `lat`, `lon` (decimal); `radius` (meters, default 500); `limit` (default 20) | Returns available spots within the radius, sorted by distance. |

Example: `GET /api/spots/nearby?lat=41.9981&lon=21.4254`

**Session management** (Bearer token required to bind a session to a user; license plate-only flow still works for guests, but with no balance charge and no history)

| Method | URL | Body / Params | Description |
|--------|-----|---------------|-------------|
| `POST` | `/api/sessions/reserve/{spotId}` | path: `spotId` | Atomically flips `available` → `reserved` under a `SELECT … FOR UPDATE` row lock. **409** if the spot is no longer available. |
| `POST` | `/api/sessions/start/{spotId}` | query: `licensePlate`, `durationHours` (1 or 2, default 1) | Validates plate, atomically charges `pricePerHour × durationHours` from the authenticated user's balance, flips spot to `occupied`, creates an `active` session with the prepaid amount. **409** if the spot was claimed by another user before the request committed; **400** for invalid plate / duration / insufficient funds. |
| `POST` | `/api/sessions/extend/{spotId}` | — | Adds one more hour (only if current duration is 1). Charges one extra hour from the user's balance. |
| `POST` | `/api/sessions/end/{spotId}` | — | Ends the active session, flips spot to `available`, returns `{ sessionId, minutes, cost, durationHours }` from the prepaid totals. |
| `POST` | `/api/sessions/cancel/{spotId}` | — | Cancels a reservation (`reserved` → `available`). |
| `GET`  | `/api/sessions/history` | — | Returns the authenticated user's past sessions, newest first. |

Conflict response shape (HTTP 409):

```json
{ "message": "Parking spot is no longer available" }
```

**Authentication and account**

| Method | URL | Body | Description |
|--------|-----|------|-------------|
| `POST` | `/api/auth/register` | `{ phoneNumber, password, firstName, lastName }` | Creates an account, returns `AuthResponse` with JWT. |
| `POST` | `/api/auth/login` | `{ phoneNumber, password }` | Returns `AuthResponse` with JWT. |
| `GET`  | `/api/auth/profile` | — | Returns the authenticated user (no token in the body). |
| `PUT`  | `/api/auth/profile` | `{ licensePlate }` | Saves / clears the user's default license plate. Null or empty clears it; any non-empty value is normalized and validated. |
| `POST` | `/api/auth/card` | `{ cardNumber, cardExpiry, cardholderName }` | Saves a card; only a masked number is persisted. |
| `DELETE` | `/api/auth/card` | — | Removes the saved card. |
| `POST` | `/api/auth/deposit` | `{ amount }` | Tops up the balance (`0 < amount ≤ 2000` MKD). |

`AuthResponse` shape:

```json
{
  "token": "<JWT, present on register/login only>",
  "userId": 1,
  "phoneNumber": "+38970123456",
  "firstName": "Ana",
  "lastName": "Petrova",
  "cardNumber": "**** **** **** 1234",
  "cardExpiry": "12/27",
  "cardholderName": "ANA PETROVA",
  "balance": 350.00,
  "licensePlate": "SK1234AB"
}
```

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

### 2.4 Concurrency: how two users can't reserve the same spot

The reserve and start flows are protected by two layered guards:

1. **Row-level pessimistic lock.** `ParkingSpotRepository.findByIdForUpdate(id)` issues `SELECT … FOR UPDATE` inside the service's `@Transactional` boundary. The first transaction holds the row lock; any concurrent transaction that calls the same finder blocks until the first one commits or rolls back.
2. **Recheck-under-lock.** Once the lock is acquired, the service re-reads the status. If it is no longer `available` (or, for `startParking`, also not `reserved`), it throws `SpotUnavailableException`, which `GlobalExceptionHandler` maps to **HTTP 409** with `{"message": "Parking spot is no longer available"}`.

`startParking` adds a belt-and-braces check that no `active` session row already exists for the spot before creating a new one.

The frontend treats 409 as a first-class signal: the spot bottom sheet closes, a friendly Macedonian snackbar appears (`Местото веќе не е достапно`), nearby spots are refreshed, and **no local active session is created**. The reserve and start buttons are disabled while a request is in flight to prevent double-tap races on the client side as well.

### 2.5 License plate validation (shared rules)

`LicensePlateValidator` is the single source of truth on the backend, and `LicensePlateDialog.isValidMkPlate` mirrors it on the client, so both sides accept exactly the same set of plates:

- **Macedonian:** `[A-Z]{2}\d{3,4}[A-Z]{2}` with the leading two letters constrained to the allowed city-code set (BE, BT, DB, DE, DH, DK, GE, GV, KA, KI, KO, KR, KP, KS, KU, MB, MK, NE, OH, PP, PE, PS, RA, RE, SK, SN, SR, ST, SU, TE, VA, VE, VI, VV).
- **Foreign:** any string of 2–12 uppercase letters, digits, or dashes.

Input is trimmed, inner whitespace stripped, and uppercased before validation. Invalid plates produce a 400 from both `POST /api/sessions/start/{spotId}` and `PUT /api/auth/profile`.

### 2.6 Seed data (`data.sql`)

Runs on every startup (`spring.sql.init.mode=always`). It now also keeps the `users` table and per-user history intact across restarts:

1. Creates `users` if missing and adds the `balance`, `first_name`, `last_name`, and `license_plate` columns idempotently with `IF NOT EXISTS`.
2. Adds `user_id`, `duration_hours`, `paid_amount` columns to `parking_sessions` if missing (FK `user_id → users(id)`).
3. Closes any leftover `active` sessions (sets `status='completed'`, fills missing `end_time`) so randomized spot state stays consistent — but does not delete history.
4. Resets every spot to `available`, then randomly samples per-street targets to recreate a plausible occupancy pattern:

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

### 2.7 Database configuration

- PostgreSQL + PostGIS, database `ParkingBuddy`.
- Connection read from environment variables — nothing hardcoded:
  - `DB_URL` (e.g. `jdbc:postgresql://localhost:5432/ParkingBuddy`)
  - `DB_USERNAME`
  - `DB_PASSWORD`
- `spring.jpa.hibernate.ddl-auto=validate` — Hibernate validates the schema but never creates or mutates tables. Schema is owned by `backend/database_setup.sql` plus the idempotent migrations in `data.sql`.
- `jwt.secret` is read from `application.properties`. **Replace this with a strong, environment-specific secret before any non-local deployment** — the bundled value is a placeholder for local development only.

---

## 3. Frontend (Flutter)

A Material 3 app with a green theme and Noto Sans typography. UI copy is in Macedonian. The home screen depends on auth state at boot:

- If a stored JWT is found and validates, the app launches directly into `MapScreen`.
- Otherwise, `WelcomeScreen` is shown (login / register / continue as guest).

### 3.1 Dependencies (`pubspec.yaml`)

| Package | Purpose |
|---------|---------|
| `google_maps_flutter` | Interactive map and custom markers |
| `geolocator` | GPS acquisition |
| `permission_handler` | Runtime location permission |
| `http` | REST calls to the backend and to Google Places / Geocoding |
| `google_fonts` | Noto Sans typography |
| `intl` | Formatting durations, money, timestamps |
| `shared_preferences` | Persist JWT and the active session across launches |
| `flutter_local_notifications` | Schedule local notifications |
| `timezone` / `flutter_timezone` | Resolve the device timezone for scheduled notifications |

### 3.2 Files

**`main.dart`** — initializes notifications, loads any stored JWT (auto-fetches `/api/auth/profile` to refresh balance, name, and saved license plate), and routes to `MapScreen` (logged in) or `WelcomeScreen` (logged out).

**`theme.dart`** — `AppColors` (primary green `#1B5E20`, accent, warning, danger, surfaces) and `buildAppTheme()` which wires the colors into a Material 3 `ThemeData` with Google Fonts Noto Sans.

**Models**

- **`models/parking_spot.dart`** — immutable `ParkingSpot` with `fromJson` / `toJson`, plus `isAvailable` / `isReserved` / `isOccupied` helpers. `toJson` enables nesting inside `ActiveSession` for persistence.
- **`models/parking_session.dart`** — immutable `ParkingSession` mirroring the backend entity (including `durationHours` and `paidAmount`).
- **`models/active_session.dart`** — in-memory snapshot of the currently active session (spot, license plate, start time, prepaid duration, paid amount) with `copyWith`, `toJson`, and `fromJson`. Used by `MapScreen` to render the minimized timer card and to persist the session across app restarts.
- **`models/place_suggestion.dart`** — single autocomplete result returned by `PlacesService`: `placeId`, `label` (place name when available, otherwise address line), optional `secondary` address line, and optional `latitude` / `longitude` (populated by `getDetails` or by the Geocoding fallback).

**Services**

- **`services/api_service.dart`** — wraps the parking endpoints (`getNearbySpots`, `reserveSpot`, `cancelReservation`, `startParking` (with `durationHours`), `extendParking`, `endParking`). Automatically attaches `Authorization: Bearer <token>` when an `AuthService` is provided. Throws `ApiException(message, statusCode)` on non-2xx; the UI inspects `statusCode == 409` to surface the friendly "spot no longer available" path. Error messages are extracted from the backend's `{"message": "..."}` envelope.
- **`services/auth_service.dart`** — JWT-aware client over the `/api/auth/*` and `/api/sessions/history` endpoints: `register`, `login`, `logout`, `getProfile`, `updateLicensePlate`, `saveCard`, `deleteCard`, `deposit`, `getHistory`. Caches the token + user fields (including the saved license plate) in memory and persists the token to `SharedPreferences`. Decodes the JWT locally to recover `userId` / `phoneNumber` while the network call to `/profile` refreshes balance, name, card state, and plate. Exposes `licensePlate` as a getter so the start-parking flow can pre-fill the dialog. Throws `AuthException` on non-2xx.
- **`services/active_session_storage.dart`** — thin wrapper over `SharedPreferences` (`save`, `load`, `clear`) that persists the active `ActiveSession` JSON. Wired into every session lifecycle event in `MapScreen` so a parked session survives app termination, backgrounding, or emulator restarts.
- **`services/notification_service.dart`** — singleton wrapping `flutter_local_notifications`. Initializes the timezone database, requests Android notification permission, and exposes `scheduleExpiryWarning(DateTime fireAt)` / `cancelExpiryWarning()`. Used to remind the driver 15 minutes before a prepaid session expires.
- **`services/places_service.dart`** — Google Places search backing the in-app search bar. Calls **Places Autocomplete** for typed queries (returns named results like "Casa Bar" rather than just street + number), resolves coordinates via **Place Details** when the user taps a suggestion, and falls back to the **Geocoding API** (with a Skopje-biased bounding box) when Autocomplete returns zero results or fails. Uses the Macedonian language hint and biases results toward the current map center / Skopje. Logs are debug-only and the API key is redacted in the URL log line.
- **`services/maps_config.dart`** — single source of truth for the runtime Google API key. Resolves it from `--dart-define=MAPS_API_KEY=...` first, then falls back to a native `MethodChannel` (`parking_buddy/config`, method `getMapsApiKey`) that reads the existing `com.google.android.geo.API_KEY` meta-data from `AndroidManifest.xml`, which itself is populated from `android/local.properties`. The result is cached for the app's lifetime.

**Screens**

- **`screens/welcome_screen.dart`** — animated landing with login, register, and "continue as guest" actions.
- **`screens/login_screen.dart`** — phone + password form, error feedback, link to register.
- **`screens/register_screen.dart`** — first/last name + phone + password (with confirmation) form.
- **`screens/map_screen.dart`** — Google Map centered on Skopje (`42.0003, 21.4177`) at zoom 16.5, requests location permission, fetches nearby spots, renders colored markers by status, and opens the spot bottom sheet on marker tap. Top-right action bar links to `ProfileScreen`.
  - **Search bar.** A Macedonian-language search bar lives at the top of the map. Local matches against spot code / street / zone are shown first; if the query has no local match the bar debounces a **Google Places Autocomplete** call (`PlacesService`) and shows up to 6 suggestions with a `place` icon. Selecting a place fetches its coordinates via Place Details, animates the camera there, drops a **red destination pin**, and triggers a fresh `getNearbySpots` request around the selected coordinates.
  - **Pan-to-refresh.** `onCameraIdle` debounces (~400 ms) and refetches nearby spots whenever the camera has moved more than ~50 m from the last fetch center. The destination and active-session markers are composed on top of `_spotMarkers` so they survive every refresh.
  - **Recenter FAB.** Animates the camera back to GPS (or the Skopje fallback) at zoom 16.5 *and* re-requests nearby spots, useful after the backend re-seeds statuses.
  - **Performance optimizations.** Marker loading is deferred until both the GoogleMap platform view is ready (`onMapCreated`) and the location flow has resolved, so the platform view, location services, and ~100-marker render don't compete for the main thread. The 1 Hz session timer updates a `ValueNotifier` instead of calling `setState`, so each tick rebuilds only the small timer text rather than the GoogleMap tree.
  - **Active session lifecycle.** When a session starts, MapScreen takes over from the bottom sheet, persists the session via `ActiveSessionStorage`, replaces all spot markers with a single azure "parked car" marker, and shows a floating timer card that expands the session screen on tap. On app restart the session is restored from disk, the camera centers on the parked car, and expired sessions are auto-cleared.
- **`screens/reservation_screen.dart`** — 15-minute hold with a live countdown, "I arrived" → license plate dialog (pre-filled from profile when set) → `startParking`, and a cancel action that calls `cancelReservation`.
- **`screens/active_session_screen.dart`** — live elapsed timer for the active prepaid session, plate + spot summary, and an "extend by 1 hour" action (only when the current duration is 1 hour) that calls `extendParking`. End-parking transitions to the receipt directly using the prepaid totals returned from the backend. The screen is minimizable: a back/down chevron pops back to `MapScreen` with `ActiveSessionResult.minimized` (session keeps running, the floating timer card stays visible on the map); ending a session pops with `ActiveSessionResult.ended`, which clears persisted state and reloads spot markers.
- **`screens/payment_screen.dart`** — pre-charge confirmation: choose payment method (saved card / new card / Apple Pay / Google Pay) and watch the success animation before navigating to the receipt.
- **`screens/deposit_processing_screen.dart`** — uses the same processing → success animation as `PaymentScreen` while a balance top-up settles. Pops `true` on success.
- **`screens/receipt_screen.dart`** — final summary: spot, plate, total time, total cost, payment method, transaction id.
- **`screens/profile_screen.dart`** — sectioned account screen:
  - Header (name, phone).
  - **Wallet tile** — current balance, deposit button (opens `DepositDialog` → `DepositProcessingScreen`).
  - **Card tile** — add / delete saved card via `CardInputDialog`.
  - **License plate tile** — shows the saved plate or a "no plate" empty state, with edit and remove actions. Edit opens `LicensePlateDialog` pre-filled with the current value and persists via `AuthService.updateLicensePlate`. Remove sends `licensePlate: null` to clear it.
  - **Activity** — entry to `HistoryScreen`.
  - Logout.
- **`screens/history_screen.dart`** — pull-to-refresh list of the logged-in user's past sessions (street, code, plate, paid duration, total cost, status, start/end timestamps).

**Widgets**

- **`widgets/spot_bottom_sheet.dart`** — spot details (code, street, zone, distance, price, max duration) plus the CTAs (Reserve, Start now). Stateful: both buttons are disabled with an inline spinner while a request is in flight, blocking double taps. On a backend `409 Conflict` the sheet closes, a Macedonian snackbar (`Местото веќе не е достапно`) is shown, nearby spots are refreshed, and **no local active session is created**. Hosts the shared `startParkingFlow` (license plate (pre-filled from `AuthService.licensePlate` when present) → duration → payment → backend `start` → receipt → active session) which applies the same 409 handling at the end of the flow.
- **`widgets/license_plate_dialog.dart`** — captures and validates the license plate. Exposes `LicensePlateDialog.validCityCodes`, `LicensePlateDialog.mkPlateRegex`, and `LicensePlateDialog.isValidMkPlate(...)` as public static members so the rest of the app (profile screen, parking flow) can re-use the exact same validation as the backend. Accepts an optional `initialValue` which seeds the input and auto-selects the Macedonian / Foreign mode based on whether the seed validates as MK.
- **`widgets/duration_picker_dialog.dart`** — 1 hour vs 2 hours prepaid duration picker (the only two allowed values).
- **`widgets/payment_method_dialog.dart`** — saved card / new card / Apple Pay / Google Pay selection. Returns a `PaymentMethodSelection` describing the chosen method and any newly entered card.
- **`widgets/card_input_dialog.dart`** — masked card number, MM/YY expiry, and cardholder name capture with validation.
- **`widgets/deposit_dialog.dart`** — top-up amount entry (`0 < amount ≤ 2000` MKD).

### 3.3 UX flow

```
WelcomeScreen ──Login/Register──► (JWT persisted, profile + plate cached)
       │guest                                       │
       ▼                                            ▼
                              MapScreen ────► ProfileScreen ──► HistoryScreen
                                 │                  │
                                 │search ▼          ├─Add/Delete card
                                 │ Places Autocomplete + red destination pin
                                 │                  ├─Edit/Remove license plate
                                 │tap marker        ├─Deposit ──► DepositProcessingScreen
                                 ▼                  └─Logout
                          SpotBottomSheet
                                 │
              ┌──Reserve─────────┴──────────Start now──┐
              ▼                                        ▼
       ReservationScreen ─I arrived─►  LicensePlateDialog (prefill from profile)
              │   cancel                    │
              └─► MapScreen                 ▼
                                     DurationPickerDialog ─► PaymentMethodDialog
                                              │
                                              ▼
                                        PaymentScreen (prepay)
                                              │ success
                                              ▼
                                     ActiveSessionScreen
                                          │      │
                                          │      └─Extend (+1h, prepaid)
                                          │ end
                                          ▼
                                     ReceiptScreen
```

---

## 4. Complete Parking Lifecycle (end to end)

```
0. ACCOUNT (optional but required to charge from balance / save history)
   Register or log in via /api/auth/register or /api/auth/login.
   Frontend stores the JWT in SharedPreferences and sends it as
   Authorization: Bearer <token> on every subsequent call.

   Top up balance:
     POST /api/auth/deposit { amount }       // 0 < amount ≤ 2000 MKD

   Save default license plate (optional, pre-fills the parking flow):
     PUT /api/auth/profile { licensePlate }  // null/empty clears it

1. FIND A SPOT
   App asks for location permission, reads GPS, and calls
   GET /api/spots/nearby?lat=...&lon=...
   → markers render on the Google Map, sorted by distance.

   Search:
     - Local match against spot code / street / zone, or
     - Google Places Autocomplete via PlacesService → place details →
       red destination pin + getNearbySpots around the selected place.
   Pan: onCameraIdle refreshes nearby spots whenever the camera moves
        more than ~50 m from the last fetch center.

2. RESERVE (optional)
   Tap a marker → SpotBottomSheet → Reserve
   POST /api/sessions/reserve/{spotId}
   → backend locks the spot row (SELECT … FOR UPDATE), verifies it's still
     available, and flips available → reserved. If a concurrent user
     already claimed it the request fails with 409 Conflict.
   → on success: 15-minute hold starts in the app.

3. START PARKING (prepaid)
   Tap "I arrived" / "Start now". The license plate dialog opens,
   pre-filled from the user's saved plate when set. Pick 1 or 2 hours,
   confirm payment method.
   POST /api/sessions/start/{spotId}?licensePlate=XYZ123&durationHours=2
   → plate is normalized + validated (mirrors LicensePlateDialog rules)
   → backend locks the spot row, re-checks the status, and rejects with
     409 Conflict if it was claimed in the meantime.
   → user balance is debited pricePerHour × durationHours
   → spot: reserved/available → occupied
   → new active ParkingSession with paidAmount + durationHours
   → MapScreen persists an ActiveSession via ActiveSessionStorage and
     replaces the marker grid with a single "parked car" marker.
   → ActiveSessionScreen starts the running timer + schedules a local
     notification 15 minutes before expiry.

4. EXTEND (optional, only when current duration is 1 hour)
   POST /api/sessions/extend/{spotId}
   → balance is debited one more hour
   → durationHours becomes 2, paidAmount increased accordingly.

5. END PARKING
   POST /api/sessions/end/{spotId}
   → end time recorded, spot: occupied → available
   → response { sessionId, minutes, cost, durationHours } drives ReceiptScreen.

6. RECEIPT
   ReceiptScreen shows spot, plate, prepaid duration, paid amount,
   payment method, transaction id.

7. HISTORY
   GET /api/sessions/history → ProfileScreen → HistoryScreen lists every
   completed session for the authenticated user.

-- ALTERNATIVE --
   Cancel reservation before starting:
   POST /api/sessions/cancel/{spotId}
   → spot: reserved → available.

-- CONCURRENCY --
   If two users tap the same spot at almost the same time, both reserve
   and start operations are serialized on a row-level pessimistic lock in
   the database. The first request wins; the second receives:
       HTTP 409  { "message": "Parking spot is no longer available" }
   The Flutter client closes the bottom sheet, shows a snackbar, and
   refreshes nearby spots — no stale local active session is created.

-- RESTART --
   Active sessions survive app termination: ActiveSessionStorage saves
   the ActiveSession JSON to SharedPreferences on start, extend, and
   update; on next launch MapScreen restores it, recenters on the parked
   spot, and resumes the timer. Sessions whose paid duration already
   elapsed while the app was closed are auto-cleared on restore.
```

---

## 5. Running the Project Locally

### 5.1 Prerequisites

- JDK 17+
- PostgreSQL 14+ with the **PostGIS** extension installed
- Flutter SDK 3.11+
- Android Studio or a configured Android emulator (the frontend defaults to `10.0.2.2:8080`, the emulator's loopback to the host)
- A Google Cloud project with **Maps SDK for Android**, **Places API**, and **Geocoding API** enabled, and an API key

### 5.2 Database

```bash
# from repo root
psql -U postgres -c "CREATE DATABASE \"ParkingBuddy\";"
psql -U postgres -d ParkingBuddy -c "CREATE EXTENSION IF NOT EXISTS postgis;"
psql -U postgres -d ParkingBuddy -f backend/database_setup.sql
```

The `users` table (including the `license_plate` column) and the additional columns on `parking_sessions` (`user_id`, `duration_hours`, `paid_amount`) are created idempotently by `data.sql` on the next backend startup, so no extra migration step is required.

### 5.3 Backend

```bash
cd backend

# set DB credentials (PowerShell shown; use the equivalent in your shell)
$env:DB_URL="jdbc:postgresql://localhost:5432/ParkingBuddy"
$env:DB_USERNAME="postgres"
$env:DB_PASSWORD="your_password"

./mvnw spring-boot:run
```

The API listens on `http://localhost:8080`. `data.sql` reshuffles spot statuses on every boot but preserves the `users` table and historical sessions.

> **Note on `jwt.secret`**: the value in `application.properties` is a development placeholder. For any non-local deployment, override it via an environment variable or external config and treat it like any other production secret.

### 5.4 Frontend

```bash
cd frontend
flutter pub get
flutter run          # on an Android emulator so 10.0.2.2 resolves to the backend
```

On a physical device or non-Android platform, update `_baseUrl` in `lib/services/api_service.dart` **and** `lib/services/auth_service.dart` to your machine's LAN IP.

### 5.5 Google Maps / Places API key

The Flutter app reads the API key once via `MapsConfig.apiKey()` and uses it for both the Google Map view (Android Maps SDK) and the in-app search (Places Autocomplete + Place Details, with a Geocoding fallback).

**Recommended (Android):** put the key in `frontend/android/local.properties` (already gitignored):

```
MAPS_API_KEY=<YOUR_GOOGLE_MAPS_API_KEY>
```

It will be inlined into `AndroidManifest.xml` as `com.google.android.geo.API_KEY` (existing manifest placeholder), and `MapsConfig` will pick it up at runtime via the `parking_buddy/config` MethodChannel — no extra `--dart-define` needed.

**Alternative (any platform):** pass it at compile time:

```bash
flutter run --dart-define=MAPS_API_KEY=<YOUR_GOOGLE_MAPS_API_KEY>
```

For HTTP-based services (Places Autocomplete, Place Details, Geocoding) the key must allow direct HTTP API calls — i.e. it cannot be restricted exclusively to the Android package + SHA-1, because Maps-SDK restrictions don't apply to those REST endpoints. If Autocomplete returns `REQUEST_DENIED`, broaden the key restriction or use a separate key for HTTP calls.
