// ── LOCATIONS — ordered: Airports → Cities → Hotels → Beaches ─────────────────
const pickupOptions = [
    // Airports
    "Liberia Airport (LIR)",
    "San José Airport (SJO)",
    // Cities / regions
    "La Fortuna",
    "Monteverde",
    "Rincon de la Vieja",
    "Samara",
    "Nosara",
    "Las Catalinas",
    // Hotels — Peninsula Papagayo (deep)
    "Andaz Costa Rica Resort at Peninsula Papagayo",
    "Four Seasons Resort Costa Rica",
    "Nekajui Peninsula Papagayo a Ritz-Carlton Reserve",
    // Hotels — Papagayo Gulf
    "Casa Conde Beach Front Hotel",
    "El Mangroove Autograph Collection",
    "Occidental Papagayo - Adults Only",
    "Planet Hollywood Costa Rica",
    "Secrets Papagayo Costa Rica",
    // Hotels — Hermosa / Coco
    "Hotel Bahía Pez Vela",
    "Hotel Bosque del Mar",
    "Hotel Coco Beach",
    "Hotel Condovac La Costa",
    "Hotel Villa del Sol",
    "Villas Playa Hermosa",
    // Hotels — Flamingo / Conchal
    "Flamingo Beach Resort",
    "Margaritaville Beach Resort Flamingo",
    "The Westin Reserva Conchal",
    "W Costa Rica - Reserva Conchal",
    // Hotels — RIU
    "Hotel Riu Guanacaste",
    "Hotel Riu Palace Guanacaste",
    // Hotels — Tamarindo area
    "Cala Luna Boutique Hotel",
    "Hotel Occidental Tamarindo",
    "Hotel Playa Grande Surf Camp",
    "JW Marriott Guanacaste Resort & Spa",
    "Tamarindo Diria Beach Resort",
    "Wyndham Tamarindo",
    // Hoteles - Rincon de La vIEJA
    "Hotel Hacienda Guachipelin",
    "Hotel Borinquen Mountain Resort & Spa",
    "Hotel Buena vista del Rincón", 
    // Beaches
    "Playa Avellanas",
    "Playa Brasilito",
    "Playa Conchal",
    "Playa Flamingo",
    "Playa Grande",
    "Playa Hermosa",
    "Playa Langosta",
    "Playa Ocotal",
    "Playa Panamá",
    "Playa Tamarindo",
    "Playas del Coco",
];

const dropoffOptions = [...pickupOptions];

