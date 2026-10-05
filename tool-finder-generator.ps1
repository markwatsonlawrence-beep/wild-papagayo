# ============================================================
# Wild Papagayo - Tour Finder Quiz Generator v1.0
# Compiles the real per-tour attributes (best_for, category,
# difficulty, activity_ids) already stored in knowledge/tours/*.json
# into a static, self-contained quiz page at /tour-finder.html.
# All scoring logic runs client-side against embedded JSON --
# no server round-trip, no hand-written recommendation rules.
# ============================================================
$ErrorActionPreference = "Stop"

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
$root = $PSScriptRoot
$toursDir = Join-Path $root "knowledge\tours"
$outPath = Join-Path $root "tour-finder.html"

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }

$tours = Get-ChildItem $toursDir -Filter '*.json' -File | ForEach-Object {
    $t = Read-Utf8Json $_.FullName
    [ordered]@{
        id = [string]$t.id
        name = [string]$t.name
        category = [string]$t.category
        difficulty = [string]$t.difficulty
        best_for = @($t.best_for)
        activity_ids = @($t.activity_ids)
        duration = [string]$t.duration_label
        image = [string]$t.hero_image
        description = [string]$t.short_description
        url = [string]$t.page_url
    }
}
$toursJson = ($tours | ConvertTo-Json -Depth 10 -Compress)

