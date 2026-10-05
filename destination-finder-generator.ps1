# ============================================================
# Wild Papagayo - Destination Finder (Experience Match) v1.0
# Compiles each destination's Claude-assisted Travel Score into a
# static, self-contained match quiz at /destination-finder.html.
# The visitor picks what matters most to their trip; match % is
# computed client-side directly from the real experience_scores
# already on each destination -- no server, no hand-written rules.
# ============================================================
$ErrorActionPreference = "Stop"

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
$root = $PSScriptRoot
$destinationsDir = Join-Path $root "knowledge\destinations"
$outPath = Join-Path $root "destination-finder.html"

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }

$categories = @('adventure', 'families', 'private', 'nightlife', 'restaurants', 'beach', 'wildlife', 'relaxation')

$destinations = Get-ChildItem $destinationsDir -Filter '*.json' -File | ForEach-Object {
    $d = Read-Utf8Json $_.FullName
    # Explicit publication gate (not an accidental side effect of missing scores).
    if ([string]$d.status -ne 'published') { return }
    if (-not $d.experience_scores) { return }
    $scores = [ordered]@{}
    foreach ($cat in $categories) {
        $prop = $d.experience_scores.PSObject.Properties[$cat]
        $scores[$cat] = if ($prop) { [int]$prop.Value.score } else { 3 }
    }
    $difficulty = ""
    $diffProp = $d.experience_scores.PSObject.Properties['difficulty']
    if ($diffProp) { $difficulty = [string]$diffProp.Value.level }
    [ordered]@{
        id = [string]$d.id
        name = [string]$d.name
        image = [string]$d.hero_image
        description = [string]$d.hero_description
        difficulty = $difficulty
        scores = $scores
        url = "destinations/$($_.BaseName)"
    }
}
$destinations = @($destinations | Where-Object { $_ })
$destinationsJson = ($destinations | ConvertTo-Json -Depth 10 -Compress)