// ── ZONE MAPPING ──────────────────────────────────────────────────────────────
const locationZones = {
    "Liberia Airport (LIR)":                              "LIR",
    "San José Airport (SJO)":                             "SJO",
    "La Fortuna":                                         "LA_FORTUNA",
    "Monteverde":                                         "MONTEVERDE",
    "Four Seasons Resort Costa Rica":                     "PAPAGAYO_DEEP",
    "Andaz Costa Rica Resort at Peninsula Papagayo":      "PAPAGAYO_DEEP",
    "Nekajui Peninsula Papagayo a Ritz-Carlton Reserve":  "PAPAGAYO_DEEP",
    "Planet Hollywood Costa Rica":                        "PAPAGAYO_GULF",
    "Secrets Papagayo Costa Rica":                        "PAPAGAYO_GULF",
    "El Mangroove Autograph Collection":                  "PAPAGAYO_GULF",
    "Occidental Papagayo - Adults Only":                  "PAPAGAYO_GULF",
    "Casa Conde Beach Front Hotel":                       "PAPAGAYO_GULF",
    "Playa Panamá":                                       "PAPAGAYO_GULF",
    "Hotel Bosque del Mar":                               "HERMOSA_COCO",
    "Villas Playa Hermosa":                               "HERMOSA_COCO",
    "Hotel Condovac La Costa":                            "HERMOSA_COCO",
    "Playa Hermosa":                                      "HERMOSA_COCO",
    "Hotel Coco Beach":                                   "HERMOSA_COCO",
    "Hotel Villa del Sol":                                "HERMOSA_COCO",
    "Playas del Coco":                                    "HERMOSA_COCO",
    "Hotel Bahía Pez Vela":                               "HERMOSA_COCO",
    "Playa Ocotal":                                       "HERMOSA_COCO",
    "Hotel Riu Guanacaste":                               "RIU_HOTELS",
    "Hotel Riu Palace Guanacaste":                        "RIU_HOTELS",
    "Margaritaville Beach Resort Flamingo":               "FLAMINGO_CONCHAL",
    "Flamingo Beach Resort":                              "FLAMINGO_CONCHAL",
    "Playa Flamingo":                                     "FLAMINGO_CONCHAL",
    "The Westin Reserva Conchal":                         "FLAMINGO_CONCHAL",
    "W Costa Rica - Reserva Conchal":                     "FLAMINGO_CONCHAL",
    "Playa Conchal":                                      "FLAMINGO_CONCHAL",
    "Playa Brasilito":                                    "FLAMINGO_CONCHAL",
    "JW Marriott Guanacaste Resort & Spa":                "TAMARINDO_SURROUND",
    "Tamarindo Diria Beach Resort":                       "TAMARINDO_MAIN",
    "Hotel Occidental Tamarindo":                         "TAMARINDO_MAIN",
    "Wyndham Tamarindo":                                  "TAMARINDO_MAIN",
    "Cala Luna Boutique Hotel":                           "TAMARINDO_MAIN",
    "Playa Tamarindo":                                    "TAMARINDO_MAIN",
    "Playa Langosta":                                     "TAMARINDO_MAIN",
    "Hotel Playa Grande Surf Camp":                       "TAMARINDO_SURROUND",
    "Playa Grande":                                       "TAMARINDO_SURROUND",
    "Playa Avellanas":                                    "TAMARINDO_SURROUND",
    "Hotel Hacienda Guachipelin":                         "RINCON_DE_LA_VIEJA",
    "Hotel Borinquen Mountain Resort & Spa":              "RINCON_DE_LA_VIEJA",
    "Hotel Buena vista del Rincón":                       "RINCON_DE_LA_VIEJA",
    "Samara":                                             "Samara",
    "Nosara":                                             "Nosara",
    "Las Catalinas":                                      "Las Catalinas"
};

