package com.parkingbuddy.parking_buddy.service;

import com.parkingbuddy.parking_buddy.entity.ParkingSession;
import com.parkingbuddy.parking_buddy.entity.ParkingSpot;
import com.parkingbuddy.parking_buddy.entity.User;
import com.parkingbuddy.parking_buddy.repository.ParkingSessionRepository;
import com.parkingbuddy.parking_buddy.repository.ParkingSpotRepository;
import com.parkingbuddy.parking_buddy.repository.UserRepository;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.Duration;
import java.util.*;

@Service
public class ParkingSessionService {

    private final ParkingSessionRepository sessionRepository;
    private final ParkingSpotRepository spotRepository;
    private final UserRepository userRepository;

    public ParkingSessionService(ParkingSessionRepository sessionRepository,
                                 ParkingSpotRepository spotRepository,
                                 UserRepository userRepository) {
        this.sessionRepository = sessionRepository;
        this.spotRepository = spotRepository;
        this.userRepository = userRepository;
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

    public ParkingSession startParking(Integer spotId,
                                       String licensePlate,
                                       Integer userId,
                                       Integer durationHours) {
        if (durationHours == null || (durationHours != 1 && durationHours != 2)) {
            throw new RuntimeException("Duration must be 1 or 2 hours");
        }

        ParkingSpot spot = spotRepository.findById(spotId)
                .orElseThrow(() -> new RuntimeException("Spot not found"));

        if (!"available".equals(spot.getStatus()) && !"reserved".equals(spot.getStatus())) {
            throw new RuntimeException("Spot is not available or reserved");
        }

        BigDecimal amount = spot.getPricePerHour().multiply(BigDecimal.valueOf(durationHours));

        if (userId != null) {
            chargeUserBalance(userId, amount);
        }

        spot.setStatus("occupied");
        spotRepository.save(spot);

        ParkingSession session = new ParkingSession();
        session.setParkingSpotId(spotId);
        session.setLicensePlate(licensePlate);
        session.setStartTime(LocalDateTime.now());
        session.setStatus("active");
        session.setUserId(userId);
        session.setDurationHours(durationHours);
        session.setPaidAmount(amount);
        return sessionRepository.save(session);
    }

    public ParkingSession extendParking(Integer spotId, Integer userId) {
        ParkingSession session = sessionRepository
                .findByParkingSpotIdAndStatus(spotId, "active")
                .orElseThrow(() -> new RuntimeException("No active session for this spot"));

        if (session.getUserId() != null && !session.getUserId().equals(userId)) {
            throw new RuntimeException("Not authorized to extend this session");
        }

        Integer currentHours = session.getDurationHours() == null ? 1 : session.getDurationHours();
        if (currentHours >= 2) {
            throw new RuntimeException("Session already at max duration");
        }

        ParkingSpot spot = spotRepository.findById(spotId)
                .orElseThrow(() -> new RuntimeException("Spot not found"));

        BigDecimal extraAmount = spot.getPricePerHour();

        if (userId != null) {
            chargeUserBalance(userId, extraAmount);
        }

        BigDecimal previousPaid = session.getPaidAmount() == null ? BigDecimal.ZERO : session.getPaidAmount();
        session.setDurationHours(currentHours + 1);
        session.setPaidAmount(previousPaid.add(extraAmount));
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

        Integer durationHours = session.getDurationHours();
        BigDecimal paid = session.getPaidAmount() == null ? BigDecimal.ZERO : session.getPaidAmount();
        long paidMinutes = durationHours == null ? 0L : durationHours * 60L;

        Map<String, Object> result = new HashMap<>();
        result.put("sessionId", session.getId());
        result.put("minutes", paidMinutes);
        result.put("cost", paid.doubleValue());
        result.put("durationHours", durationHours);
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

    public List<Map<String, Object>> getHistoryForUser(Integer userId) {
        List<ParkingSession> sessions = sessionRepository.findByUserIdOrderByStartTimeDesc(userId);
        List<Map<String, Object>> result = new ArrayList<>();

        for (ParkingSession session : sessions) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("sessionId", session.getId());
            item.put("licensePlate", session.getLicensePlate());
            item.put("startTime", session.getStartTime() != null ? session.getStartTime().toString() : null);
            item.put("endTime", session.getEndTime() != null ? session.getEndTime().toString() : null);
            item.put("status", session.getStatus());
            item.put("durationHours", session.getDurationHours());

            Optional<ParkingSpot> spotOpt = spotRepository.findById(session.getParkingSpotId());
            if (spotOpt.isPresent()) {
                ParkingSpot spot = spotOpt.get();
                item.put("spotCode", spot.getCode());
                item.put("streetName", spot.getStreetName());
                item.put("zone", spot.getZone());

                long paidMinutes;
                double totalCost;
                if (session.getDurationHours() != null) {
                    paidMinutes = session.getDurationHours() * 60L;
                    totalCost = session.getPaidAmount() != null
                            ? session.getPaidAmount().doubleValue()
                            : 0.0;
                } else if (session.getStartTime() != null && session.getEndTime() != null) {
                    paidMinutes = Math.max(1, Duration.between(session.getStartTime(), session.getEndTime()).toMinutes());
                    long billedHours = Math.max(1, (long) Math.ceil(paidMinutes / 60.0));
                    totalCost = billedHours * spot.getPricePerHour().doubleValue();
                } else {
                    paidMinutes = 0;
                    totalCost = 0.0;
                }
                item.put("paidDurationMinutes", paidMinutes);
                item.put("totalCost", totalCost);
            } else {
                item.put("spotCode", null);
                item.put("streetName", null);
                item.put("zone", null);
                item.put("paidDurationMinutes", 0);
                item.put("totalCost", 0.0);
            }

            result.add(item);
        }

        return result;
    }

    private void chargeUserBalance(Integer userId, BigDecimal amount) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));

        BigDecimal current = user.getBalance() == null ? BigDecimal.ZERO : user.getBalance();
        if (current.compareTo(amount) < 0) {
            throw new RuntimeException("Insufficient balance");
        }
        user.setBalance(current.subtract(amount));
        userRepository.save(user);
    }
}