$html = @'
<!DOCTYPE html>
<html lang="en-CR">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<link rel="icon" type="image/svg+xml" href="images/favicon-wildpapagayo.svg">
<title>Find Your Perfect Costa Rica Destination | Wild Papagayo</title>
<meta name="description" content="Tell us what matters most to your trip and see which Guanacaste and Arenal destination matches best, scored from our real destination Travel Scores.">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://wildpapagayo.com/destination-finder">
<link rel="stylesheet" href="style.min.css">
<style>
.finder-wrap{width:min(880px,92%);margin:-40px auto 70px;background:#fff;border-radius:8px;box-shadow:0 20px 50px rgba(6,36,72,.14);padding:40px;position:relative;z-index:2}
.finder-wrap h2{font-family:Georgia,serif;color:#062448;font-size:1.4rem;margin:0 0 8px}
.finder-wrap>p{color:#5a5a5a;margin:0 0 22px;font-size:.92rem}
.finder-options{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:28px}
.finder-opt{border:1.5px solid #e4dfd4;border-radius:6px;padding:16px 10px;background:#fff;cursor:pointer;text-align:center;font-size:.85rem;color:#062448;font-weight:700;transition:border-color .15s,background .15s}
.finder-opt:hover{border-color:#C9A24B}
.finder-opt.selected{border-color:#062448;background:#062448;color:#fff}
.finder-cta-row{text-align:center}
.finder-cta-row button{background:#C9A24B;color:#062448;border:none;padding:14px 34px;border-radius:30px;font-weight:800;cursor:pointer;font-size:.9rem}
.finder-cta-row button:disabled{opacity:.5;cursor:not-allowed}
.finder-results{margin-top:32px;display:none}
.finder-results.show{display:block}
.finder-match-card{display:flex;gap:18px;border:1px solid #e4dfd4;border-radius:6px;overflow:hidden;margin-bottom:16px;text-decoration:none;color:inherit;position:relative}
.finder-match-card img{width:180px;height:150px;object-fit:cover;flex-shrink:0}
.finder-match-body{padding:16px 18px;flex:1}
.finder-match-pct{position:absolute;top:12px;right:14px;background:#062448;color:#C9A24B;font-weight:800;font-size:.85rem;padding:4px 12px;border-radius:20px}
.finder-match-body h3{font-family:Georgia,serif;color:#062448;font-size:1.15rem;margin:0 0 6px}
.finder-match-body p{color:#5a5a5a;font-size:.85rem;line-height:1.5;margin:0 0 6px}
.finder-match-body small{color:#8a94a3;text-transform:uppercase;letter-spacing:.06em;font-size:.7rem;font-weight:800}
@media(max-width:640px){.finder-wrap{padding:26px 20px}.finder-options{grid-template-columns:1fr 1fr}.finder-match-card{flex-direction:column}.finder-match-card img{width:100%;height:160px}.finder-match-pct{top:8px;right:8px}}
</style>

<!-- Google tag (gtag.js) -- deferred until window 'load' so it never competes with LCP/FCP-critical resources -->
<script>
window.addEventListener('load', function() {
  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=G-9V2MY7J6RJ';
  document.head.appendChild(s);
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  window.gtag = gtag;
  gtag('js', new Date());
  gtag('config', 'G-9V2MY7J6RJ');
});
</script>
</head>
<body>
<header class="site-header">
    <nav class="nav container" aria-label="Main navigation">
        <a class="brand" href="/" aria-label="Wild Papagayo Home">
            <img src="images/logo-wildpapagayo-nav.webp" alt="Wild Papagayo Private Journeys Costa Rica" width="160" height="80" loading="eager" fetchpriority="high" decoding="async">
        </a>
        <button aria-label="Open menu" aria-expanded="false" aria-controls="main-navigation" class="hamburger">&#9776;</button>
        <div class="nav-links" id="main-navigation">
            <a href="/">Home</a>
            <a href="tours">All Experiences</a>
            <a href="paquete">Multi-Day Journeys</a>
            <div class="nav-dropdown">
                <button class="nav-dropdown-trigger" aria-expanded="false" aria-haspopup="true">Discover <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></button>
                <div class="nav-dropdown-menu">
                    <a href="destination-finder">Destinations</a>
                    <a href="hotels">Hotels</a>
                    <a href="private-tours/peninsula-papagayo">Tours from Papagayo</a>
                    <a href="months">When to Visit</a>
                    <a href="blog/liberia-airport-transfer-guide">Liberia Airport Guide</a>
                    <a href="waterfalls-near-papagayo-guide">Waterfalls Near Papagayo</a>
                    <a href="plan-by-traveler-type">Plan by Traveler Type</a>
                </div>
            </div>
            <a href="transport">Transport</a>
            <a href="guides">Expert Guides</a>
            <a href="about">Our Story</a>
            <a href="Blogs">Insider Guide</a>
            <a href="travel-insurance">Travel Insurance</a>
            <a href="contact">Connect</a>
        </div>
        <a class="btn btn-primary header-cta" href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%20want%20to%20plan%20my%20Costa%20Rica%20trip." target="_blank" rel="noopener noreferrer">Plan Your Trip</a>
    </nav>
</header>

<main>
<header class="plain-hero">
  <div class="container plain-hero-inner">
    <span class="kicker">Experience Match</span>
    <h1>Find Your Perfect Destination</h1>
    <p>Pick what matters most to your trip and we'll match you against our real destination Travel Scores -- not a generic list.</p>
  </div>
  <div class="plain-hero-photo">
    <img src="images/luxury-costa-rica-tours-hero.webp" alt="Find your perfect Costa Rica destination" width="1600" height="900" loading="eager" fetchpriority="high" decoding="async">
  </div>
</header>

<div class="finder-wrap">
  <h2>What matters most to your trip?</h2>
  <p>Choose up to 3.</p>
  <div class="finder-options" id="finder-categories">
    <button class="finder-opt" data-cat="adventure">Adventure</button>
    <button class="finder-opt" data-cat="families">Family-Friendly</button>
    <button class="finder-opt" data-cat="private">Private</button>
    <button class="finder-opt" data-cat="nightlife">Nightlife</button>
    <button class="finder-opt" data-cat="restaurants">Restaurants</button>
    <button class="finder-opt" data-cat="beach">Beach</button>
    <button class="finder-opt" data-cat="wildlife">Wildlife</button>
    <button class="finder-opt" data-cat="relaxation">Relaxation</button>
  </div>
  <div class="finder-cta-row"><button id="finder-see-matches" disabled>See My Matches</button></div>

  <div class="finder-results" id="finder-results">
    <h2 style="margin-top:32px">Your Best Matches</h2>
    <div id="finder-match-cards"></div>
  </div>
</div>
</main>

<footer class="footer">
    <div class="container footer-grid footer-grid-clean">

        <div class="footer-brand">
            <img src="images/logo-wildpapagayo-nav.webp" alt="Wild Papagayo Private Journeys Costa Rica" class="footer-logo" width="180" height="180">
            <p>Exceptional Costa Rica, exclusively curated for discerning travelers.</p>
            <div class="footer-social">
                <a href="https://www.instagram.com/wild.papagayo" target="_blank" rel="noopener noreferrer" aria-label="Instagram" class="footer-social-ig">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="20" rx="5" ry="5"/><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"/><line x1="17.5" y1="6.5" x2="17.51" y2="6.5"/></svg>
                </a>
                <a href="https://www.facebook.com/share/1JLByXiV4k/?mibextid=wwXIfr" target="_blank" rel="noopener noreferrer" aria-label="Facebook" class="footer-social-fb">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/></svg>
                </a>
                <a href="https://wa.me/50688566325" target="_blank" rel="noopener noreferrer" aria-label="WhatsApp" class="footer-social-wa">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg>
                </a>
            </div>
        </div>

        <div>
            <div class="footer-title">Explore</div>
            <a href="/">Home</a>
            <a href="tours">All Experiences</a>
            <a href="paquete">Multi-Day Journeys</a>
            <a href="transport">Transport</a>
            <a href="guides">Expert Guides</a>
            <a href="about">Our Story</a>
            <a href="Blogs">Insider Guide</a>
            <a href="travel-insurance">Travel Insurance</a>
            <div class="footer-title footer-title-spaced">Legal</div>
            <a href="Terminosycondiciones">Terms &amp; Conditions</a>
            <a href="politicasdecancelacion">Booking &amp; Cancellation Policy</a>
            <a href="politicasdeprivacidad">Privacy Policy</a>
        </div>

        <div>
            <div class="footer-title">Get in Touch</div>
            <div class="footer-contact">
                <p>Guanacaste, Costa Rica</p>
                <p><a href="tel:+50688566325">+506 8856-6325</a></p>
                <p><a href="mailto:info@wildpapagayo.com">info@wildpapagayo.com</a></p>
            </div>
            <p class="footer-ict">Costa Rica - ICT License #491</p>
        </div>

        <div>
            <div class="footer-title">Trip Planning Tips</div>
            <p>Real trip-planning tips, seasonal advice and new tours from our local team. No spam, unsubscribe anytime.</p>
            <div class="newsletter-form">
                <label for="newsletterEmail" class="sr-only">Email</label>
                <input id="newsletterEmail" name="newsletterEmail" type="email" placeholder="Your email address" required>
                <button class="btn-newsletter" type="button" id="btnNewsletterReal" onclick="enviarNewsletter()">Join</button>
            </div>
        </div>

    </div>

    <div class="container footer-bottom">
        &copy; <span id="year"></span> Wild Papagayo. All rights reserved.
    </div>
</footer>

<a href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%20want%20to%20plan%20a%20private%20Costa%20Rica%20experience."
   class="whatsapp-float" target="_blank" rel="noopener noreferrer" aria-label="Chat with us on WhatsApp">
    <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg>
</a>

<script>
const DESTINATIONS = __DESTINATIONS_JSON__;
const selected = new Set();

document.querySelectorAll('.finder-opt').forEach(btn => {
  btn.addEventListener('click', () => {
    const cat = btn.dataset.cat;
    if (selected.has(cat)) {
      selected.delete(cat);
      btn.classList.remove('selected');
    } else {
      if (selected.size >= 3) return;
      selected.add(cat);
      btn.classList.add('selected');
    }
    document.getElementById('finder-see-matches').disabled = selected.size === 0;
  });
});

function imgUrl(p){ return p || 'images/luxury-costa-rica-tours-hero.webp'; }

document.getElementById('finder-see-matches').addEventListener('click', () => {
  const cats = [...selected];
  const ranked = DESTINATIONS.map(d => {
    const avg = cats.reduce((sum, c) => sum + (d.scores[c] || 3), 0) / cats.length;
    const pct = Math.round((avg / 5) * 100);
    return { d, pct };
  }).sort((a, b) => b.pct - a.pct).slice(0, 4);

  document.getElementById('finder-match-cards').innerHTML = ranked.map(({d, pct}) => `
    <a class="finder-match-card" href="${d.url}">
      <span class="finder-match-pct">${pct}%</span>
      <img src="${imgUrl(d.image)}" alt="${d.name}" loading="lazy">
      <div class="finder-match-body">
        <small>${d.difficulty ? d.difficulty + ' difficulty' : ''}</small>
        <h3>${d.name}</h3>
        <p>${d.description}</p>
      </div>
    </a>
  `).join('');
  document.getElementById('finder-results').classList.add('show');
  document.getElementById('finder-results').scrollIntoView({behavior:'smooth', block:'start'});
  if (typeof trackEvent === 'function') {
    trackEvent('destination_finder_complete', { finder_type: 'destination', result_count: ranked.length, page_type: 'destination_finder' });
  }
});

document.getElementById('year').textContent = new Date().getFullYear();
</script>
<script src="script.js" defer></script><script src="assistant-widget.js" defer></script>
</body>
</html>
'@

$html = $html.Replace('__DESTINATIONS_JSON__', $destinationsJson)
Write-FileIfChanged -Path $outPath -Content $html
Write-Host "Generated destination-finder.html with $($destinations.Count) scored destinations embedded."
