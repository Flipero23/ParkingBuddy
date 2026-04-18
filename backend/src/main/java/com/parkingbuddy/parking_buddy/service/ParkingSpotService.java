package com.parkingbuddy.parking_buddy.service;

import com.parkingbuddy.parking_buddy.repository.ParkingSpotRepository;
import org.springframework.stereotype.Service;
import java.util.*;

@Service
public class ParkingSpotService {

    private final ParkingSpotRepository parkingSpotRepository;

    public ParkingSpotService(ParkingSpotRepository parkingSpotRepository) {
        this.parkingSpotRepository = parkingSpotRepository;
    }

    public List<Map<String, Object>> findNearbyAvailable(double lat, double lon, double radius, int limit) {
        List<Object[]> results = parkingSpotRepository.findNearbyAvailable(lat, lon, radius, limit);
        List<Map<String, Object>> spots = new ArrayList<>();

        for (Object[] row : results) {
            Map<String, Object> spot = new HashMap<>();
            spot.put("id", row[0]);
            spot.put("code", row[1]);
            spot.put("streetName", row[2]);
            spot.put("zone", row[3]);
            spot.put("status", row[4]);
            spot.put("maxDurationMinutes", row[5]);
            spot.put("pricePerHour", row[6]);
            spot.put("distance", row[7]);
            spot.put("latitude", row[8]);
            spot.put("longitude", row[9]);
            spots.add(spot);
        }

        return spots;
    }
}