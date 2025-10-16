-- Travel Database Initialization Script
-- This script creates and populates the hotels table with comprehensive hotel data

-- Connect to travel_db
\c travel_db;

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables if they exist (for clean restart)
DROP TABLE IF EXISTS hotels CASCADE;

-- Create hotels table with only essential constraints
CREATE TABLE hotels (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4(),
    hotel_name VARCHAR(100) NOT NULL,
    hotel_chain VARCHAR(100),
    city VARCHAR(100) NOT NULL,
    country VARCHAR(100),
    address VARCHAR(255),
    star_rating INTEGER,
    price_per_night DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3),
    available_rooms INTEGER,
    total_rooms INTEGER,
    room_type VARCHAR(20),
    amenities TEXT,
    description TEXT,
    status VARCHAR(20),
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- EUROPEAN CITIES (with budget options under €140)

-- Madrid, Spain
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('Madrid Marriott Auditorium', 'Marriott', 'Madrid', 'Spain', 'Avenida de Aragón 400, Madrid', 5, 285.00, 'EUR', 45, 869, 'DELUXE', 'Spa, Fitness Center, Business Center, Room Service, Free WiFi, Pool', 'Luxury 5-star hotel in Madrid with world-class amenities and exceptional service.', 'ACTIVE'),
('Hilton Madrid Airport', 'Hilton', 'Madrid', 'Spain', 'Avenida de la Capital de España 10, Madrid', 4, 195.00, 'EUR', 78, 284, 'STANDARD', 'Fitness Center, Business Center, Room Service, Free WiFi, Airport Shuttle', 'Modern 4-star hotel near Madrid airport with convenient location and excellent facilities.', 'ACTIVE'),
('Holiday Inn Madrid - Calle Alcalá', 'Holiday Inn', 'Madrid', 'Spain', 'Calle de Alcalá 66, Madrid', 4, 140.00, 'EUR', 92, 173, 'STANDARD', '24/7 Reception, Fitness Center, Business Center, Room Service, Free WiFi', 'Comfortable 4-star hotel in central Madrid with modern amenities and friendly service.', 'ACTIVE'),
('Hotel Madrid Centro', 'Independent', 'Madrid', 'Spain', 'Calle Gran Vía 25, Madrid', 3, 89.00, 'EUR', 45, 120, 'STANDARD', 'Free WiFi, 24/7 Reception, Restaurant', 'Budget-friendly hotel in the heart of Madrid with essential amenities.', 'ACTIVE'),
('Novotel Madrid Center', 'Accor', 'Madrid', 'Spain', 'Calle de O''Donnell 53, Madrid', 4, 125.00, 'EUR', 105, 790, 'STANDARD', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant', 'Contemporary 4-star hotel in central Madrid with modern design and convenient location.', 'ACTIVE');

-- Paris, France
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('The Ritz Paris', 'Ritz-Carlton', 'Paris', 'France', 'Place Vendôme 15, Paris', 5, 450.00, 'EUR', 12, 142, 'SUITE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Butler Service', 'Legendary 5-star palace hotel in the heart of Paris offering unparalleled luxury and elegance.', 'ACTIVE'),
('Paris Marriott Champs Elysees Hotel', 'Marriott', 'Paris', 'France', 'Rue de Berri 70, Paris', 5, 295.00, 'EUR', 38, 192, 'DELUXE', 'Fitness Center, Business Center, Room Service, Free WiFi, Concierge', 'Sophisticated 5-star hotel near Champs-Élysées with elegant accommodations and premium service.', 'ACTIVE'),
('Hilton Paris Opera', 'Hilton', 'Paris', 'France', 'Rue Saint-Lazare 108, Paris', 4, 220.00, 'EUR', 56, 268, 'STANDARD', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant', 'Classic 4-star hotel near Opera with traditional Parisian charm and modern amenities.', 'ACTIVE'),
('Holiday Inn Paris - Gare de Lyon Bastille', 'Holiday Inn', 'Paris', 'France', 'Rue de Lyon 11, Paris', 4, 155.00, 'EUR', 89, 253, 'STANDARD', '24/7 Reception, Fitness Center, Business Center, Room Service, Free WiFi', 'Modern 4-star hotel near Gare de Lyon with comfortable accommodations and convenient location.', 'ACTIVE'),
('Hotel Paris Republique', 'Independent', 'Paris', 'France', 'Boulevard du Temple 45, Paris', 3, 95.00, 'EUR', 67, 150, 'STANDARD', 'Free WiFi, 24/7 Reception, Continental Breakfast', 'Charming budget hotel in the vibrant Republique district with easy metro access.', 'ACTIVE'),
('Pullman Paris Montparnasse', 'Accor', 'Paris', 'France', 'Rue du Commandant René Mouchotte 19, Paris', 4, 185.00, 'EUR', 73, 957, 'STANDARD', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Bar', 'Contemporary 4-star hotel in Montparnasse with panoramic city views and modern facilities.', 'ACTIVE');

-- London, United Kingdom
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('London Marriott Hotel County Hall', 'Marriott', 'London', 'United Kingdom', 'Westminster Bridge Rd, London', 5, 295.00, 'EUR', 44, 200, 'DELUXE', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Thames Views', 'Historic 5-star hotel with stunning Thames views and prime South Bank location.', 'ACTIVE'),
('Hilton London Park Lane', 'Hilton', 'London', 'United Kingdom', '22 Park Ln, London', 5, 325.00, 'EUR', 33, 453, 'DELUXE', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Hyde Park Views', 'Iconic 5-star hotel overlooking Hyde Park with timeless elegance and luxury service.', 'ACTIVE'),
('Holiday Inn London - Kensington High St', 'Holiday Inn', 'London', 'United Kingdom', 'Wrights Ln, London', 4, 155.00, 'EUR', 87, 706, 'STANDARD', '24/7 Reception, Fitness Center, Business Center, Room Service, Free WiFi', 'Modern 4-star hotel in Kensington with convenient location and comfortable accommodations.', 'ACTIVE'),
('Premier Inn London City', 'Premier Inn', 'London', 'United Kingdom', 'Aldgate High Street 85, London', 3, 110.00, 'EUR', 156, 300, 'STANDARD', 'Free WiFi, 24/7 Reception, Restaurant, Comfortable Beds', 'Reliable budget hotel in the City with excellent value and consistent quality.', 'ACTIVE'),
('InterContinental London Park Lane', 'InterContinental', 'London', 'United Kingdom', '1 Hamilton Pl, London', 5, 385.00, 'EUR', 26, 447, 'DELUXE', 'Spa, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Michelin Restaurant', 'Prestigious 5-star hotel at Hyde Park Corner with legendary service and luxury accommodations.', 'ACTIVE');

-- Amsterdam, Netherlands
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('Amsterdam Marriott Hotel', 'Marriott', 'Amsterdam', 'Netherlands', 'Stadhouderskade 12, Amsterdam', 5, 265.00, 'EUR', 52, 396, 'DELUXE', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Bar', 'Luxury 5-star hotel overlooking Leidseplein with elegant accommodations and prime location.', 'ACTIVE'),
('Hilton Amsterdam', 'Hilton', 'Amsterdam', 'Netherlands', 'Apollolaan 138, Amsterdam', 5, 245.00, 'EUR', 47, 271, 'STANDARD', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Executive Lounge', 'Classic 5-star hotel in Amsterdam South with timeless elegance and modern amenities.', 'ACTIVE'),
('Holiday Inn Amsterdam', 'Holiday Inn', 'Amsterdam', 'Netherlands', 'De Boelelaan 2, Amsterdam', 4, 135.00, 'EUR', 91, 264, 'STANDARD', '24/7 Reception, Fitness Center, Business Center, Room Service, Free WiFi', 'Modern 4-star hotel with convenient location and comfortable accommodations.', 'ACTIVE'),
('Hotel V Nesplein', 'Independent', 'Amsterdam', 'Netherlands', 'Nesplein 23, Amsterdam', 3, 98.00, 'EUR', 34, 80, 'STANDARD', 'Free WiFi, 24/7 Reception, Bar, Bike Rental', 'Trendy budget hotel near museums with Dutch design and friendly atmosphere.', 'ACTIVE'),
('InterContinental Amstel Amsterdam', 'InterContinental', 'Amsterdam', 'Netherlands', 'Professor Tulpplein 1, Amsterdam', 5, 420.00, 'EUR', 22, 79, 'SUITE', 'Spa, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Michelin Restaurant', 'Iconic 5-star palace hotel on the Amstel River offering unparalleled luxury and service.', 'ACTIVE');

-- Frankfurt, Germany
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('Frankfurt Marriott Hotel', 'Marriott', 'Frankfurt', 'Germany', 'Hamburger Allee 2, Frankfurt', 5, 225.00, 'EUR', 58, 588, 'DELUXE', 'Spa, Fitness Center, Business Center, Room Service, Free WiFi, Restaurant', 'Modern 5-star hotel in financial district with excellent business facilities and luxury amenities.', 'ACTIVE'),
('Hilton Frankfurt City Centre', 'Hilton', 'Frankfurt', 'Germany', 'Hochstraße 4, Frankfurt', 4, 185.00, 'EUR', 73, 342, 'STANDARD', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Executive Lounge', 'Central 4-star hotel with convenient location and modern amenities for business travelers.', 'ACTIVE'),
('Holiday Inn Frankfurt Airport', 'Holiday Inn', 'Frankfurt', 'Germany', 'Unterschweinstiege 16, Frankfurt', 4, 145.00, 'EUR', 98, 341, 'STANDARD', '24/7 Reception, Fitness Center, Business Center, Room Service, Free WiFi, Airport Shuttle', 'Convenient airport hotel with shuttle service and comfortable accommodations.', 'ACTIVE'),
('Meininger Hotel Frankfurt Main', 'Meininger', 'Frankfurt', 'Germany', 'Europaallee 64, Frankfurt', 3, 75.00, 'EUR', 89, 180, 'STANDARD', 'Free WiFi, 24/7 Reception, Bar, Luggage Storage', 'Modern budget hotel near central station with clean rooms and good value.', 'ACTIVE'),
('InterContinental Frankfurt', 'InterContinental', 'Frankfurt', 'Germany', 'Wilhelm-Leuschner-Straße 43, Frankfurt', 5, 295.00, 'EUR', 43, 467, 'DELUXE', 'Spa, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Restaurant', 'Luxury 5-star hotel in city center with sophisticated accommodations and premium service.', 'ACTIVE');

-- NON-EUROPEAN CITIES

-- New York, United States
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('New York Marriott Marquis', 'Marriott', 'New York', 'United States', '1535 Broadway, New York', 5, 385.00, 'USD', 67, 1966, 'DELUXE', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Revolving Rooftop', 'Iconic Times Square hotel with revolving rooftop restaurant and Broadway theater access.', 'ACTIVE'),
('Hilton New York Midtown', 'Hilton', 'New York', 'United States', '1335 Avenue of the Americas, New York', 4, 295.00, 'USD', 89, 2079, 'STANDARD', 'Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Executive Lounge', 'Large midtown hotel with comprehensive facilities and central Manhattan location.', 'ACTIVE'),
('Holiday Inn Manhattan Financial District', 'Holiday Inn', 'New York', 'United States', '99 Washington Street, New York', 4, 225.00, 'USD', 134, 492, 'STANDARD', '24/7 Reception, Fitness Center, Business Center, Room Service, Free WiFi', 'Modern hotel in Financial District with easy access to Wall Street and Brooklyn Bridge.', 'ACTIVE'),
('Pod Hotels Times Square', 'Pod Hotels', 'New York', 'United States', '400 W 42nd St, New York', 3, 165.00, 'USD', 178, 665, 'STANDARD', 'Free WiFi, 24/7 Reception, Rooftop Bar, Fitness Center', 'Stylish budget hotel in Times Square with efficient rooms and great location.', 'ACTIVE'),
('InterContinental New York Barclay', 'InterContinental', 'New York', 'United States', '111 E 48th St, New York', 5, 465.00, 'USD', 45, 702, 'DELUXE', 'Spa, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Fine Dining', 'Historic luxury hotel in Midtown East with classic elegance and modern amenities.', 'ACTIVE');

-- Los Angeles, United States
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('JW Marriott Los Angeles L.A. LIVE', 'Marriott', 'Los Angeles', 'United States', '900 W Olympic Blvd, Los Angeles', 5, 325.00, 'USD', 78, 878, 'DELUXE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Restaurant', 'Luxury downtown hotel connected to entertainment district with world-class amenities.', 'ACTIVE'),
('Hilton Los Angeles Airport', 'Hilton', 'Los Angeles', 'United States', '5711 W Century Blvd, Los Angeles', 4, 195.00, 'USD', 156, 1234, 'STANDARD', 'Pool, Fitness Center, Business Center, Room Service, Free WiFi, Airport Shuttle', 'Convenient airport hotel with shuttle service and comprehensive facilities.', 'ACTIVE'),
('Holiday Inn Los Angeles Downtown', 'Holiday Inn', 'Los Angeles', 'United States', '750 Garland Ave, Los Angeles', 4, 165.00, 'USD', 89, 195, 'STANDARD', '24/7 Reception, Pool, Fitness Center, Business Center, Room Service, Free WiFi', 'Modern downtown hotel with pool and easy access to attractions.', 'ACTIVE'),
('Best Western Plus Dragon Gate Inn', 'Best Western', 'Los Angeles', 'United States', '818 N Hill St, Los Angeles', 3, 125.00, 'USD', 67, 154, 'STANDARD', 'Free WiFi, 24/7 Reception, Continental Breakfast, Parking', 'Budget-friendly hotel in Chinatown with good value and essential amenities.', 'ACTIVE'),
('InterContinental Los Angeles Downtown', 'InterContinental', 'Los Angeles', 'United States', '900 Wilshire Blvd, Los Angeles', 5, 395.00, 'USD', 56, 889, 'DELUXE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Rooftop Bar', 'Ultra-modern luxury hotel in downtown with stunning city views and premium amenities.', 'ACTIVE');

-- Las Vegas, United States
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('JW Marriott Las Vegas Resort & Spa', 'Marriott', 'Las Vegas', 'United States', '221 N Rampart Blvd, Las Vegas', 5, 285.00, 'USD', 67, 548, 'DELUXE', 'Spa, Pool, Golf Course, Fitness Center, Business Center, Room Service, Free WiFi, Casino', 'Luxury 5-star resort in Summerlin with championship golf course and world-class spa facilities.', 'ACTIVE'),
('Hilton Grand Vacations on the Las Vegas Strip', 'Hilton', 'Las Vegas', 'United States', '2650 Las Vegas Blvd S, Las Vegas', 4, 195.00, 'USD', 89, 1228, 'STANDARD', 'Pool, Fitness Center, Business Center, Room Service, Free WiFi, Strip Views, Casino Access', 'Modern 4-star hotel on the famous Las Vegas Strip with stunning views and casino access.', 'ACTIVE'),
('Holiday Inn Club Vacations at Desert Club Resort', 'Holiday Inn', 'Las Vegas', 'United States', '10711 W Charleston Blvd, Las Vegas', 4, 145.00, 'USD', 134, 318, 'STANDARD', '24/7 Reception, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Golf Access', 'Resort-style 4-star hotel with golf access and family-friendly amenities in a desert setting.', 'ACTIVE'),
('The Orleans Hotel & Casino', 'Independent', 'Las Vegas', 'United States', '4500 W Tropicana Ave, Las Vegas', 3, 89.00, 'USD', 178, 1886, 'STANDARD', 'Free WiFi, 24/7 Reception, Casino, Bowling, Movie Theater, Multiple Restaurants', 'Budget-friendly casino hotel with extensive entertainment options and good value for Las Vegas.', 'ACTIVE'),
('The Cosmopolitan of Las Vegas', 'InterContinental', 'Las Vegas', 'United States', '3708 Las Vegas Blvd S, Las Vegas', 5, 395.00, 'USD', 45, 3027, 'SUITE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Strip Views, Casino', 'Ultra-luxury 5-star resort on the Strip with sophisticated accommodations and world-class dining.', 'ACTIVE');

-- Tokyo, Japan
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('Tokyo Marriott Hotel', 'Marriott', 'Tokyo', 'Japan', '4-7-36 Kitashinagawa, Tokyo', 5, 285.00, 'USD', 89, 249, 'DELUXE', 'Spa, Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Executive Lounge', 'Elegant hotel in Shinagawa with traditional Japanese hospitality and modern luxury.', 'ACTIVE'),
('Hilton Tokyo', 'Hilton', 'Tokyo', 'Japan', '6-6-2 Nishi-Shinjuku, Tokyo', 5, 245.00, 'USD', 134, 815, 'STANDARD', 'Pool, Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Executive Lounge', 'Iconic Shinjuku hotel with comprehensive facilities and excellent city access.', 'ACTIVE'),
('Holiday Inn Tokyo Shibuya', 'Holiday Inn', 'Tokyo', 'Japan', '2-3-1 Shibuya, Tokyo', 4, 185.00, 'USD', 67, 192, 'STANDARD', '24/7 Reception, Fitness Center, Business Center, Room Service, Free WiFi', 'Modern hotel in vibrant Shibuya district with easy access to shopping and entertainment.', 'ACTIVE'),
('Hotel Gracery Shinjuku', 'Gracery', 'Tokyo', 'Japan', '1-19-1 Kabukicho, Tokyo', 3, 145.00, 'USD', 178, 970, 'STANDARD', 'Free WiFi, 24/7 Reception, Restaurant, Godzilla Head View', 'Unique budget hotel in Shinjuku with famous Godzilla head and convenient location.', 'ACTIVE'),
('InterContinental Tokyo Bay', 'InterContinental', 'Tokyo', 'Japan', '1-16-2 Kaigan, Tokyo', 5, 365.00, 'USD', 45, 330, 'DELUXE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Bay Views', 'Luxury waterfront hotel with stunning Tokyo Bay views and world-class service.', 'ACTIVE');

-- Dubai, United Arab Emirates
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('JW Marriott Marquis Dubai', 'Marriott', 'Dubai', 'United Arab Emirates', 'Sheikh Zayed Road, Dubai', 5, 295.00, 'USD', 89, 1608, 'DELUXE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Multiple Restaurants', 'Twin tower luxury hotel with world-class facilities and stunning city views.', 'ACTIVE'),
('Hilton Dubai Jumeirah', 'Hilton', 'Dubai', 'United Arab Emirates', 'The Walk, Jumeirah Beach Residence, Dubai', 5, 225.00, 'USD', 134, 389, 'STANDARD', 'Beach Access, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Restaurant', 'Beachfront hotel with direct beach access and modern amenities in JBR.', 'ACTIVE'),
('Holiday Inn Dubai Al Barsha', 'Holiday Inn', 'Dubai', 'United Arab Emirates', 'Al Barsha 1, Dubai', 4, 145.00, 'USD', 178, 363, 'STANDARD', '24/7 Reception, Pool, Fitness Center, Business Center, Room Service, Free WiFi', 'Modern hotel near Mall of the Emirates with pool and comprehensive facilities.', 'ACTIVE'),
('Citymax Hotel Al Barsha', 'Citymax', 'Dubai', 'United Arab Emirates', 'Al Barsha 1, Dubai', 3, 95.00, 'USD', 234, 496, 'STANDARD', 'Free WiFi, 24/7 Reception, Pool, Fitness Center, Restaurant', 'Contemporary budget hotel with good facilities and convenient location.', 'ACTIVE'),
('InterContinental Dubai Festival City', 'InterContinental', 'Dubai', 'United Arab Emirates', 'Festival City, Dubai', 5, 385.00, 'USD', 67, 498, 'DELUXE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Creek Views', 'Luxury hotel overlooking Dubai Creek with exceptional service and facilities.', 'ACTIVE');

-- Singapore
INSERT INTO hotels (hotel_name, hotel_chain, city, country, address, star_rating, price_per_night, currency, available_rooms, total_rooms, room_type, amenities, description, status) VALUES
('Singapore Marriott Tang Plaza Hotel', 'Marriott', 'Singapore', 'Singapore', '320 Orchard Road, Singapore', 5, 265.00, 'USD', 89, 393, 'DELUXE', 'Pool, Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Orchard Road Location', 'Prime Orchard Road location with luxury amenities and excellent shopping access.', 'ACTIVE'),
('Hilton Singapore Orchard', 'Hilton', 'Singapore', 'Singapore', '333 Orchard Road, Singapore', 5, 235.00, 'USD', 134, 793, 'STANDARD', 'Pool, Fitness Center, Business Center, Room Service, Free WiFi, Restaurant, Executive Lounge', 'Modern hotel in heart of shopping district with comprehensive facilities.', 'ACTIVE'),
('Holiday Inn Singapore Atrium', 'Holiday Inn', 'Singapore', 'Singapore', '317 Outram Road, Singapore', 4, 165.00, 'USD', 178, 512, 'STANDARD', '24/7 Reception, Pool, Fitness Center, Business Center, Room Service, Free WiFi', 'Centrally located hotel with pool and easy access to attractions and business district.', 'ACTIVE'),
('Hotel Boss', 'Independent', 'Singapore', 'Singapore', '500 Jalan Sultan, Singapore', 3, 125.00, 'USD', 234, 1500, 'STANDARD', 'Free WiFi, 24/7 Reception, Restaurant, Near MRT Station', 'Large budget hotel with good facilities and convenient public transport access.', 'ACTIVE'),
('InterContinental Singapore', 'InterContinental', 'Singapore', 'Singapore', '80 Middle Road, Singapore', 5, 345.00, 'USD', 67, 403, 'DELUXE', 'Spa, Pool, Fitness Center, Business Center, Room Service, Free WiFi, Concierge, Heritage Building', 'Historic luxury hotel with colonial charm and modern amenities in Bugis district.', 'ACTIVE');

-- Verify data insertion
SELECT
    city,
    country,
    COUNT(*) as hotel_count,
    MIN(price_per_night) as min_price,
    MAX(price_per_night) as max_price,
    ROUND(AVG(price_per_night), 2) as avg_price,
    currency
FROM hotels
WHERE status = 'ACTIVE'
GROUP BY city, country, currency
ORDER BY country, city;

-- Show European cities with budget options under €140
SELECT
    city,
    hotel_name,
    price_per_night,
    currency,
    star_rating
FROM hotels
WHERE status = 'ACTIVE'
  AND currency = 'EUR'
  AND price_per_night < 140
ORDER BY city, price_per_night;

-- Show all cities with hotel count
SELECT
    city,
    country,
    COUNT(*) as hotel_count
FROM hotels
WHERE status = 'ACTIVE'
GROUP BY city, country
ORDER BY country, city;

COMMIT;
