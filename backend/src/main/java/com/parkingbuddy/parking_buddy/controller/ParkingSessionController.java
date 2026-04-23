package com.parkingbuddy.parking_buddy.controller;

import com.parkingbuddy.parking_buddy.entity.ParkingSession;
import com.parkingbuddy.parking_buddy.entity.ParkingSpot;
import com.parkingbuddy.parking_buddy.service.ParkingSessionService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/sessions")
public class ParkingSessionController {

    private final ParkingSessionService parkingSessionService;

    public ParkingSessionController(ParkingSessionService parkingSessionService) {
        this.parkingSessionService = parkingSessionService;
    }

    @PostMapping("/reserve/{spotId}")
    public ParkingSpot reserveSpot(@PathVariable Integer spotId) {
        return parkingSessionService.reserveSpot(spotId);
    }

    @PostMapping("/start/{spotId}")
    public ParkingSession startParking(@PathVariable Integer spotId,
                                       @RequestParam String licensePlate,
                                       HttpServletRequest request) {
        Integer userId = (Integer) request.getAttribute("userId");
        return parkingSessionService.startParking(spotId, licensePlate, userId);
    }

    @PostMapping("/end/{spotId}")
    public Map<String, Object> endParking(@PathVariable Integer spotId) {
        return parkingSessionService.endParking(spotId);
    }

    @PostMapping("/cancel/{spotId}")
    public ParkingSpot cancelReservation(@PathVariable Integer spotId) {
        return parkingSessionService.cancelReservation(spotId);
    }
}
