package com.parkingbuddy.parking_buddy.repository;

import com.parkingbuddy.parking_buddy.entity.ParkingSpot;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ParkingSpotRepository extends JpaRepository<ParkingSpot, Integer> {

    @Query(value = """
    SELECT id, code, street_name, zone, status,
           max_duration_minutes, price_per_hour,
           ST_Y(geom) AS latitude,
           ST_X(geom) AS longitude,
           ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography) AS distance
    FROM parking_spots
    WHERE status = 'available'
      AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography, :radius)
    ORDER BY distance
    LIMIT :limit
""", nativeQuery = true)
    List<Object[]> findNearbyAvailable(
            @Param("lat") double lat,
            @Param("lon") double lon,
            @Param("radius") double radius,
            @Param("limit") int limit
    );

    /**
     * Loads a spot with a row-level write lock (`SELECT ... FOR UPDATE`).
     *
     * Must be called inside a transaction. Concurrent callers attempting to
     * lock the same row will block until the first transaction commits or
     * rolls back, which makes the reserve/start flow safe against
     * two-users-one-spot races.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM ParkingSpot s WHERE s.id = :id")
    Optional<ParkingSpot> findByIdForUpdate(@Param("id") Integer id);
}
