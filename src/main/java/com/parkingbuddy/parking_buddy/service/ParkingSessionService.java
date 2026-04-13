package com.parkingbuddy.parking_buddy.service;

import com.parkingbuddy.parking_buddy.entity.ParkingSession;
import com.parkingbuddy.parking_buddy.entity.ParkingSpot;
import com.parkingbuddy.parking_buddy.repository.ParkingSessionRepository;
import com.parkingbuddy.parking_buddy.repository.ParkingSpotRepository;
import org.springframework.stereotype.Service;
import java.time.LocalDateTime;
import java.time.Duration;
import java.util.*;

@Service
public class ParkingSessionService {

    private final ParkingSessionRepository sessionRepository;
    private final ParkingSpotRepository spotRepository;

    public ParkingSessionService(ParkingSessionRepository sessionRepository,
                                 ParkingSpotRepository spotRepository) {
        this.sessionRepository = sessionRepository;
        this.spotRepository = spotRepository;
    }

    public ParkingSpot reserveSpot(Integer spotId) {
        ParkingSpot spot = spotRepository.findById(spotId)
                .orElseThrow(() -> new RuntimeException("Spot not found"));

        if (!"available".equals(spot.getStatus())) {
            throw new RuntimeException("Spot is not available");
        }

        spot.setStatus("reserved");
        return spotRepository.save(spot);
    }

    public ParkingSession startParking(Integer spotId, String licensePlate) {
        ParkingSpot spot = spotRepository.findById(spotId)
                .orElseThrow(() -> new RuntimeException("Spot not found"));

        if (!"available".equals(spot.getStatus()) && !"reserved".equals(spot.getStatus())) {
            throw new RuntimeException("Spot is not available or reserved");
        }

        spot.setStatus("occupied");
        spotRepository.save(spot);

        ParkingSession session = new ParkingSession();
        session.setParkingSpotId(spotId);
        session.setLicensePlate(licensePlate);
        session.setStartTime(LocalDateTime.now());
        session.setStatus("active");
        return sessionRepository.save(session);
    }

    public Map<String, Object> endParking(Integer spotId) {
        ParkingSession session = sessionRepository
                .findByParkingSpotIdAndStatus(spotId, "active")
                .orElseThrow(() -> new RuntimeException("No active session for this spot"));

        session.setEndTime(LocalDateTime.now());
        session.setStatus("completed");
        sessionRepository.save(session);

        ParkingSpot spot = spotRepository.findById(spotId)
                .orElseThrow(() -> new RuntimeException("Spot not found"));
        spot.setStatus("available");
        spotRepository.save(spot);

        long minutes = Duration.between(session.getStartTime(), session.getEndTime()).toMinutes();
        double cost = Math.ceil(minutes / 60.0) * spot.getPricePerHour().doubleValue();

        Map<String, Object> result = new HashMap<>();
        result.put("sessionId", session.getId());
        result.put("minutes", minutes);
        result.put("cost", cost);
        return result;
    }

    public ParkingSpot cancelReservation(Integer spotId) {
        ParkingSpot spot = spotRepository.findById(spotId)
                .orElseThrow(() -> new RuntimeException("Spot not found"));

        if (!"reserved".equals(spot.getStatus())) {
            throw new RuntimeException("Spot is not reserved");
        }

        spot.setStatus("available");
        return spotRepository.save(spot);
    }
}