// ── PRICING MATRIX ────────────────────────────────────────────────────────────
// hiace_s = 1–4 pax · hiace_l = 5–9 pax · coaster = 10–16 pax
const zonePricingMatrix = {
    "LIR-TAMARINDO_MAIN":     { duration: "1h 20m", prices: { hiace_s: 170, hiace_l: 230, coaster: 330 } },
    "LIR-TAMARINDO_SURROUND": { duration: "1h 35m", prices: { hiace_s: 185, hiace_l: 245, coaster: 340 } },
    "LIR-PAPAGAYO_DEEP":      { duration: "45m",    prices: { hiace_s: 140, hiace_l: 200, coaster: 275 } },
    "LIR-PAPAGAYO_GULF":      { duration: "30m",    prices: { hiace_s: 140, hiace_l: 200, coaster: 275 } },
    "LIR-HERMOSA_COCO":       { duration: "35m",    prices: { hiace_s: 140, hiace_l: 200, coaster: 275 } },
    "LIR-RIU_HOTELS":         { duration: "45m",    prices: { hiace_s: 140, hiace_l: 200, coaster: 275 } },
    "LIR-FLAMINGO_CONCHAL":   { duration: "1h 10m", prices: { hiace_s: 170, hiace_l: 230, coaster: 330 } },
    "LIR-LA_FORTUNA":         { duration: "3h 00m", prices: { hiace_s: 310, hiace_l: 370, coaster: 500 } },
    "LIR-MONTEVERDE":         { duration: "3h 00m", prices: { hiace_s: 310, hiace_l: 370, coaster: 500 } },
    "LIR-SJO":                { duration: "4h 30m", prices: { hiace_s: 370, hiace_l: 425, coaster: 610 } },
    "LIR-RINCON_DE_LA_VIEJA": { duration: "1h 15m", prices: { hiace_s: 160, hiace_l: 220, coaster: 290 } },
    "LIR-SAMARA":             { duration: "2h 45m", prices: { hiace_s: 250, hiace_l: 300, coaster: 390 } },
    "LIR-NOSARA":             { duration: "3h 00m", prices: { hiace_s: 290, hiace_l: 345, coaster: 450 } },
    "LIR-LAS_CATALINAS":      { duration: "1h 45m", prices: { hiace_s: 185, hiace_l: 245, coaster: 340 } },
    "SJO-TAMARINDO_MAIN":     { duration: "4h 30m", prices: { hiace_s: 450, hiace_l: 510, coaster: 720 } },
    "SJO-TAMARINDO_SURROUND": { duration: "4h 45m", prices: { hiace_s: 470, hiace_l: 530, coaster: 740 } },
    "SJO-LA_FORTUNA":         { duration: "3h 00m", prices: { hiace_s: 330, hiace_l: 400, coaster: 600 } },
    "SJO-MONTEVERDE":         { duration: "4h 15m", prices: { hiace_s: 470, hiace_l: 530, coaster: 730 } },
    "SJO-PAPAGAYO_DEEP":      { duration: "4h 30m", prices: { hiace_s: 410, hiace_l: 470, coaster: 640 } },
    "SJO-PAPAGAYO_GULF":      { duration: "4h 10m", prices: { hiace_s: 410, hiace_l: 470, coaster: 640 } },
    "SJO-HERMOSA_COCO":       { duration: "4h 15m", prices: { hiace_s: 410, hiace_l: 470, coaster: 640 } },
    "SJO-RIU_HOTELS":         { duration: "4h 20m", prices: { hiace_s: 410, hiace_l: 470, coaster: 640 } },
    "SJO-FLAMINGO_CONCHAL":   { duration: "4h 20m", prices: { hiace_s: 450, hiace_l: 510, coaster: 720 } },
    "Rincon_de_la_Vieja-PAPAGAYO_DEEP":      { duration: "1h 30m",    prices: { hiace_s: 200,  hiace_l: 260, coaster: 315 } },
    "Rincon_de_la_Vieja-PAPAGAYO_GULF":      { duration: "1h 30m",    prices: { hiace_s: 200,  hiace_l: 260, coaster: 315 } },
    "Rincon_de_la_Vieja-HERMOSA_COCO":       { duration: "1h 30m",    prices: { hiace_s: 200,  hiace_l: 260, coaster: 315 } },
    "Rincon_de_la_Vieja-RIU_HOTELS":         { duration: "1h 45m",    prices: { hiace_s: 200,  hiace_l: 260, coaster: 315 } },
    "Rincon_de_la_Vieja-TAMARINDO_MAIN":     { duration: "2h 20m",    prices: { hiace_s: 230,  hiace_l: 290, coaster: 390 } },
    "Rincon_de_la_Vieja-TAMARINDO_SURROUND": { duration: "2h 35m",    prices: { hiace_s: 245,  hiace_l: 300, coaster: 400 } },
    "Rincon_de_la_Vieja-FLAMINGO_CONCHAL":   { duration: "2h 20m",    prices: { hiace_s: 230,  hiace_l: 290, coaster: 390 } },
    "MONTEVERDE-PAPAGAYO_DEEP":              { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 470 } },
    "MONTEVERDE-PAPAGAYO_GULF":              { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 470 } },
    "MONTEVERDE-HERMOSA_COCO":               { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 470 } },
    "MONTEVERDE-RIU_HOTELS":                 { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 470 } },
    "MONTEVERDE-TAMARINDO_MAIN":             { duration: "3h 30m",    prices: { hiace_s: 335,  hiace_l: 390, coaster: 540 } },
    "MONTEVERDE-TAMARINDO_SURROUND":         { duration: "3h 45m",    prices: { hiace_s: 355,  hiace_l: 410, coaster: 560 } },
    "MONTEVERDE-FLAMINGO_CONCHAL":           { duration: "3h 30m",    prices: { hiace_s: 335,  hiace_l: 390, coaster: 540 } },
    "LA_FORTUNA-PAPAGAYO_DEEP":              { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 500 } },
    "LA_FORTUNA-PAPAGAYO_GULF":              { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 500 } },
    "LA_FORTUNA-HERMOSA_COCO":               { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 500 } },
    "LA_FORTUNA-RIU_HOTELS":                 { duration: "3h 00m",    prices: { hiace_s: 305,  hiace_l: 365, coaster: 500 } },
    "LA_FORTUNA-TAMARINDO_MAIN":             { duration: "3h 30m",    prices: { hiace_s: 365,  hiace_l: 430, coaster: 610 } },
    "LA_FORTUNA-TAMARINDO_SURROUND":         { duration: "3h 45m",    prices: { hiace_s: 385,  hiace_l: 450, coaster: 530 } },
    "LA_FORTUNA-FLAMINGO_CONCHAL":           { duration: "3h 30m",    prices: { hiace_s: 365,  hiace_l: 430, coaster: 610 } },
};

