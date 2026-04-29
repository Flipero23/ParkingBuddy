package com.parkingbuddy.parking_buddy.service;

import com.parkingbuddy.parking_buddy.entity.ParkingSession;
import com.parkingbuddy.parking_buddy.entity.ParkingSpot;
import com.parkingbuddy.parking_buddy.entity.User;
import com.parkingbuddy.parking_buddy.exception.ResourceNotFoundException;
import com.parkingbuddy.parking_buddy.exception.SpotUnavailableException;
import com.parkingbuddy.parking_buddy.repository.ParkingSessionRepository;
import com.parkingbuddy.parking_buddy.repository.ParkingSpotRepository;
import com.parkingbuddy.parking_buddy.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
public class ParkingSessionService {

    private static final String STATUS_AVAILABLE = "available";
    private static final String STATUS_RESERVED = "reserved";
    private static final String STATUS_OCCUPIED = "occupied";
    private static final String SESSION_ACTIVE = "active";

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

    /**
     * Reserves the spot if it is currently available. Locks the spot row for
     * the duration of the transaction so two concurrent callers cannot both
     * succeed; the second one observes the updated status and gets a 409.
     */
    @Transactional
    public ParkingSpot reserveSpot(Integer spotId) {
        ParkingSpot spot = lockSpot(spotId);

        if (!STATUS_AVAILABLE.equals(spot.getStatus())) {
            throw new SpotUnavailableException("Parking spot is no longer available");
        }

        spot.setStatus(STATUS_RESERVED);
        return spotRepository.save(spot);
    }

    /**
     * Starts a paid session on a spot. Locks the spot row, then verifies the
     * status is still available or reserved before charging the user and
     * creating the session. Concurrent callers serialize on the row lock and
     * the loser is rejected with a 409.
     */
    @Transactional
    public ParkingSession startParking(Integer spotId,
                                       String licensePlate,
                                       Integer userId,
                                       Integer durationHours) {
        if (durationHours == null || (durationHours != 1 && durationHours != 2)) {
            throw new IllegalArgumentException("Duration must be 1 or 2 hours");
        }

        String normalizedPlate = LicensePlateValidator.normalizeAndValidate(licensePlate);

        ParkingSpot spot = lockSpot(spotId);

        if (!STATUS_AVAILABLE.equals(spot.getStatus()) && !STATUS_RESERVED.equals(spot.getStatus())) {
            throw new SpotUnavailableException("Parking spot is no longer available");
        }

        // Belt-and-braces guard: if somehow a session row already exists for
        // this spot, refuse before creating a duplicate.
        sessionRepository.findByParkingSpotIdAndStatus(spotId, SESSION_ACTIVE)
                .ifPresent(existing -> {
                    throw new SpotUnavailableException("Parking spot is no longer available");
                });

        BigDecimal amount = spot.getPricePerHour().multiply(BigDecimal.valueOf(durationHours));

        if (userId != null) {
            chargeUserBalance(userId, amount);
        }

        spot.setStatus(STATUS_OCCUPIED);
        spotRepository.save(spot);

        ParkingSession session = new ParkingSession();
        session.setParkingSpotId(spotId);
        session.setLicensePlate(normalizedPlate);
        session.setStartTime(LocalDateTime.now());
        session.setStatus(SESSION_ACTIVE);
        session.setUserId(userId);
        session.setDurationHours(durationHours);
        session.setPaidAmount(amount);
        return sessionRepository.save(session);
    }

    @Transactional
    public ParkingSession extendParking(Integer spotId, Integer userId) {
        ParkingSession session = sessionRepository
                .findByParkingSpotIdAndStatus(spotId, SESSION_ACTIVE)
                .orElseThrow(() -> new ResourceNotFoundException("No active session for this spot"));

        if (session.getUserId() != null && !session.getUserId().equals(userId)) {
            throw new IllegalArgumentException("Not authorized to extend this session");
        }

        Integer currentHours = session.getDurationHours() == null ? 1 : session.getDurationHours();
        if (currentHours >= 2) {
            throw new IllegalArgumentException("Session already at max duration");
        }

        ParkingSpot spot = lockSpot(spotId);

        BigDecimal extraAmount = spot.getPricePerHour();

        if (userId != null) {
            chargeUserBalance(userId, extraAmount);
        }

        BigDecimal previousPaid = session.getPaidAmount() == null ? BigDecimal.ZERO : session.getPaidAmount();
        session.setDurationHours(currentHours + 1);
        session.setPaidAmount(previousPaid.add(extraAmount));
        return sessionRepository.save(session);
    }

    @Transactional
    public Map<String, Object> endParking(Integer spotId) {
        ParkingSession session = sessionRepository
                .findByParkingSpotIdAndStatus(spotId, SESSION_ACTIVE)
                .orElseThrow(() -> new ResourceNotFoundException("No active session for this spot"));

        session.setEndTime(LocalDateTime.now());
        session.setStatus("completed");
        sessionRepository.save(session);

        ParkingSpot spot = lockSpot(spotId);
        spot.setStatus(STATUS_AVAILABLE);
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

    @Transactional
    public ParkingSpot cancelReservation(Integer spotId) {
        ParkingSpot spot = lockSpot(spotId);

        if (!STATUS_RESERVED.equals(spot.getStatus())) {
            throw new IllegalArgumentException("Spot is not reserved");
        }

        spot.setStatus(STATUS_AVAILABLE);
        return spotRepository.save(spot);
    }

    @Transactional(readOnly = true)
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

    private ParkingSpot lockSpot(Integer spotId) {
        return spotRepository.findByIdForUpdate(spotId)
                .orElseThrow(() -> new ResourceNotFoundException("Spot not found"));
    }

    private void chargeUserBalance(Integer userId, BigDecimal amount) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        BigDecimal current = user.getBalance() == null ? BigDecimal.ZERO : user.getBalance();
        if (current.compareTo(amount) < 0) {
            throw new IllegalArgumentException("Insufficient balance");
        }
        user.setBalance(current.subtract(amount));
        userRepository.save(user);
    }
}
