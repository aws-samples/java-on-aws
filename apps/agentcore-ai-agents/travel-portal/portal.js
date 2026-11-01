// Corporate travel portal: static pages, data generated in the page so any route and date returns the same offers.
// Pages render synchronously (no fetch), so the text is in the DOM at DOMContentLoaded for browser automation.

const AIRPORTS = {
  BER: "Berlin", MUC: "Munich", FRA: "Frankfurt", LHR: "London", CDG: "Paris", AMS: "Amsterdam",
  NRT: "Tokyo Narita", HND: "Tokyo Haneda", TYO: "Tokyo", JFK: "New York", SFO: "San Francisco",
  TPA: "Tampa", SIN: "Singapore", DXB: "Dubai", IST: "Istanbul", HEL: "Helsinki", ZRH: "Zurich",
};
const CITY_AIRPORTS = {
  tokyo: "TYO", berlin: "BER", london: "LHR", paris: "CDG", munich: "MUC", "new york": "JFK", "san francisco": "SFO",
};
const AIRLINES = [
  ["LH", "Lufthansa", "FRA"], ["NH", "ANA", "MUC"], ["JL", "Japan Airlines", "HEL"], ["AY", "Finnair", "HEL"],
  ["TK", "Turkish Airlines", "IST"], ["EK", "Emirates", "DXB"], ["LX", "SWISS", "ZRH"], ["KL", "KLM", "AMS"],
];
const HOTELS = {
  "San Francisco": [
    ["SoMa Business Hotel", "SoMa", 3, 129], ["Market Street Hotel", "Market Street", 4, 149],
    ["Yerba Buena Suites", "Yerba Buena", 4, 185], ["Mission Bay Hotel", "Mission Bay", 4, 165],
    ["Union Square Inn", "Union Square", 3, 119], ["Embarcadero Grand", "Embarcadero", 5, 420],
  ],
  default: [
    ["City Center Hotel", "Center", 3, 105], ["Business Inn", "Center", 3, 92],
    ["Grand Hotel", "Old Town", 4, 160], ["Palace Hotel", "Center", 5, 410],
  ],
};

// Default trip dates relative to today: the Monday of the week that contains today plus two months, back on Saturday
function isoDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function tripDates() {
  const today = new Date();
  const start = new Date(today.getFullYear(), today.getMonth() + 2, today.getDate());
  if (start.getDate() !== today.getDate()) start.setDate(0); // Dec 31 + 2 months: the last day of February
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 5);
  return { start: isoDate(start), end: isoDate(end) };
}
const TRIP = tripDates();
function cityName(value) {
  return value.trim().toLowerCase().split(/\s+/).map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
}

function seed(text) {
  let h = 2166136261;
  for (const c of text) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
  return () => ((h = Math.imul(h ^ (h >>> 15), 2246822507) >>> 0) / 4294967296);
}
function param(name, fallback = "") {
  return new URLSearchParams(location.search).get(name) || fallback;
}
function code(value) {
  const v = value.trim();
  return CITY_AIRPORTS[v.toLowerCase()] || v.toUpperCase().slice(0, 3);
}
function el(html) {
  const t = document.createElement("template");
  t.innerHTML = html.trim();
  return t.content;
}
function longHaul(from, to) {
  const asia = ["TYO", "NRT", "HND", "SIN"], america = ["JFK", "SFO", "TPA"];
  return [from, to].some((c) => asia.includes(c) || america.includes(c));
}

function flights(from, to, date, cabin) {
  const rnd = seed(`${from}-${to}-${date}`);
  const long = longHaul(from, to);
  const factor = { ECONOMY: 1, PREMIUM_ECONOMY: 1.8, BUSINESS: 4.2 }[cabin] || 1;
  return AIRLINES.slice(0, 6).map(([iata, name, hub], i) => {
    const stops = i === 1 && long ? 0 : rnd() < 0.3 ? 2 : 1;
    const hours = (long ? 11.5 : 1.5) + stops * 2.5 + Math.round(rnd() * 3);
    const departure = 6 + Math.floor(rnd() * 14);
    const base = (long ? 640 : 120) + Math.round(rnd() * (long ? 520 : 180)) - (stops === 2 ? 90 : 0);
    const co2 = Math.round((long ? 480 : 95) * (1 + stops * 0.12) * (cabin === "BUSINESS" ? 2.9 : 1) * (0.9 + rnd() * 0.2));
    return {
      flight: `${iata} ${100 + Math.floor(rnd() * 800)}`, airline: name,
      via: stops === 0 ? "nonstop" : stops === 1 ? hub : `${hub}, ${AIRLINES[(i + 3) % 8][2]}`,
      stops, departure: `${String(departure).padStart(2, "0")}:${rnd() < 0.5 ? "10" : "45"}`,
      duration: `${Math.floor(hours)}h ${rnd() < 0.5 ? "05" : "40"}m`,
      price: Math.round(base * factor), co2,
    };
  }).sort((a, b) => a.price - b.price);
}

