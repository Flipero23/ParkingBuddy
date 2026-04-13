# ParkingBuddy — Project Overview

A Spring Boot REST API that helps drivers find nearby parking spots, reserve them, and track active parking sessions. It uses a PostgreSQL database with the PostGIS extension to handle location-based queries.

---

## 1. Project Structure

```
parking-buddy/
└── src/main/java/com/parkingbuddy/parking_buddy/
    ├── ParkingBuddyApplication.java        ← app entry point
    ├── entity/
    │   ├── ParkingSpot.java                ← represents a parking spot in the DB
    │   └── ParkingSession.java             ← represents an active or completed parking session
    ├── repository/
    │   ├── ParkingSpotRepository.java      ← database access for parking spots
    │   └── ParkingSessionRepository.java   ← database access for parking sessions
    ├── service/
    │   ├── ParkingSpotService.java         ← business logic for finding spots
    │   └── ParkingSessionService.java      ← business logic for reserving, starting, ending sessions
    └── controller/
        ├── ParkingSpotController.java      ← HTTP endpoints for spot queries
        └── ParkingSessionController.java   ← HTTP endpoints for session actions
```

---

## 2. What Each Class Does

### `ParkingBuddyApplication`
This is the starting point of the entire application. When you run the project, Java calls the `main` method here, which boots up the Spring framework and makes the API ready to receive requests.

### `ParkingSpot` (entity)
This class represents a single row in the `parking_spots` database table. Each parking spot has an ID, a short code (like "A12"), a street name, a zone, a status (available / reserved / occupied), a maximum allowed parking duration in minutes, and a price per hour. Spring JPA uses this class to automatically read and write spot data without manual SQL.

### `ParkingSession` (entity)
This class represents a single row in the `parking_sessions` table. A session is created whenever a driver starts parking. It stores which spot was used, the driver's license plate, when parking started, when it ended, and whether the session is active or completed.

### `ParkingSpotRepository`
This is the interface that talks directly to the database for parking spot data. It inherits standard database operations (find by ID, save, delete) from Spring's `JpaRepository`. It also contains one custom SQL query that finds available spots near a given GPS location using PostGIS.

### `ParkingSessionRepository`
This is the interface that talks directly to the database for session data. Like the spot repository, it inherits standard operations. It also has one custom method that finds an active session for a specific parking spot — used when ending a session.

### `ParkingSpotService`
This class contains the business logic for searching nearby spots. It calls the repository's spatial query and then converts the raw database results into a clean list of maps that can be sent back to the client as JSON. It acts as a translator between the database and the controller.

### `ParkingSessionService`
This class contains the core business logic for the entire parking lifecycle. It handles reserving a spot, starting a session (with license plate capture), ending a session and calculating cost, and cancelling a reservation. It enforces rules like "you can't start parking on an occupied spot" and coordinates updates across both the spot and session tables.

### `ParkingSpotController`
This class exposes one HTTP endpoint that lets clients search for nearby available parking spots by sending their GPS coordinates. It delegates all real work to `ParkingSpotService` and returns the result as JSON.

### `ParkingSessionController`
This class exposes four HTTP endpoints that cover the full parking lifecycle — reserve, start, end, and cancel. Each endpoint receives a spot ID from the URL, calls the appropriate method in `ParkingSessionService`, and returns the result as JSON.

---

## 3. API Endpoints

### Spot Search

| Method | URL | Parameters | What it does |
|--------|-----|------------|--------------|
| `GET` | `/api/spots/nearby` | `lat` (decimal), `lon` (decimal), `radius` (meters, default 500), `limit` (default 20) | Returns a list of available parking spots within the given radius of the GPS coordinates, sorted by distance. |

**Example:** `GET /api/spots/nearby?lat={your_lat}&lon={your_lon}&radius=300&limit=10`

---

### Session Management

