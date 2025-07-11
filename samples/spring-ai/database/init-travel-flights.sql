-- Flight Database Initialization Script
-- This script creates and populates airports and flights tables with comprehensive flight data

-- Connect to travel_db
\c travel_db;

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing flight tables if they exist (for clean restart)
DROP TABLE IF EXISTS flights CASCADE;
DROP TABLE IF EXISTS airports CASCADE;

-- Create airports table
CREATE TABLE airports (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4(),
    airport_code VARCHAR(3) UNIQUE NOT NULL,
    airport_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    timezone VARCHAR(50),
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- Create flights table with only essential constraints
CREATE TABLE flights (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4(),
    flight_number VARCHAR(10) UNIQUE NOT NULL,
    airline_name VARCHAR(100) NOT NULL,
    departure_airport VARCHAR(3) NOT NULL,
    arrival_airport VARCHAR(3) NOT NULL,
    departure_time TIME NOT NULL,
    arrival_time TIME NOT NULL,
    duration_minutes INTEGER,
    price DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    available_seats INTEGER,
    total_seats INTEGER,
    aircraft_type VARCHAR(20),
    seat_class VARCHAR(20),
    status VARCHAR(20),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    FOREIGN KEY (departure_airport) REFERENCES airports(airport_code),
    FOREIGN KEY (arrival_airport) REFERENCES airports(airport_code)
);

-- Insert airport data for all cities from AirportService
INSERT INTO airports (airport_code, airport_name, city, country, timezone) VALUES
-- New York
('JFK', 'John F. Kennedy International Airport', 'New York', 'United States', 'America/New_York'),
('LGA', 'LaGuardia Airport', 'New York', 'United States', 'America/New_York'),
('EWR', 'Newark Liberty International Airport', 'Newark', 'United States', 'America/New_York'),
-- London
('LHR', 'Heathrow Airport', 'London', 'United Kingdom', 'Europe/London'),
('LGW', 'Gatwick Airport', 'London', 'United Kingdom', 'Europe/London'),
('STN', 'Stansted Airport', 'London', 'United Kingdom', 'Europe/London'),
-- Paris
('CDG', 'Charles de Gaulle Airport', 'Paris', 'France', 'Europe/Paris'),
('ORY', 'Orly Airport', 'Paris', 'France', 'Europe/Paris'),
-- Tokyo
('NRT', 'Narita International Airport', 'Tokyo', 'Japan', 'Asia/Tokyo'),
('HND', 'Haneda Airport', 'Tokyo', 'Japan', 'Asia/Tokyo'),
-- Los Angeles
('LAX', 'Los Angeles International Airport', 'Los Angeles', 'United States', 'America/Los_Angeles'),
('BUR', 'Hollywood Burbank Airport', 'Burbank', 'United States', 'America/Los_Angeles'),
-- Las Vegas
('LAS', 'Harry Reid International Airport', 'Las Vegas', 'United States', 'America/Los_Angeles'),
('VGT', 'North Las Vegas Airport', 'North Las Vegas', 'United States', 'America/Los_Angeles'),
-- Dubai
('DXB', 'Dubai International Airport', 'Dubai', 'United Arab Emirates', 'Asia/Dubai'),
('DWC', 'Al Maktoum International Airport', 'Dubai', 'United Arab Emirates', 'Asia/Dubai'),
-- Singapore
('SIN', 'Singapore Changi Airport', 'Singapore', 'Singapore', 'Asia/Singapore'),
-- Amsterdam
('AMS', 'Amsterdam Airport Schiphol', 'Amsterdam', 'Netherlands', 'Europe/Amsterdam'),
-- Frankfurt
('FRA', 'Frankfurt Airport', 'Frankfurt', 'Germany', 'Europe/Berlin'),
-- Madrid
('MAD', 'Adolfo Suárez Madrid–Barajas Airport', 'Madrid', 'Spain', 'Europe/Madrid');

-- Insert flight data with logical airline routes and reasonable prices
-- Major US Routes
INSERT INTO flights (flight_number, airline_name, departure_airport, arrival_airport, departure_time, arrival_time, duration_minutes, price, currency, available_seats, total_seats, aircraft_type, seat_class, status) VALUES
-- New York to Los Angeles
('AA101', 'American Airlines', 'JFK', 'LAX', '08:00:00', '11:30:00', 330, 299.00, 'USD', 45, 180, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
('UA201', 'United Airlines', 'JFK', 'LAX', '14:00:00', '17:30:00', 330, 315.00, 'USD', 67, 200, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
-- Los Angeles to New York
('AA102', 'American Airlines', 'LAX', 'JFK', '09:00:00', '17:30:00', 330, 289.00, 'USD', 52, 180, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
('UA202', 'United Airlines', 'LAX', 'JFK', '15:30:00', '23:59:00', 330, 325.00, 'USD', 78, 200, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),

-- New York to Las Vegas
('AA301', 'American Airlines', 'JFK', 'LAS', '10:00:00', '13:00:00', 300, 245.00, 'USD', 89, 160, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
('WN401', 'Southwest Airlines', 'JFK', 'LAS', '16:00:00', '19:00:00', 300, 199.00, 'USD', 134, 175, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
-- Las Vegas to New York
('AA302', 'American Airlines', 'LAS', 'JFK', '11:30:00', '19:30:00', 300, 255.00, 'USD', 67, 160, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
('WN402', 'Southwest Airlines', 'LAS', 'JFK', '17:30:00', '01:30:00', 300, 209.00, 'USD', 98, 175, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),

-- Los Angeles to Las Vegas
('WN501', 'Southwest Airlines', 'LAX', 'LAS', '07:00:00', '08:15:00', 75, 89.00, 'USD', 156, 175, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
('AA501', 'American Airlines', 'LAX', 'LAS', '19:00:00', '20:15:00', 75, 95.00, 'USD', 123, 160, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
-- Las Vegas to Los Angeles
('WN502', 'Southwest Airlines', 'LAS', 'LAX', '09:30:00', '10:45:00', 75, 85.00, 'USD', 145, 175, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
('AA502', 'American Airlines', 'LAS', 'LAX', '21:30:00', '22:45:00', 75, 99.00, 'USD', 134, 160, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),

-- Transatlantic Routes
-- New York to London
('BA101', 'British Airways', 'JFK', 'LHR', '22:00:00', '09:30:00', 450, 599.00, 'USD', 34, 250, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
('VS001', 'Virgin Atlantic', 'JFK', 'LHR', '20:30:00', '08:00:00', 450, 649.00, 'USD', 45, 280, 'AIRBUS_A330', 'ECONOMY', 'SCHEDULED'),
-- London to New York
('BA102', 'British Airways', 'LHR', 'JFK', '11:00:00', '14:30:00', 450, 579.00, 'USD', 56, 250, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
('VS002', 'Virgin Atlantic', 'LHR', 'JFK', '13:30:00', '17:00:00', 450, 629.00, 'USD', 67, 280, 'AIRBUS_A330', 'ECONOMY', 'SCHEDULED'),

-- New York to Paris
('AF001', 'Air France', 'JFK', 'CDG', '23:30:00', '12:00:00', 450, 549.00, 'USD', 78, 300, 'AIRBUS_A350', 'ECONOMY', 'SCHEDULED'),
('DL401', 'Delta Air Lines', 'JFK', 'CDG', '21:00:00', '09:30:00', 450, 589.00, 'USD', 89, 220, 'BOEING_767', 'ECONOMY', 'SCHEDULED'),
-- Paris to New York
('AF002', 'Air France', 'CDG', 'JFK', '10:30:00', '13:00:00', 450, 529.00, 'USD', 45, 300, 'AIRBUS_A350', 'ECONOMY', 'SCHEDULED'),
('DL402', 'Delta Air Lines', 'CDG', 'JFK', '12:00:00', '14:30:00', 450, 569.00, 'USD', 67, 220, 'BOEING_767', 'ECONOMY', 'SCHEDULED'),

-- European Routes
-- London to Paris
('BA301', 'British Airways', 'LHR', 'CDG', '08:00:00', '10:30:00', 90, 129.00, 'EUR', 134, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('AF301', 'Air France', 'LHR', 'CDG', '18:00:00', '20:30:00', 90, 139.00, 'EUR', 156, 160, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
-- Paris to London
('BA302', 'British Airways', 'CDG', 'LHR', '12:00:00', '12:30:00', 90, 125.00, 'EUR', 123, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('AF302', 'Air France', 'CDG', 'LHR', '16:30:00', '17:00:00', 90, 135.00, 'EUR', 145, 160, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),

-- London to Amsterdam
('BA401', 'British Airways', 'LHR', 'AMS', '09:00:00', '11:30:00', 90, 119.00, 'EUR', 167, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('KL401', 'KLM', 'LHR', 'AMS', '15:00:00', '17:30:00', 90, 109.00, 'EUR', 189, 200, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
-- Amsterdam to London
('BA402', 'British Airways', 'AMS', 'LHR', '13:00:00', '13:30:00', 90, 115.00, 'EUR', 134, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('KL402', 'KLM', 'AMS', 'LHR', '19:00:00', '19:30:00', 90, 105.00, 'EUR', 156, 200, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),

-- Paris to Madrid
('AF501', 'Air France', 'CDG', 'MAD', '10:00:00', '12:30:00', 120, 149.00, 'EUR', 145, 160, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('IB501', 'Iberia', 'CDG', 'MAD', '17:00:00', '19:30:00', 120, 139.00, 'EUR', 167, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
-- Madrid to Paris
('AF502', 'Air France', 'MAD', 'CDG', '14:00:00', '16:30:00', 120, 145.00, 'EUR', 123, 160, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('IB502', 'Iberia', 'MAD', 'CDG', '21:00:00', '23:30:00', 120, 135.00, 'EUR', 134, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),

-- Frankfurt to Amsterdam
('LH601', 'Lufthansa', 'FRA', 'AMS', '08:30:00', '10:00:00', 90, 99.00, 'EUR', 178, 200, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('KL601', 'KLM', 'FRA', 'AMS', '16:30:00', '18:00:00', 90, 89.00, 'EUR', 189, 180, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),
-- Amsterdam to Frankfurt
('LH602', 'Lufthansa', 'AMS', 'FRA', '12:00:00', '13:30:00', 90, 95.00, 'EUR', 156, 200, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('KL602', 'KLM', 'AMS', 'FRA', '20:00:00', '21:30:00', 90, 85.00, 'EUR', 167, 180, 'BOEING_737', 'ECONOMY', 'SCHEDULED'),

-- London to Frankfurt
('BA801', 'British Airways', 'LHR', 'FRA', '07:30:00', '10:00:00', 90, 109.00, 'EUR', 145, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('LH801', 'Lufthansa', 'LHR', 'FRA', '17:00:00', '19:30:00', 90, 99.00, 'EUR', 167, 200, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
-- Frankfurt to London
('BA802', 'British Airways', 'FRA', 'LHR', '11:30:00', '12:00:00', 90, 105.00, 'EUR', 134, 180, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),
('LH802', 'Lufthansa', 'FRA', 'LHR', '21:00:00', '21:30:00', 90, 95.00, 'EUR', 156, 200, 'AIRBUS_A320', 'ECONOMY', 'SCHEDULED'),

-- London to Las Vegas (Long-haul)
('BA901', 'British Airways', 'LHR', 'LAS', '11:00:00', '14:30:00', 630, 649.00, 'USD', 67, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
('VS901', 'Virgin Atlantic', 'LHR', 'LAS', '15:30:00', '19:00:00', 630, 699.00, 'USD', 89, 350, 'AIRBUS_A330', 'ECONOMY', 'SCHEDULED'),
-- Las Vegas to London
('BA902', 'British Airways', 'LAS', 'LHR', '16:00:00', '09:30:00', 630, 629.00, 'USD', 78, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
('VS902', 'Virgin Atlantic', 'LAS', 'LHR', '20:30:00', '14:00:00', 630, 679.00, 'USD', 56, 350, 'AIRBUS_A330', 'ECONOMY', 'SCHEDULED'),

-- Frankfurt to Las Vegas
('LH701', 'Lufthansa', 'FRA', 'LAS', '13:30:00', '16:00:00', 690, 749.00, 'USD', 89, 350, 'BOEING_787', 'ECONOMY', 'SCHEDULED'),
('UA701', 'United Airlines', 'FRA', 'LAS', '22:00:00', '00:30:00', 690, 799.00, 'USD', 67, 300, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
-- Las Vegas to Frankfurt
('LH702', 'Lufthansa', 'LAS', 'FRA', '18:00:00', '12:30:00', 690, 729.00, 'USD', 78, 350, 'BOEING_787', 'ECONOMY', 'SCHEDULED'),
('UA702', 'United Airlines', 'LAS', 'FRA', '02:30:00', '21:00:00', 690, 779.00, 'USD', 89, 300, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),

-- Long-haul Routes to Asia
-- New York to Tokyo
('JL001', 'Japan Airlines', 'JFK', 'NRT', '13:00:00', '16:30:00', 810, 899.00, 'USD', 45, 350, 'BOEING_787', 'ECONOMY', 'SCHEDULED'),
('NH001', 'ANA', 'JFK', 'NRT', '17:30:00', '21:00:00', 810, 949.00, 'USD', 67, 300, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
-- Tokyo to New York
('JL002', 'Japan Airlines', 'NRT', 'JFK', '18:00:00', '04:30:00', 810, 879.00, 'USD', 56, 350, 'BOEING_787', 'ECONOMY', 'SCHEDULED'),
('NH002', 'ANA', 'NRT', 'JFK', '22:30:00', '09:00:00', 810, 929.00, 'USD', 78, 300, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),

-- London to Tokyo
('JL401', 'Japan Airlines', 'LHR', 'NRT', '12:30:00', '08:00:00', 690, 799.00, 'USD', 89, 350, 'BOEING_787', 'ECONOMY', 'SCHEDULED'),
('BA501', 'British Airways', 'LHR', 'NRT', '21:00:00', '16:30:00', 690, 849.00, 'USD', 45, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
-- Tokyo to London
('JL402', 'Japan Airlines', 'NRT', 'LHR', '10:00:00', '14:30:00', 690, 779.00, 'USD', 67, 350, 'BOEING_787', 'ECONOMY', 'SCHEDULED'),
('BA502', 'British Airways', 'NRT', 'LHR', '19:30:00', '00:00:00', 690, 829.00, 'USD', 56, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),

-- Routes to Middle East and Asia
-- New York to Dubai
('EK201', 'Emirates', 'JFK', 'DXB', '23:59:00', '19:30:00', 810, 749.00, 'USD', 89, 400, 'AIRBUS_A380', 'ECONOMY', 'SCHEDULED'),
('QR201', 'Qatar Airways', 'JFK', 'DXB', '22:00:00', '18:00:00', 840, 799.00, 'USD', 67, 350, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
-- Dubai to New York
('EK202', 'Emirates', 'DXB', 'JFK', '08:30:00', '14:00:00', 810, 729.00, 'USD', 78, 400, 'AIRBUS_A380', 'ECONOMY', 'SCHEDULED'),
('QR202', 'Qatar Airways', 'DXB', 'JFK', '10:00:00', '16:00:00', 840, 779.00, 'USD', 89, 350, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),

-- London to Dubai
('EK001', 'Emirates', 'LHR', 'DXB', '14:30:00', '00:00:00', 390, 449.00, 'USD', 134, 400, 'AIRBUS_A380', 'ECONOMY', 'SCHEDULED'),
('BA601', 'British Airways', 'LHR', 'DXB', '21:30:00', '07:00:00', 390, 499.00, 'USD', 123, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
-- Dubai to London
('EK002', 'Emirates', 'DXB', 'LHR', '02:30:00', '07:00:00', 390, 429.00, 'USD', 145, 400, 'AIRBUS_A380', 'ECONOMY', 'SCHEDULED'),
('BA602', 'British Airways', 'DXB', 'LHR', '09:00:00', '13:30:00', 390, 479.00, 'USD', 156, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),

-- Singapore Routes
-- London to Singapore
('SQ001', 'Singapore Airlines', 'LHR', 'SIN', '22:00:00', '17:30:00', 750, 699.00, 'USD', 89, 350, 'AIRBUS_A350', 'ECONOMY', 'SCHEDULED'),
('BA701', 'British Airways', 'LHR', 'SIN', '13:00:00', '08:30:00', 750, 749.00, 'USD', 67, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED'),
-- Singapore to London
('SQ002', 'Singapore Airlines', 'SIN', 'LHR', '01:00:00', '07:30:00', 750, 679.00, 'USD', 78, 350, 'AIRBUS_A350', 'ECONOMY', 'SCHEDULED'),
('BA702', 'British Airways', 'SIN', 'LHR', '11:30:00', '18:00:00', 750, 729.00, 'USD', 89, 280, 'BOEING_777', 'ECONOMY', 'SCHEDULED');

-- Verify data insertion
SELECT
    COUNT(*) as total_airports
FROM airports;

SELECT
    COUNT(*) as total_flights,
    COUNT(DISTINCT airline_name) as unique_airlines,
    COUNT(DISTINCT departure_airport) as departure_airports,
    COUNT(DISTINCT arrival_airport) as arrival_airports
FROM flights;

-- Show flight routes summary
SELECT
    departure_airport,
    arrival_airport,
    COUNT(*) as flight_count,
    MIN(price) as min_price,
    MAX(price) as max_price,
    ROUND(AVG(price), 2) as avg_price,
    currency
FROM flights
WHERE status = 'SCHEDULED'
GROUP BY departure_airport, arrival_airport, currency
ORDER BY departure_airport, arrival_airport;

-- Show airlines and their routes
SELECT
    airline_name,
    COUNT(*) as total_flights,
    COUNT(DISTINCT departure_airport || '-' || arrival_airport) as unique_routes
FROM flights
WHERE status = 'SCHEDULED'
GROUP BY airline_name
ORDER BY total_flights DESC;

COMMIT;
