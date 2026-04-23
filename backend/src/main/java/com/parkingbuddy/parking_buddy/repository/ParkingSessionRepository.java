package com.parkingbuddy.parking_buddy.repository;

import com.parkingbuddy.parking_buddy.entity.ParkingSession;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface ParkingSessionRepository extends JpaRepository<ParkingSession, Integer> {

    Optional<ParkingSession> findByParkingSpotIdAndStatus(Integer parkingSpotId, String status);

    List<ParkingSession> findByUserIdOrderByStartTimeDesc(Integer userId);
}
