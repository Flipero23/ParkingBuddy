package com.parkingbuddy.parking_buddy.controller;

import com.parkingbuddy.parking_buddy.service.ParkingSpotService;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/spots")
public class ParkingSpotController {

    private final ParkingSpotService parkingSpotService;

    public ParkingSpotController(ParkingSpotService parkingSpotService) {
        this.parkingSpotService = parkingSpotService;
    }

    @GetMapping("/nearby")
    public List<Map<String, Object>> getNearbySpots(
            @RequestParam double lat,
            @RequestParam double lon,
            @RequestParam(defaultValue = "500") double radius,
            @RequestParam(defaultValue = "20") int limit) {
        return parkingSpotService.findNearbyAvailable(lat, lon, radius, limit);
    }
}