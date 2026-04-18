UPDATE parking_spots SET status = 'available';

UPDATE parking_spots SET status = 'occupied' WHERE id IN (
    SELECT id FROM parking_spots ORDER BY RANDOM() LIMIT 80
);

UPDATE parking_spots SET status = 'reserved' WHERE id IN (
    SELECT id FROM parking_spots WHERE status = 'available' ORDER BY RANDOM() LIMIT 20
);

DELETE FROM parking_sessions;