$html = @'
<!DOCTYPE html>
<html lang="en-CR">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<link rel="icon" type="image/svg+xml" href="images/favicon-wildpapagayo.svg">
<title>Find Your Perfect Costa Rica Tour | Wild Papagayo</title>
<meta name="description" content="Answer three quick questions and find the private Costa Rica tour that actually fits your group, pace and interests -- matched from our full tour catalog.">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://wildpapagayo.com/tour-finder">
<meta property="og:title" content="Find Your Perfect Costa Rica Tour | Wild Papagayo">
<meta property="og:description" content="Answer three quick questions and find the private Costa Rica tour that actually fits your group, pace and interests -- matched from our full tour catalog.">
<meta property="og:image" content="https://wildpapagayo.com/images/logo-wildpapagayo-nav.webp">
<meta property="og:type" content="website">
<meta property="og:url" content="https://wildpapagayo.com/tour-finder">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Find Your Perfect Costa Rica Tour | Wild Papagayo">
<meta name="twitter:description" content="Answer three quick questions and find the private Costa Rica tour that actually fits your group, pace and interests -- matched from our full tour catalog.">
<link rel="stylesheet" href="style.min.css">
<style>
.finder-wrap{width:min(880px,92%);margin:-40px auto 70px;background:#fff;border-radius:8px;box-shadow:0 20px 50px rgba(6,36,72,.14);padding:40px;position:relative;z-index:2}
.finder-progress{display:flex;gap:6px;margin-bottom:28px}
.finder-progress span{flex:1;height:4px;border-radius:2px;background:#e4dfd4}
.finder-progress span.done{background:#C9A24B}
.finder-step{display:none}
.finder-step.active{display:block}
.finder-step h2{font-family:Georgia,serif;color:#062448;font-size:1.5rem;margin:0 0 20px}
.finder-options{display:grid;grid-template-columns:1fr 1fr;gap:14px}
.finder-opt{border:1.5px solid #e4dfd4;border-radius:6px;padding:20px;background:#fff;cursor:pointer;text-align:left;font-size:.95rem;color:#062448;font-weight:700;transition:border-color .15s,background .15s}
.finder-opt:hover{border-color:#C9A24B}
.finder-opt.selected{border-color:#062448;background:#062448;color:#fff}
.finder-back{margin-top:22px;background:none;border:none;color:#8a94a3;font-weight:700;cursor:pointer;font-size:.85rem}
.finder-results h2{font-family:Georgia,serif;color:#062448;font-size:1.6rem;margin:0 0 6px}
.finder-results>p{color:#5a5a5a;margin:0 0 26px}
.finder-card{display:flex;gap:18px;border:1px solid #e4dfd4;border-radius:6px;overflow:hidden;margin-bottom:16px;text-decoration:none;color:inherit}
.finder-card img{width:200px;height:150px;object-fit:cover;flex-shrink:0}
.finder-card-body{padding:16px 18px}
.finder-card-body span{color:#C9A24B;font-size:10.5px;font-weight:800;letter-spacing:.12em;text-transform:uppercase}
.finder-card-body h3{font-family:Georgia,serif;color:#062448;font-size:1.2rem;margin:6px 0 8px}
.finder-card-body p{color:#5a5a5a;font-size:.88rem;line-height:1.55;margin:0 0 8px}
.finder-card-link{color:#0d7a5f;font-size:.82rem;font-weight:800}
.finder-restart{margin-top:10px;background:#062448;color:#fff;border:none;padding:12px 24px;border-radius:30px;font-weight:800;cursor:pointer}
@media(max-width:640px){.finder-wrap{padding:26px 20px}.finder-options{grid-template-columns:1fr}.finder-card{flex-direction:column}.finder-card img{width:100%;height:180px}}
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
    <span class="kicker">Tour Finder</span>
    <h1>Find Your Perfect Costa Rica Tour</h1>
    <p>Three quick questions, matched against our full private tour catalog -- no generic "Top 10" list.</p>
  </div>
  <div class="plain-hero-photo">
    <img src="images/luxury-costa-rica-tours-hero.webp" alt="Find your perfect Costa Rica tour" width="1600" height="900" loading="eager" fetchpriority="high" decoding="async">
  </div>
</header>

<div class="finder-wrap">
  <div class="finder-progress"><span id="prog-1"></span><span id="prog-2"></span><span id="prog-3"></span></div>

  <div class="finder-step active" id="step-1">
    <h2>Who's traveling?</h2>
    <div class="finder-options" data-q="who">
      <button class="finder-opt" data-val="Couples">A couple</button>
      <button class="finder-opt" data-val="Families">A family with kids</button>
      <button class="finder-opt" data-val="Friends">Friends or a group</button>
      <button class="finder-opt" data-val="First-time visitors">Solo / first time in Costa Rica</button>
    </div>
  </div>

  <div class="finder-step" id="step-2">
    <h2>What's your travel style?</h2>
    <div class="finder-options" data-q="style">
      <button class="finder-opt" data-val="Wellness & Nature">Relaxed & scenic</button>
      <button class="finder-opt" data-val="Wildlife">Wildlife & nature</button>
      <button class="finder-opt" data-val="Adventure">Adventure & adrenaline</button>
      <button class="finder-opt" data-val="Wildlife & Culture">Culture & local life</button>
    </div>
    <button class="finder-back" data-back="1">&larr; Back</button>
  </div>

  <div class="finder-step" id="step-3">
    <h2>How active do you want to be?</h2>
    <div class="finder-options" data-q="activity">
      <button class="finder-opt" data-val="Easy">Easy, take-it-slow</button>
      <button class="finder-opt" data-val="Easy to Moderate">A comfortable mix</button>
      <button class="finder-opt" data-val="Moderate">Bring on the adventure</button>
    </div>
    <button class="finder-back" data-back="2">&larr; Back</button>
  </div>

  <div class="finder-step" id="step-results">
    <div class="finder-results">
      <h2>Your Top Matches</h2>
      <p>Based on your answers, here's what fits best from our private tour catalog.</p>
      <div id="finder-cards"></div>
      <button class="finder-restart" id="finder-restart">Start Over</button>
    </div>
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
const TOURS = __TOURS_JSON__;
const answers = {};
let step = 1;

function imgUrl(p){ return p || 'images/luxury-costa-rica-tours-hero.webp'; }

document.querySelectorAll('.finder-opt').forEach(btn => {
  btn.addEventListener('click', () => {
    const group = btn.closest('.finder-options');
    const q = group.dataset.q;
    group.querySelectorAll('.finder-opt').forEach(b => b.classList.toggle('selected', b === btn));
    answers[q] = btn.dataset.val;
    setTimeout(() => { if (step < 3) goStep(step + 1); else showResults(); }, 200);
  });
});
document.querySelectorAll('[data-back]').forEach(btn => btn.addEventListener('click', () => goStep(Number(btn.dataset.back))));
document.getElementById('finder-restart').addEventListener('click', () => { Object.keys(answers).forEach(k => delete answers[k]); document.querySelectorAll('.finder-opt.selected').forEach(b => b.classList.remove('selected')); goStep(1); });

function goStep(n) {
  step = n;
  document.querySelectorAll('.finder-step').forEach(s => s.classList.remove('active'));
  document.getElementById('step-' + n).classList.add('active');
  for (let i = 1; i <= 3; i++) document.getElementById('prog-' + i).classList.toggle('done', i <= n);
}

function scoreTour(t) {
  let s = 0;
  if (answers.who && t.best_for.includes(answers.who)) s += 3;
  if (answers.style && t.category === answers.style) s += 3;
  else if (answers.style === 'Wildlife' && t.category.indexOf('Wildlife') !== -1) s += 3;
  if (answers.activity && t.difficulty === answers.activity) s += 2;
  else if (answers.activity && t.difficulty.indexOf(answers.activity) !== -1) s += 1;
  return s;
}

function showResults() {
  document.querySelectorAll('.finder-step').forEach(s => s.classList.remove('active'));
  document.getElementById('step-results').classList.add('active');
  for (let i = 1; i <= 3; i++) document.getElementById('prog-' + i).classList.add('done');
  const ranked = TOURS.map(t => ({ t, s: scoreTour(t) })).sort((a, b) => b.s - a.s).slice(0, 3);
  document.getElementById('finder-cards').innerHTML = ranked.map(({t}) => `
    <a class="finder-card" href="${t.url}">
      <img src="${imgUrl(t.image)}" alt="${t.name}" loading="lazy">
      <div class="finder-card-body">
        <span>${t.category} &middot; ${t.duration}</span>
        <h3>${t.name}</h3>
        <p>${t.description}</p>
        <span class="finder-card-link">View This Tour &rarr;</span>
      </div>
    </a>
  `).join('');
  if (typeof trackEvent === 'function') {
    trackEvent('tour_finder_complete', { finder_type: 'tour', result_count: ranked.length, page_type: 'tour_finder' });
  }
}

document.getElementById('year').textContent = new Date().getFullYear();
</script>
<script src="script.js" defer></script><script src="assistant-widget.js" defer></script>
</body>
</html>
'@

$html = $html.Replace('__TOURS_JSON__', $toursJson)
Write-FileIfChanged -Path $outPath -Content $html
Write-Host "Generated tour-finder.html with $($tours.Count) tours embedded."