// ── VEHICLES ──────────────────────────────────────────────────────────────────
const vehicles = {
    hiace_s:  { name: "Toyota Hiace",   icon: "🚐", capacity: "1–4 pax",   badge: "Small Group",  desc: "Private transfer, ideal for couples and small families." },
    hiace_l:  { name: "Toyota Hiace",   icon: "🚐", capacity: "5–9 pax",   badge: "Medium Group", desc: "Spacious Hiace for groups of 5 to 9 passengers." },
    coaster:  { name: "Toyota Coaster", icon: "🚌", capacity: "10–16 pax", badge: "Large Group",  desc: "Maximum comfort for larger groups." },
};

// ── EXTRAS ────────────────────────────────────────────────────────────────────
const extrasConfig = {
    beerQty:        { label: "Local Beer",   price: 4  },
    softDrinkQty:   { label: "Soft Drinks",  price: 3  },
    juiceQty:       { label: "Natural Juice",price: 2  },
    groceryStopQty: { label: "Grocery Stop", price: 40 },
    chipsQty:       { label: "Chips",        price: 3  },
    cookiesQty:     { label: "Cookies",      price: 4  },
    nutsQty:        { label: "Nuts",         price: 5  },
};

// ── STATE ─────────────────────────────────────────────────────────────────────
let selectedVehicle = null;
const $   = id => document.getElementById(id);
const val = id => ($( id)?.value ?? "").trim();

// ── HELPERS ───────────────────────────────────────────────────────────────────
function getRouteKey(zoneA, zoneB) {
    if (!zoneA || !zoneB) return null;
    if (zonePricingMatrix[`${zoneA}-${zoneB}`]) return `${zoneA}-${zoneB}`;
    if (zonePricingMatrix[`${zoneB}-${zoneA}`]) return `${zoneB}-${zoneA}`;
    return null;
}

function getRouteData(pickupZone, dropoffZone) {
    const key = getRouteKey(pickupZone, dropoffZone);
    return key ? zonePricingMatrix[key] : null;
}

const money = v => `$${Math.round(v || 0)} USD`;
const pax   = () => Number($("adults")?.value || 0) + Number($("children")?.value || 0);

function extrasTotal() {
    return Object.entries(extrasConfig).reduce((sum, [id, cfg]) => {
        return sum + (Number($(id)?.value || 0) * cfg.price);
    }, 0);
}

function getExtrasList() {
    return Object.entries(extrasConfig)
        .filter(([id]) => Number($(id)?.value || 0) > 0)
        .map(([id, cfg]) => `• ${cfg.label} x${$(id).value}`)
        .join("\n");
}

function formatDate(dateStr) {
    if (!dateStr) return "";
    const d = new Date(dateStr + "T12:00:00");
    return d.toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" });
}

// ── QUOTE NUMBER — random on load, gives "real system" feel ───────────────────
const QUOTE_NUM = "WP-" + String(Math.floor(10000 + Math.random() * 90000));

function initQuoteNumber() {
    const el = $("quoteNumber");
    if (el) el.textContent = `Quote #${QUOTE_NUM}`;
}

// ── VEHICLE RENDERING ─────────────────────────────────────────────────────────
function getVehicleOptions(totalPax) {
    if (totalPax <= 4)  return ["hiace_s"];
    if (totalPax <= 9)  return ["hiace_l"];
    if (totalPax <= 16) return ["coaster"];
    return ["custom"];
}

