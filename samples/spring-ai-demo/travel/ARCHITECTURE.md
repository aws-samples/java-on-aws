# Spring Boot Application Architecture Guidelines

This document outlines the architectural decisions and guidelines for developing Spring Boot web applications with JPA, AI integration, and Domain-Driven Design (DDD) principles. These guidelines are derived from practical implementation experiences in the travel application domains.

## Table of Contents

1. [Domain Model Architecture](#domain-model-architecture)
   - [Entity Design](#entity-design)
   - [ID and Business Identifier Handling](#id-and-business-identifier-handling)
   - [Entity Relationships](#entity-relationships)
   - [Validation Constraints](#validation-constraints)

2. [Layered Architecture](#layered-architecture)
   - [Layer Responsibilities](#layer-responsibilities)
   - [Package Structure](#package-structure)
   - [Dependency Flow](#dependency-flow)

3. [Transaction Management](#transaction-management)
   - [Method-Level Annotations](#method-level-annotations)
   - [Read vs. Write Operations](#read-vs-write-operations)

4. [API Design](#api-design)
   - [Unified Search Endpoints](#unified-search-endpoints)
   - [Resource Identification](#resource-identification)
   - [HTTP Status Codes](#http-status-codes)
   - [Error Handling](#error-handling)

5. [AI Integration](#ai-integration)
   - [Tool Annotations](#tool-annotations)
   - [Parameter Handling](#parameter-handling)
   - [Response Formatting](#response-formatting)

6. [Implementation Examples](#implementation-examples)
   - [Accommodations Domain](#accommodations-domain)
   - [Transportation Domain](#transportation-domain)

## Domain Model Architecture

### Entity Design

Entities should represent domain objects with clear boundaries and responsibilities. They should encapsulate both data and behavior related to their state.

#### Guidelines:

- Use JPA annotations for persistence mapping
- Implement proper equals() and hashCode() based on business identity
- Use lifecycle callbacks (@PrePersist, @PreUpdate) for entity state management
- Keep entities focused on their core domain responsibilities
- Use value objects for complex attributes that don't have identity

```java
@Entity
@Table(name = "hotels")
class Hotel {
    enum RoomType {
        STANDARD, DELUXE, SUITE, EXECUTIVE
    }

    enum HotelStatus {
        ACTIVE, INACTIVE, MAINTENANCE
    }

    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "hotel_name")
    @NotBlank(message = "Hotel name is required")
    private String hotelName;

    // Other fields...

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    // Getters and setters...
}
```

### ID and Business Identifier Handling

#### Guidelines:

- **Primary Key Naming**: Use `id` as the standard primary key field name
  - Consistent across all entities
  - Aligns with Spring Data JPA conventions
  - Simplifies repository and query methods

- **ID Generation**: Use UUID strings for entity IDs
  - Globally unique across all environments
  - No need for database sequences or auto-increment
  - Better for distributed systems and future data migration
  - Use `UUID.randomUUID().toString()` in `@PrePersist` methods

- **Business Identifiers**: Separate business identifiers from technical primary keys
  - Use domain-specific reference codes for business operations (e.g., `bookingReference`, `airportCode`, `flightNumber`)
  - Make business identifiers user-friendly (e.g., alphanumeric codes)
  - Add unique constraints to business identifiers
  - Generate business identifiers automatically in `@PrePersist` methods

```java
@Entity
@Table(name = "flight_bookings")
class FlightBooking {
    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "booking_reference", unique = true)
    @Size(max = 10, message = "Booking reference must not exceed 10 characters")
    private String bookingReference;

    // Other fields...

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }
        if (bookingReference == null || bookingReference.trim().isEmpty()) {
            bookingReference = ReferenceGenerator.generate(6);
        }
        // Other initialization...
    }
}
```

### Entity Relationships

#### Guidelines:

- **Foreign Key Naming**: Use the entity name + "Id" for foreign key fields
  - `hotelId` for a reference to a Hotel entity
  - `flightId` for a reference to a Flight entity
  - Consistent across all relationships

- **One-to-Many Relationships**: Two approaches based on use case:

  1. **ID-Based Approach** (Simpler, less coupled):
     - Store only the foreign key ID in the child entity
     - Good for simpler domains or when entities are in different bounded contexts
     ```java
     @Column(name = "hotel_id")
     private String hotelId;
     ```

  2. **Entity-Based Approach** (More object-oriented, JPA managed):
     - Use `@ManyToOne` and `@JoinColumn` for direct entity relationships
     - Better for complex domains with frequent navigation between entities
     ```java
     @ManyToOne
     @JoinColumn(name = "hotel_id", nullable = false)
     private Hotel hotel;
     ```

- **Choosing Between Approaches**:
  - Use ID-based approach when:
    - Entities belong to different bounded contexts
    - You want to minimize coupling between domains
    - Performance is critical (fewer joins)
    - The relationship is primarily for reference

  - Use entity-based approach when:
    - Entities are in the same bounded context
    - You frequently navigate between related entities
    - You want to leverage JPA's relationship management
    - You need cascading operations

### Validation Constraints

#### Guidelines:

- Use Jakarta Validation annotations for entity validation
- Place constraints on fields that require validation
- Use custom validation messages for clear error reporting
- Be careful with constraints on fields that are calculated or set by the service layer
- Consider partial updates when designing validation constraints

```java
@Column(name = "customer_email")
@NotBlank(message = "Customer email is required")
@Email(message = "Invalid email format")
@Size(max = 255, message = "Email must not exceed 255 characters")
private String customerEmail;
```

## Layered Architecture

### Layer Responsibilities

#### Guidelines:

A five-layer architecture provides clear separation of concerns:

1. **Entity Layer**: Domain model objects
   - JPA entities with annotations
   - Business logic related to entity state
   - Lifecycle callbacks (`@PrePersist`, `@PreUpdate`)

2. **Repository Layer**: Data access
   - Spring Data repositories
   - Custom query methods
   - Package-private visibility

3. **Service Layer**: Business logic
   - Transaction management
   - Domain operations and rules
   - Error handling and validation
   - **Full CRUD operations** for all entities
   - **Dual method interfaces**: object-based for controllers and parameter-based for tools

4. **Controller Layer**: API endpoints
   - Request handling and response formatting
   - Input validation
   - HTTP status codes
   - **Limited operations** based on entity type:
     - Dictionary/reference entities: search and get operations only
     - Main business entities: search, get, create, update operations
   - Uses object-based service methods

5. **Tools Layer**: AI integration
   - `@Tool` annotated methods
   - Delegating to service layer
   - Detailed descriptions for AI consumption
   - **Limited operations** based on entity type:
     - Dictionary/reference entities: search and get operations only
     - Main business entities: search, get, create, update, and business operations (confirm, cancel, etc.)
   - Uses parameter-based service methods

### Service Layer Method Pattern

#### Guidelines:

Services should provide two types of methods for create and update operations:

1. **Object-based methods**: Used by controllers
   - Accept entity objects directly
   - Perform validation on the entity
   - Used for web API interactions
   - Example:
     ```java
     @Transactional
     public HotelBooking createBooking(HotelBooking booking) {
         validateBooking(booking);
         return bookingRepository.save(booking);
     }
     ```

2. **Parameter-based methods**: Used by tools
   - Accept individual parameters
   - Construct entity objects from parameters
   - Delegate to object-based methods
   - Better for AI tool interactions
   - Example:
     ```java
     @Transactional
     public HotelBooking createBooking(String hotelId,
                                     LocalDate checkInDate,
                                     Integer numberOfNights,
                                     String customerName,
                                     String customerEmail) {
         HotelBooking booking = new HotelBooking();
         booking.setHotelId(hotelId);
         booking.setCheckInDate(checkInDate);
         booking.setNumberOfNights(numberOfNights);
         booking.setCustomerName(customerName);
         booking.setCustomerEmail(customerEmail);

         return createBooking(booking);
     }
     ```

This pattern provides:
- Clean separation between web and AI interfaces
- Consistent validation in one place
- Reduced code duplication
- Better maintainability

### Package Structure

#### Guidelines:

- Organize code by domain/feature rather than by layer
- Use consistent package naming across domains
- Keep related classes together in the same package
- Use package-private visibility for implementation details

```
com.example.travel
├── accommodations
│   ├── Hotel.java
│   ├── HotelBooking.java
│   ├── HotelBookingController.java
│   ├── HotelBookingRepository.java
│   ├── HotelBookingService.java
│   ├── HotelBookingTools.java
│   ├── HotelController.java
│   ├── HotelRepository.java
│   ├── HotelService.java
│   └── HotelTools.java
├── transportation
│   ├── Airport.java
│   ├── AirportController.java
│   ├── AirportRepository.java
│   ├── AirportService.java
│   ├── AirportTools.java
│   ├── Flight.java
│   ├── FlightBooking.java
│   ├── FlightBookingController.java
│   ├── FlightBookingRepository.java
│   ├── FlightBookingService.java
│   ├── FlightBookingTools.java
│   ├── FlightController.java
│   ├── FlightRepository.java
│   ├── FlightService.java
│   └── FlightTools.java
└── common
    └── ReferenceGenerator.java
```

### Dependency Flow

#### Guidelines:

- Dependencies should flow inward: Controller → Service → Repository → Entity
- Higher layers should depend on lower layers, not vice versa
- Use interfaces for decoupling when appropriate
- Avoid circular dependencies between domains

## Transaction Management

### Method-Level Annotations

#### Guidelines:

- Apply transaction annotations at the method level rather than the class level
- Use `@Transactional(readOnly = true)` for read operations (get, find, search)
- Use `@Transactional` for write operations (create, update, delete, confirm, cancel)
- Avoid `@Transactional(readOnly = true)` at the class level

```java
@Transactional(readOnly = true)
public Hotel getHotel(String id) {
    // Implementation
}

@Transactional
public Hotel createHotel(Hotel hotel) {
    // Implementation
}
```

### Read vs. Write Operations

#### Guidelines:

- **Read Operations**:
  - Use `@Transactional(readOnly = true)` to optimize database access
  - Return immutable objects or copies when possible
  - Use projection interfaces or DTOs for specific query needs

- **Write Operations**:
  - Use `@Transactional` without readOnly flag
  - Validate input before persisting
  - Handle concurrency with optimistic locking when needed
  - Return the updated entity state

## API Design

### Unified Search Endpoints

#### Guidelines:

- Use consistent patterns for search operations
- Single `/search` endpoint with optional query parameters
- Return collections (List<Entity>) for all search operations
- Return empty list instead of errors for no results
- Support multiple search criteria in one endpoint

```java
@GetMapping("/search")
@ResponseStatus(HttpStatus.OK)
List<Airport> search(@RequestParam(required = false) String city,
                     @RequestParam(required = false) String code) {
    if (city != null) {
        return airportService.findByCity(city);
    } else if (code != null) {
        List<Airport> result = new ArrayList<>();
        try {
            result.add(airportService.findByAirportCode(code));
        } catch (ResponseStatusException e) {
            // Return empty list if not found
        }
        return result;
    } else {
        return Collections.emptyList();
    }
}
```

### Resource Identification

#### Guidelines:

- Use consistent patterns for resource identification
- Use `/{id}` for retrieving by technical ID
- Use business identifiers in search endpoints
- Use business identifiers for business operations (confirm, cancel)

```java
// Get by technical ID
@GetMapping("/{id}")
@ResponseStatus(HttpStatus.OK)
Hotel getHotel(@PathVariable String id) {
    return hotelService.getHotel(id);
}

// Business operations using business identifier
@PutMapping("/{bookingReference}/confirm")
@ResponseStatus(HttpStatus.OK)
HotelBooking confirmBooking(@PathVariable String bookingReference) {
    return hotelBookingService.confirmBooking(bookingReference);
}
```

### HTTP Status Codes

#### Guidelines:

- Use appropriate HTTP status codes for different scenarios
- 200 OK: Successful GET, PUT, PATCH operations
- 201 Created: Successful POST operations
- 204 No Content: Successful DELETE operations
- 400 Bad Request: Invalid input, validation errors
- 404 Not Found: Resource not found
- 409 Conflict: Resource already exists
- 500 Internal Server Error: Unexpected server errors

```java
@PostMapping
@ResponseStatus(HttpStatus.CREATED)
HotelBooking createBooking(@Valid @RequestBody HotelBooking hotelBooking) {
    return bookingService.createBooking(hotelBooking);
}
```

### Error Handling

#### Guidelines:

- Use `ResponseStatusException` for HTTP-specific errors
- Include detailed error messages
- Log errors with context
- Return consistent error response format

```java
if (hotel.isEmpty()) {
    logger.warn("Hotel not found with ID: {}", id);
    throw new ResponseStatusException(HttpStatus.NOT_FOUND,
        "Hotel not found with ID: " + id);
}
```

## AI Integration

### Tool Annotations

#### Guidelines:

- Place `@Tool` annotations in separate Tools classes
- Delegate to service methods for actual implementation
- Provide detailed descriptions for AI consumption
- Include error conditions and expected behavior

```java
@Tool(description = """
    Find hotel booking by reference code.
    Requires: bookingReference - The unique booking identifier.
    Returns: Complete booking details including hotel information and guest data.
    Errors: NOT_FOUND if booking doesn't exist.
    """)
public HotelBooking findHotelBookingByBookingReference(String bookingReference) {
    return bookingService.findByBookingReference(bookingReference);
}
```

### Parameter Handling

#### Guidelines:

- Use individual parameters for better AI interaction
- List all required parameters explicitly
- Provide detailed descriptions for each parameter
- Use simple types that can be easily understood by AI

```java
@Tool(description = "Create a new flight booking...")
public FlightBooking createFlightBooking(String flightNumber,
                                       LocalDate flightDate,
                                       String customerName,
                                       String customerEmail,
                                       Integer numberOfPassengers) {
    // Implementation
}
```

### Response Formatting

#### Guidelines:

- Return domain objects directly when possible
- Use consistent response formats
- Include all necessary information for AI to understand the response
- Consider adding helper methods for complex response formatting

## Implementation Examples

### Accommodations Domain

#### Entity Layer Example (Hotel.java)

```java
@Entity
@Table(name = "hotels")
class Hotel {
    enum RoomType {
        STANDARD, DELUXE, SUITE, EXECUTIVE
    }

    enum HotelStatus {
        ACTIVE, INACTIVE, MAINTENANCE
    }

    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "hotel_name")
    @NotBlank(message = "Hotel name is required")
    private String hotelName;

    // Other fields...

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    // Getters and setters...
}
```

#### Repository Layer Example

```java
@Repository
interface HotelRepository extends CrudRepository<Hotel, String> {
    List<Hotel> findByCityContainingIgnoreCaseAndStatus(String city, Hotel.HotelStatus status);
    List<Hotel> findByHotelNameContainingIgnoreCase(String hotelName);
}
```

#### Service Layer Example

```java
@Service
public class HotelBookingService {
    private final HotelBookingRepository bookingRepository;
    private final HotelService hotelService;

    HotelBookingService(HotelBookingRepository bookingRepository, HotelService hotelService) {
        this.bookingRepository = bookingRepository;
        this.hotelService = hotelService;
    }

    // Object-based method for controllers
    @Transactional
    public HotelBooking createBooking(HotelBooking booking) {
        validateBooking(booking);

        // Calculate derived fields
        Hotel hotel = hotelService.getHotel(booking.getHotelId());
        booking.setTotalPrice(calculateTotalPrice(hotel, booking.getNumberOfNights()));
        booking.setCurrency(hotel.getCurrency());

        return bookingRepository.save(booking);
    }

    // Parameter-based method for tools
    @Transactional
    public HotelBooking createBooking(String hotelId,
                                     LocalDate checkInDate,
                                     Integer numberOfNights,
                                     String customerName,
                                     String customerEmail) {
        // Create booking object from parameters
        HotelBooking booking = new HotelBooking();
        booking.setHotelId(hotelId);
        booking.setCheckInDate(checkInDate);
        booking.setNumberOfNights(numberOfNights);
        booking.setCustomerName(customerName);
        booking.setCustomerEmail(customerEmail);

        // Delegate to object-based method
        return createBooking(booking);
    }

    @Transactional(readOnly = true)
    public HotelBooking getBooking(String id) {
        return bookingRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Booking not found with ID: " + id));
    }

    @Transactional(readOnly = true)
    public HotelBooking findByBookingReference(String bookingReference) {
        return bookingRepository.findByBookingReference(bookingReference)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Booking not found with reference: " + bookingReference));
    }

    // Other methods...
}
```

#### Controller Layer Example

```java
@RestController
@RequestMapping("api/hotel-bookings")
class HotelBookingController {
    private final HotelBookingService bookingService;

    HotelBookingController(HotelBookingService bookingService) {
        this.bookingService = bookingService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    HotelBooking createBooking(@Valid @RequestBody HotelBooking booking) {
        // Use object-based service method
        return bookingService.createBooking(booking);
    }

    @GetMapping("/{id}")
    @ResponseStatus(HttpStatus.OK)
    HotelBooking getBooking(@PathVariable String id) {
        return bookingService.getBooking(id);
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    List<HotelBooking> search(@RequestParam(required = false) String reference) {
        if (reference != null) {
            List<HotelBooking> result = new ArrayList<>();
            try {
                result.add(bookingService.findByBookingReference(reference));
            } catch (ResponseStatusException e) {
                // Return empty list if not found
            }
            return result;
        } else {
            return Collections.emptyList();
        }
    }

    // Other endpoints...
}
```

#### Tools Layer Example

```java
@Component
public class HotelBookingTools {
    private final HotelBookingService bookingService;

    public HotelBookingTools(HotelBookingService bookingService) {
        this.bookingService = bookingService;
    }

    @Bean
    public ToolCallbackProvider hotelBookingToolsProvider(HotelBookingTools hotelBookingTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(hotelBookingTools)
                .build();
    }

    @Tool(description = """
        Create a new hotel booking.
        Requires: hotelId - ID of the hotel to book,
                 checkInDate - Date of check-in (YYYY-MM-DD),
                 numberOfNights - Number of nights to stay,
                 customerName - Name of the customer,
                 customerEmail - Email of the customer.
        Returns: The created booking with generated ID, reference, and calculated price.
        Errors: NOT_FOUND if hotel doesn't exist, BAD_REQUEST if dates are invalid.
        """)
    public HotelBooking createHotelBooking(String hotelId,
                                         LocalDate checkInDate,
                                         Integer numberOfNights,
                                         String customerName,
                                         String customerEmail) {
        // Use parameter-based service method
        return bookingService.createBooking(
            hotelId, checkInDate, numberOfNights, customerName, customerEmail);
    }

    @Tool(description = """
        Find hotel booking by reference code.
        Requires: bookingReference - The unique booking identifier.
        Returns: Complete booking details including hotel information and guest data.
        Errors: NOT_FOUND if booking doesn't exist.
        """)
    public HotelBooking findHotelBookingByReference(String bookingReference) {
        return bookingService.findByBookingReference(bookingReference);
    }

    // Other tool methods...
}
```

### Transportation Domain

#### Entity Layer Example (Flight.java)

```java
@Entity
@Table(name = "flights")
class Flight {
    enum FlightStatus {
        SCHEDULED, DELAYED, CANCELLED, COMPLETED
    }

    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "flight_number", unique = true)
    @NotBlank(message = "Flight number is required")
    private String flightNumber;

    @Column(name = "departure_airport")
    @NotBlank(message = "Departure airport is required")
    private String departureAirport;

    @Column(name = "arrival_airport")
    @NotBlank(message = "Arrival airport is required")
    private String arrivalAirport;

    // Other fields...

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    // Getters and setters...
}
```

#### Service Layer Example

```java
@Service
public class FlightService {
    private final FlightRepository flightRepository;
    private final AirportRepository airportRepository;

    public FlightService(FlightRepository flightRepository, AirportRepository airportRepository) {
        this.flightRepository = flightRepository;
        this.airportRepository = airportRepository;
    }

    @Transactional(readOnly = true)
    public Flight getflight(String id) {
        return flightRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Flight not found with id: " + id));
    }

    @Transactional(readOnly = true)
    public Flight findByFlightNumber(String flightNumber) {
        return flightRepository.findByFlightNumber(flightNumber)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Flight not found with number: " + flightNumber));
    }

    @Transactional
    public Flight createFlight(Flight flight) {
        // Validation and business logic
        return flightRepository.save(flight);
    }

    // Other methods...
}
```

#### Controller Layer Example

```java
@RestController
@RequestMapping("api/flights")
class FlightController {
    private final FlightService flightService;

    FlightController(FlightService flightService) {
        this.flightService = flightService;
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    List<Flight> search(
            @RequestParam(required = false) String departureCity,
            @RequestParam(required = false) String arrivalCity,
            @RequestParam(required = false) String flightNumber) {

        if (departureCity != null && arrivalCity != null) {
            return flightService.findFlightsByRoute(departureCity, arrivalCity);
        } else if (flightNumber != null) {
            List<Flight> result = new ArrayList<>();
            try {
                result.add(flightService.findByFlightNumber(flightNumber));
            } catch (ResponseStatusException e) {
                // Return empty list if not found
            }
            return result;
        } else {
            return Collections.emptyList();
        }
    }

    @GetMapping("/{id}")
    @ResponseStatus(HttpStatus.OK)
    Flight getFlight(@PathVariable String id) {
        return flightService.getFlight(id);
    }

    // Other endpoints...
}
```

#### Tools Layer Example

```java
@Component
public class FlightTools {
    private final FlightService flightService;

    public FlightTools(FlightService flightService) {
        this.flightService = flightService;
    }

    @Bean
    public ToolCallbackProvider flightToolsProvider(FlightTools flightTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(flightTools)
                .build();
    }

    @Tool(description = """
        Find flights between two cities.
        Requires: departureCity - Name of the departure city,
                 arrivalCity - Name of the arrival city.
        Returns: List of available flights sorted by price from lowest to highest.
        Errors: NOT_FOUND if no flights found between the specified cities.
        """)
    public List<Flight> findFlightsByRoute(String departureCity, String arrivalCity) {
        return flightService.findFlightsByRoute(departureCity, arrivalCity);
    }

    // Other tool methods...
}
```

## Conclusion

These architectural guidelines provide a foundation for building maintainable, scalable Spring Boot applications with JPA, AI integration, and DDD principles. By following these patterns consistently across domains, you'll create a codebase that is easier to understand, extend, and maintain over time.

The examples from the accommodations and transportation domains demonstrate how these principles can be applied in practice, showing the benefits of consistent naming conventions, clear separation of concerns, and proper handling of business identifiers and technical IDs.