| Method | URL | Parameters | What it does |
|--------|-----|------------|--------------|
| `POST` | `/api/sessions/reserve/{spotId}` | `spotId` in URL | Marks the spot as **reserved** so no one else can take it. Returns the updated spot. |
| `POST` | `/api/sessions/start/{spotId}` | `spotId` in URL, `licensePlate` as query param | Starts an active parking session. Records the license plate and start time, marks the spot as **occupied**. Returns the new session. |
| `POST` | `/api/sessions/end/{spotId}` | `spotId` in URL | Ends the active session for that spot. Records the end time, calculates the cost, marks the spot **available** again. Returns session ID, total minutes parked, and cost. |
| `POST` | `/api/sessions/cancel/{spotId}` | `spotId` in URL | Cancels a reservation (spot must be in **reserved** status). Marks it **available** again. Returns the updated spot. |

---

## 4. How the PostGIS Spatial Query Works

The `parking_spots` table has a special column called `geom` that stores the GPS location of each spot as a geometric point (longitude + latitude). PostGIS is a PostgreSQL extension that understands geometry — it can measure real-world distances on a curved Earth, not just flat math.

When a user searches for nearby spots, the app runs this query:

```sql
SELECT ..., ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography) AS distance
FROM parking_spots
WHERE status = 'available'
  AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography, :radius)
ORDER BY distance
LIMIT :limit
```

In plain English:
1. **`ST_MakePoint(:lon, :lat)`** — turns the user's coordinates into a point PostGIS understands.
2. **`ST_SetSRID(..., 4326)`** — tells PostGIS this point uses the WGS 84 coordinate system (the same one as GPS).
3. **`::geography`** — switches from flat-map math to real-world curved-Earth math, so distances are in meters, not degrees.
4. **`ST_DWithin(..., :radius)`** — filters out any spot that is farther than the requested radius (in meters).
5. **`ST_Distance(...)`** — calculates the exact distance from the user to each spot.
6. **`ORDER BY distance`** — puts the closest spots first.

The result is a list of available spots nearby, each with its distance from the user.

---

## 5. Complete Parking Lifecycle

```
1. FIND A SPOT
   Driver sends GPS location →
   GET /api/spots/nearby
   ← App returns list of available spots nearby, sorted by distance

2. RESERVE (optional)
   Driver picks a spot →
   POST /api/sessions/reserve/{spotId}
   ← Spot status changes: available → reserved
   (Holds the spot while the driver walks over)

3. START PARKING
   Driver arrives and starts the session →
   POST /api/sessions/start/{spotId}?licensePlate=ABC123
   ← Spot status changes: available/reserved → occupied
   ← A new ParkingSession is created with the current time and license plate

4. END PARKING
   Driver is done and ends the session →
   POST /api/sessions/end/{spotId}
   ← Session end time is recorded
   ← Duration in minutes is calculated
   ← Cost is calculated: ceil(minutes / 60) × price_per_hour
   ← Spot status changes: occupied → available
   ← Response includes sessionId, minutes parked, and total cost

-- ALTERNATIVE: CANCEL A RESERVATION --
   Driver changes their mind before starting →
   POST /api/sessions/cancel/{spotId}
   ← Spot status changes: reserved → available
```

---

## Test Data (`data.sql`)

Spring Boot automatically runs `src/main/resources/data.sql` on every startup. This file randomizes the database state to simulate a realistic parking lot:

1. Resets all spots to **available**
2. Randomly picks 80 spots and marks them **occupied**
3. From the remaining available spots, randomly picks 20 and marks them **reserved**
4. Clears all existing parking sessions so there are no leftover active sessions

This means every time the app starts, you get a fresh, realistic-looking snapshot of a busy parking area — without manually inserting test data.

---

## Database Configuration

- **Database:** PostgreSQL (local, port 5432)
- **Database name:** `ParkingBuddy`
- **Credentials:** Stored in environment variables (`SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`) — not hardcoded in any file.
- **Schema management:** `ddl-auto=validate` — Spring checks that the database tables match the entity classes at startup but does not create or modify tables automatically.