function renderVehicles() {
    const totalPax = pax();
    const options  = getVehicleOptions(totalPax);
    const box      = $("vehicleOptions");
    if (!box) return;
    box.innerHTML  = "";

    if (!selectedVehicle || !options.includes(selectedVehicle)) selectedVehicle = options[0];

    if (options[0] === "custom") {
        $("customQuoteBox")?.classList.remove("is-hidden");
        return;
    }
    $("customQuoteBox")?.classList.add("is-hidden");

    const pickupZone  = locationZones[val("pickup")];
    const dropoffZone = locationZones[val("dropoff")];
    const routeData   = getRouteData(pickupZone, dropoffZone);

    options.forEach(code => {
        const v     = vehicles[code];
        const price = routeData?.prices?.[code];
        box.insertAdjacentHTML("beforeend",
            `<button type="button" class="vehicle-card ${selectedVehicle === code ? "active" : ""}" data-vehicle="${code}">
                <span class="vehicle-badge">${v.badge}</span>
                <h4>${v.icon} ${v.name}</h4>
                <p>${v.capacity}<br>${v.desc}</p>
                <strong class="vehicle-price">${price ? money(price) : "Select a route"}</strong>
            </button>`
        );
    });

    box.querySelectorAll(".vehicle-card").forEach(card => card.addEventListener("click", () => {
        selectedVehicle = card.dataset.vehicle;
        calculateTransferTotal();
    }));
}

// ── CALCULATE & UPDATE UI ─────────────────────────────────────────────────────
function calculateTransferTotal() {
    renderVehicles();

    const pickupVal   = val("pickup");
    const dropoffVal  = val("dropoff");
    const pickupZone  = locationZones[pickupVal];
    const dropoffZone = locationZones[dropoffVal];
    const routeData   = getRouteData(pickupZone, dropoffZone);
    const routeExists = !!(routeData && selectedVehicle && routeData.prices?.[selectedVehicle]);
    const vehiclePrice = routeExists ? routeData.prices[selectedVehicle] : 0;
    const total       = extrasTotal() + vehiclePrice;

    // Summary route / duration / status
    if ($("summaryRoute"))    $("summaryRoute").textContent    = (pickupVal && dropoffVal) ? `${pickupVal} → ${dropoffVal}` : "Select your route";
    if ($("summaryDuration")) $("summaryDuration").textContent = routeData?.duration ?? "—";
    if ($("routeStatus"))     $("routeStatus").textContent     = routeExists ? "Estimated Price" : "Select your route";

    // Pax / vehicle / bags
    if ($("summaryPax"))      $("summaryPax").textContent     = pax();
    if ($("summaryVehicle"))  $("summaryVehicle").textContent = selectedVehicle && vehicles[selectedVehicle] ? vehicles[selectedVehicle].name : "Select vehicle";
    if ($("summaryBags"))     $("summaryBags").textContent    = `${$("carryOnBags")?.value ?? 0} carry-on / ${$("checkedBags")?.value ?? 0} checked`;

    // Price display — never show $0
    const priceDisplay = routeExists
        ? money(total)
        : (pickupVal && dropoffVal ? "Request Quote" : "—");
    if ($("summaryTotal")) $("summaryTotal").textContent = priceDisplay;
    if ($("totalPrice"))   $("totalPrice").textContent   = priceDisplay;

    // Availability badge
    const badge = $("availabilityBadge");
    if (badge) {
        if (routeExists) {
            badge.textContent = "Available";
            badge.className   = "availability available";
        } else {
            badge.textContent = pickupVal && dropoffVal ? "Custom Quote" : "Pending";
            badge.className   = "availability pending";
        }
    }

    // Pre-build WhatsApp message for the confirm modal
    const msg = buildTransferMessage(total, routeExists);
    const waBtn = $("whatsappBtn");
    if (waBtn) waBtn.dataset.waMsg = msg;
}