function renderFlights() {
  const from = code(param("from", "BER")), to = code(param("to", "SFO"));
  const date = param("date", TRIP.start), cabin = param("cabin", "ECONOMY").toUpperCase();
  document.title = `Flights ${from} to ${to} on ${date} - Corporate Travel Portal`;
  const rows = flights(from, to, date, cabin).map((f) =>
    `<tr><td>${f.flight}</td><td>${f.airline}</td><td>${f.departure}</td><td>${f.duration}</td>` +
    `<td>${f.via}</td><td>${cabin.replace("_", " ").toLowerCase()}</td><td class="num">${f.price} EUR</td>` +
    `<td class="num">${f.co2} kg</td><td><a href="booking.html?flight=${encodeURIComponent(f.flight)}` +
    `&from=${from}&to=${to}&date=${date}&price=${f.price}">Select</a></td></tr>`).join("");
  document.getElementById("results").append(el(
    `<h2>${AIRPORTS[from] || from} (${from}) to ${AIRPORTS[to] || to} (${to}), ${date}</h2>` +
    `<p>Round trip prices per person, sorted by price. Policy: economy class for all flights.</p>` +
    `<table><thead><tr><th>Flight</th><th>Airline</th><th>Departure</th><th>Duration</th><th>Via</th>` +
    `<th>Class</th><th>Price</th><th>CO2</th><th></th></tr></thead><tbody>${rows}</tbody></table>`));
}

function renderHotels() {
  const name = cityName(param("city", "San Francisco"));
  const nights = Math.max(1, Math.round((new Date(param("checkout", TRIP.end)) - new Date(param("checkin", TRIP.start))) / 864e5)) || 5;
  document.title = `Hotels in ${name} - Corporate Travel Portal`;
  const rows = (HOTELS[name] || HOTELS.default).map(([hotel, district, stars, rate]) =>
    `<tr><td>${hotel}</td><td>${district}</td><td>${"★".repeat(stars)}</td><td class="num">${rate} USD</td>` +
    `<td class="num">${rate * nights} USD</td></tr>`).join("");
  document.getElementById("results").append(el(
    `<h2>Hotels in ${name}, ${nights} nights</h2>` +
    `<p>Rates per night, taxes included. Check the hotel limit of your region before booking.</p>` +
    `<table><thead><tr><th>Hotel</th><th>District</th><th>Category</th><th>Per night</th><th>Total</th></tr></thead>` +
    `<tbody>${rows}</tbody></table>`));
}

function renderBooking() {
  for (const name of ["flight", "from", "to", "date", "price"]) {
    const input = document.querySelector(`[name=${name}]`);
    if (input && param(name)) input.value = param(name);
  }
  document.getElementById("booking").addEventListener("submit", (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.target));
    const reference = "BK-" + Math.floor(seed(JSON.stringify(data))() * 1e6).toString().padStart(6, "0");
    document.getElementById("confirmation").textContent =
      `Booking request ${reference} for ${data.traveler}: flight ${data.flight} ${data.from}-${data.to} on ${data.date}. ` +
      `Status: waiting for manager approval.`;
  });
}

function renderHome() {
  document.querySelector("[name=date]").value = TRIP.start;
  document.getElementById("flights-link").textContent = `flights.html?from=BER&to=SFO&date=${TRIP.start}`;
  document.getElementById("hotels-link").textContent =
    `hotels.html?city=San Francisco&checkin=${TRIP.start}&checkout=${TRIP.end}`;
}

// Loaded at the end of <body>: render right away, before DOMContentLoaded
const page = document.body.dataset.page;
if (page === "home") renderHome();
if (page === "flights") renderFlights();
if (page === "hotels") renderHotels();
if (page === "booking") renderBooking();
