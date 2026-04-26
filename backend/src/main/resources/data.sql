CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    card_number VARCHAR(30),
    card_expiry VARCHAR(5),
    cardholder_name VARCHAR(100)
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS balance NUMERIC(12, 2) DEFAULT 0;
UPDATE users SET balance = 0 WHERE balance IS NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_name VARCHAR(100);

ALTER TABLE parking_sessions ADD COLUMN IF NOT EXISTS user_id INTEGER REFERENCES users(id);
ALTER TABLE parking_sessions ADD COLUMN IF NOT EXISTS duration_hours INTEGER;
ALTER TABLE parking_sessions ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12, 2);

DELETE FROM parking_sessions;

UPDATE parking_spots SET status = 'available';

-- Радњанска: 32 total spots (6 available, 22 occupied, 4 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Радњанска';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Радњанска'
    ORDER BY RANDOM()
    LIMIT 22
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Радњанска'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 4
);


-- Костурски Херои: 19 total spots (6 available, 10 occupied, 3 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Костурски Херои';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Костурски Херои'
    ORDER BY RANDOM()
    LIMIT 10
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Костурски Херои'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 3
);



-- Отон Жупанчиќ: 15 total spots (3 available, 10 occupied, 2 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Отон Жупанчиќ';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Отон Жупанчиќ'
    ORDER BY RANDOM()
    LIMIT 10
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Отон Жупанчиќ'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 2
);


-- Антоние Грубишиќ: 27 total spots (8 available, 18 occupied, 1 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Антоние Грубишиќ';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Антоние Грубишиќ'
    ORDER BY RANDOM()
    LIMIT 18
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Антоние Грубишиќ'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 1
);


-- Наум Наумовски - Борче: 24 total spots (4 available, 18 occupied, 2 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Наум Наумовски - Борче';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Наум Наумовски - Борче'
    ORDER BY RANDOM()
    LIMIT 18
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Наум Наумовски - Борче'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 2
);


-- Коле Неделковски: 9 total spots (2 available, 6 occupied, 1 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Коле Неделковски';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Коле Неделковски'
    ORDER BY RANDOM()
    LIMIT 6
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Коле Неделковски'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 1
);


-- Пиринска: 9 total spots (3 available, 6 occupied, 0 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Пиринска';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Пиринска'
    ORDER BY RANDOM()
    LIMIT 6
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Пиринска'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 0
);


-- Аминта Трети: 15 total spots (5 available, 7 occupied, 3 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Аминта Трети';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Аминта Трети'
    ORDER BY RANDOM()
    LIMIT 7
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Аминта Трети'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 3
);


-- Михаил Цоков: 100 total spots (13 available, 80 occupied, 7 reserved)
UPDATE parking_spots
SET status = 'available'
WHERE street_name = 'Михаил Цоков';

UPDATE parking_spots
SET status = 'occupied'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Михаил Цоков'
    ORDER BY RANDOM()
    LIMIT 80
);

UPDATE parking_spots
SET status = 'reserved'
WHERE id IN (
    SELECT id
    FROM parking_spots
    WHERE street_name = 'Михаил Цоков'
      AND status = 'available'
    ORDER BY RANDOM()
    LIMIT 7
);