// ── WHATSAPP MESSAGE ──────────────────────────────────────────────────────────
function buildTransferMessage(total, routeExists) {
    const adults   = $("adults")?.value   || "0";
    const children = $("children")?.value || "0";
    const paxLine  = Number(children) > 0 ? `${adults} Adults, ${children} Children` : `${adults} Adults`;
    const vehicle  = selectedVehicle && vehicles[selectedVehicle] ? vehicles[selectedVehicle].name : "To be confirmed";
    const dateStr  = formatDate(val("travelDate"));
    const airline  = val("airline");
    const flight   = val("flightNumber");
    const arrival  = val("arrivalTime");
    const notes    = val("notes");
    const extras   = getExtrasList();
    const price    = routeExists ? money(total) : "Request Quote";

    let msg = `Hello Wild Papagayo Team! 🌿\n\nI'd like to request a private transfer.\n\n`;
    msg += `📍 Pickup:      ${val("pickup")  || "—"}\n`;
    msg += `📍 Drop-off:    ${val("dropoff") || "—"}\n`;
    if (dateStr)  msg += `📅 Date:        ${dateStr}\n`;
    if (airline)  msg += `✈️  Airline:     ${airline}\n`;
    if (flight)   msg += `🔢 Flight:      ${flight}\n`;
    if (arrival)  msg += `🕐 Arrival:     ${arrival}\n`;
    msg += `\n👥 Passengers: ${paxLine}\n`;
    msg += `🚙 Vehicle:     ${vehicle}\n`;
    msg += `💰 Estimated:   ${price}\n`;
    if (extras)   msg += `\n🛒 Extras:\n${extras}\n`;
    if (notes)    msg += `\n📝 Notes: ${notes}\n`;
    msg += `\nQuote Ref: ${QUOTE_NUM}\nThank you! 🙏`;
    return msg;
}

// ── CONFIRMATION MODAL ────────────────────────────────────────────────────────
function showConfirmModal() {
    const pickupZone  = locationZones[val("pickup")];
    const dropoffZone = locationZones[val("dropoff")];
    const routeData   = getRouteData(pickupZone, dropoffZone);
    const routeExists = !!(routeData && selectedVehicle && routeData.prices?.[selectedVehicle]);
    const vehiclePrice = routeExists ? routeData.prices[selectedVehicle] : 0;
    const total       = extrasTotal() + vehiclePrice;
    const msg         = buildTransferMessage(total, routeExists);
    const waUrl       = `https://wa.me/50688566325?text=${encodeURIComponent(msg)}`;

    const extras      = getExtrasList();
    const vehicle     = selectedVehicle && vehicles[selectedVehicle] ? vehicles[selectedVehicle].name : "To be confirmed";
    const price       = routeExists ? money(total) : "Request Quote";
    const adults      = $("adults")?.value   || "0";
    const children    = $("children")?.value || "0";
    const paxLine     = Number(children) > 0 ? `${adults} Adults, ${children} Children` : `${adults} Adults`;

    let modal = $("wpConfirmModal");
    if (!modal) {
        modal = document.createElement("div");
        modal.id = "wpConfirmModal";
        modal.style.cssText = "display:none;position:fixed;inset:0;z-index:99999;background:rgba(6,36,72,.78);align-items:center;justify-content:center;padding:20px;backdrop-filter:blur(4px);";
        modal.innerHTML = `
            <div style="background:#fff;border-radius:16px;max-width:460px;width:100%;padding:32px;box-shadow:0 30px 90px rgba(0,0,0,.3);max-height:92vh;overflow-y:auto;">
                <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">
                    <h3 style="font-family:'Playfair Display',Georgia,serif;font-size:1.4rem;color:#062448;margin:0;">Review Your Reservation</h3>
                    <button onclick="closeConfirmModal()" aria-label="Close" style="background:none;border:none;font-size:1.4rem;color:#9a9a9a;cursor:pointer;padding:4px;">✕</button>
                </div>
                <p style="color:#667085;font-size:.88rem;margin:0 0 22px;">Please review before sending to WhatsApp.</p>
                <div id="cmRows" style="display:flex;flex-direction:column;gap:0;margin-bottom:22px;border:1px solid #e4dfd4;border-radius:10px;overflow:hidden;"></div>
                <a id="cmConfirmBtn" href="#" target="_blank" rel="noopener"
                   style="display:flex;align-items:center;justify-content:center;gap:10px;width:100%;padding:14px;background:#25d366;color:#fff;font-weight:800;font-size:.95rem;border-radius:10px;text-decoration:none;margin-bottom:10px;box-sizing:border-box;">
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg>
                    Confirm on WhatsApp
                </a>
                <button onclick="closeConfirmModal()" style="width:100%;padding:11px;background:transparent;border:1.5px solid #e4dfd4;border-radius:10px;color:#667085;font-size:.88rem;cursor:pointer;font-weight:600;box-sizing:border-box;">← Edit Details</button>
            </div>
        `;
        modal.addEventListener("click", e => { if (e.target === modal) closeConfirmModal(); });
        document.body.appendChild(modal);
    }

    // Build rows
    const rows = [
        { label: "Pickup",     value: val("pickup")  || "—" },
        { label: "Drop-off",   value: val("dropoff") || "—" },
        { label: "Date",       value: formatDate(val("travelDate")) || "—" },
        { label: "Vehicle",    value: vehicle },
        { label: "Passengers", value: paxLine },
        { label: "Extras",     value: extras || "None", pre: true },
        { label: "Total",      value: price, highlight: true },
    ];

    const container = $("cmRows");
    container.innerHTML = rows.map((r, i) => `
        <div style="display:flex;justify-content:space-between;align-items:${r.pre ? "flex-start" : "center"};padding:12px 16px;${i < rows.length - 1 ? "border-bottom:1px solid #e4dfd4;" : ""}background:${r.highlight ? "#FFF9F2" : "#fff"};">
            <span style="color:#667085;font-size:.86rem;flex-shrink:0;">${r.label}</span>
            <b style="color:${r.highlight ? "#C9A24B" : "#062448"};font-size:${r.highlight ? "1.05rem" : ".88rem"};text-align:right;${r.pre ? "white-space:pre-line;" : ""}max-width:62%;">${r.value}</b>
        </div>
    `).join("");

    const confirmBtn = $("cmConfirmBtn");
    if (confirmBtn) confirmBtn.href = waUrl;

    modal.style.display = "flex";
    document.body.style.overflow = "hidden";
}

