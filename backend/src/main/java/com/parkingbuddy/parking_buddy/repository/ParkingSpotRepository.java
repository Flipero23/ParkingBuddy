package com.parkingbuddy.parking_buddy.repository;

import com.parkingbuddy.parking_buddy.entity.ParkingSpot;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface ParkingSpotRepository extends JpaRepository<ParkingSpot, Integer> {

    @Query(value = """
        SELECT id, code, street_name, zone, status,
               max_duration_minutes, price_per_hour,
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
}