function closeConfirmModal() {
    const modal = $("wpConfirmModal");
    if (modal) modal.style.display = "none";
    document.body.style.overflow = "";
}

// ── AUTOCOMPLETE ──────────────────────────────────────────────────────────────
function initPremiumSearch(inputId, listId, locationsArray) {
    const inputField  = $(inputId);
    const resultsList = $(listId);
    if (!inputField || !resultsList) return;

    inputField.placeholder = "Search airport, hotel or destination...";

    inputField.addEventListener("input", function () {
        const phrase = this.value.toLowerCase().trim();
        resultsList.innerHTML = "";

        if (phrase.length < 3) {
            resultsList.style.display = "none";
            return;
        }

        const matches = locationsArray.filter(p => p.toLowerCase().includes(phrase));

        if (matches.length === 0) {
            resultsList.innerHTML = `<li style="color:#9a9a9a;cursor:default;font-style:italic;pointer-events:none;">No locations found.</li>`;
            resultsList.style.display = "block";
            return;
        }

        matches.forEach(placeName => {
            const li = document.createElement("li");
            li.innerHTML = `<span>📍</span> ${placeName}`;
            li.addEventListener("click", () => {
                inputField.value = placeName;
                resultsList.style.display = "none";
                calculateTransferTotal();
            });
            resultsList.appendChild(li);
        });
        resultsList.style.display = "block";
    });

    document.addEventListener("click", e => {
        if (!inputField.contains(e.target) && !resultsList.contains(e.target)) {
            resultsList.style.display = "none";
        }
    });
}

// ── INIT ──────────────────────────────────────────────────────────────────────
const inputsToWatch = ["pickup","dropoff","adults","children","beerQty","softDrinkQty","juiceQty","groceryStopQty","chipsQty","cookiesQty","nutsQty","carryOnBags","checkedBags"];

window.addEventListener("DOMContentLoaded", () => {
    initQuoteNumber();
    initPremiumSearch("pickup",  "pickup-list",  pickupOptions);
    initPremiumSearch("dropoff", "dropoff-list", dropoffOptions);

    inputsToWatch.forEach(id => {
        const el = $(id);
        if (!el) return;
        el.addEventListener("input",  calculateTransferTotal);
        el.addEventListener("change", calculateTransferTotal);
    });

    // Email submission via formsubmit.co
    const form    = $("transferForm");
    const submitBtn = $("transferSubmitBtn");
    const msgBox  = $("transferFormMsg");
    if (form && submitBtn) {
        form.addEventListener("submit", async function(e) {
            e.preventDefault();
            const orig = submitBtn.textContent;
            submitBtn.textContent = "Sending…";
            submitBtn.disabled = true;

            const pickupVal  = val("pickup");
            const dropoffVal = val("dropoff");
            const adults     = $("adults")?.value   || "0";
            const children   = $("children")?.value || "0";
            const extras     = getExtrasList();
            const prefContact = document.querySelector('input[name="Preferred Contact"]:checked')?.value || "Either works";

            const body = JSON.stringify({
                "_subject":          "New Transport Reservation — Wild Papagayo",
                "_template":         "table",
                "_captcha":          "false",
                "Quote Ref":         QUOTE_NUM,
                "First Name":        val("firstName"),
                "Last Name":         val("lastName"),
                "Phone":             val("phone"),
                "Email":             val("email"),
                "Country":           val("country"),
                "Preferred Contact": prefContact,
                "Pickup":            pickupVal  || "—",
                "Drop-off":          dropoffVal || "—",
                "Travel Date":       formatDate(val("travelDate")) || val("travelDate"),
                "Adults":            adults,
                "Children":          children,
                "Airline":           val("airline")      || "—",
                "Flight Number":     val("flightNumber") || "—",
                "Arrival Time":      val("arrivalTime")  || "—",
                "Carry-on Bags":     $("carryOnBags")?.value  || "0",
                "Checked Bags":      $("checkedBags")?.value  || "0",
                "Extras":            extras || "None",
                "Estimated Total":   $("totalPrice")?.textContent || "—",
                "Notes":             val("notes") || "—"
            });

            try {
                const res    = await fetch("https://formsubmit.co/ajax/reservas@wildpapagayo.com", {
                    method:  "POST",
                    headers: { "Content-Type": "application/json", "Accept": "application/json" },
                    body
                });
                const result = await res.json();
                if (!result.success) throw new Error("failed");

                if (typeof trackEvent === "function") {
                    trackEvent("generate_lead", { lead_type: "transport", page_type: "transport" });
                }

                const waText = encodeURIComponent(
                    "Hello Wild Papagayo! I just submitted a transport reservation request.\n\n" +
                    "Quote: " + QUOTE_NUM + "\n" +
                    "Route: " + (pickupVal || "—") + " → " + (dropoffVal || "—") + "\n" +
                    "Passengers: " + adults + " adults" + (Number(children) > 0 ? ", " + children + " children" : "")
                );

                form.innerHTML =
                    '<div style="text-align:center;padding:40px 20px;">' +
                    '<div style="width:56px;height:56px;border-radius:50%;background:#C9A24B;display:flex;align-items:center;justify-content:center;margin:0 auto 18px;">' +
                    '<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>' +
                    '</div>' +
                    '<h3 style="font-family:\'Playfair Display\',serif;color:#062448;font-size:1.45rem;margin:0 0 10px;">Request Received!</h3>' +
                    '<p style="color:#667085;margin:0 0 6px;line-height:1.7;">We\'ll review your route and confirm availability. Check your email for our reply.</p>' +
                    '<p style="color:#8a9aac;font-size:.85rem;margin:0 0 28px;">Quote reference: <strong style="color:#062448;">' + QUOTE_NUM + '</strong></p>' +
                    '<a href="https://wa.me/50688566325?text=' + waText + '" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:8px;padding:12px 22px;border-radius:6px;background:#25D366;color:#fff;text-decoration:none;font-weight:600;font-size:.9rem;">' +
                    'Also confirm on WhatsApp</a>' +
                    '</div>';
            } catch (_) {
                submitBtn.textContent = orig;
                submitBtn.disabled = false;
                if (msgBox) {
                    msgBox.innerHTML =
                        '<div style="margin-top:14px;padding:14px 16px;border-radius:8px;background:#fff3cd;border:1px solid #ffc107;color:#664d03;font-size:.88rem;">' +
                        '⚠️ Email submission failed. <a href="https://wa.me/50688566325" target="_blank" rel="noopener" style="color:#062448;font-weight:600;">Send via WhatsApp instead →</a>' +
                        '</div>';
                }
            }
        });
    }

    calculateTransferTotal();
});
