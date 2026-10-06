// ── CONFIG ─────────────────────────────────────────────────────────────────
const CONFIG = {
    WHATSAPP: '50688566325',
    SCROLL_OFFSET: 80,          // nav height — used for anchor scroll offset
    DEBOUNCE_DELAY: 250,
    BACK_TO_TOP_THRESHOLD: 400,
    AUTOPLAY_INTERVAL: 4000,
};

// ── UTILITIES ───────────────────────────────────────────────────────────────
function debounce(fn, delay) {
    let timer;
    return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), delay); };
}

function showToast(msg, type = 'info') {
    const old = document.querySelector('.wp-toast');
    if (old) old.remove();
    const t = document.createElement('div');
    t.className = 'wp-toast';
    t.setAttribute('role', 'status');
    t.setAttribute('aria-live', 'polite');
    t.textContent = msg;
    Object.assign(t.style, {
        position: 'fixed', bottom: '24px', left: '50%',
        transform: 'translateX(-50%) translateY(20px)',
        background: type === 'error' ? '#c0392b' : '#062448',
        color: '#fff', padding: '12px 22px', borderRadius: '8px',
        fontSize: '.88rem', fontWeight: '600', zIndex: '9999',
        opacity: '0', transition: 'opacity .25s, transform .25s',
        pointerEvents: 'none', whiteSpace: 'nowrap',
        boxShadow: '0 4px 20px rgba(0,0,0,.25)',
    });
    document.body.appendChild(t);
    requestAnimationFrame(() => {
        t.style.opacity = '1';
        t.style.transform = 'translateX(-50%) translateY(0)';
    });
    setTimeout(() => {
        t.style.opacity = '0';
        t.style.transform = 'translateX(-50%) translateY(10px)';
        setTimeout(() => t.remove(), 300);
    }, 3200);
}

function trackEvent(name, params = {}) {
    if (typeof gtag === 'function') gtag('event', name, params);
}

// ── ATTRIBUTION CONTEXT ──────────────────────────────────────────────────────
// First-touch landing page / referrer / UTM + a non-identifying session id,
// captured once per browser session (sessionStorage, never across tabs/days)
// and merged into every CTA/estimator/Bubu event below so a lead can later be
// traced back to what first brought the visitor to the site, without ever
// storing full browsing history, message text, or anything PII. Fails open:
// any error here (storage blocked, private mode) falls back to an empty
// context object -- it must never break a CTA, form, or chat.
const WPAttribution = (function () {
    var KEY = 'wpaAttributionContext';
    function randomId() {
        return (crypto && crypto.randomUUID) ? crypto.randomUUID() : (
            'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
                var r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
            })
        );
    }
    function referrerHost() {
        if (!document.referrer) return '(direct)';
        try {
            var refHost = new URL(document.referrer).host;
            return refHost === location.host ? '(internal)' : refHost;
        } catch (e) { return '(direct)'; }
    }
    function capture() {
        var params = new URLSearchParams(location.search);
        return {
            landing_page: location.pathname,
            referrer_host: referrerHost(),
            utm_source: params.get('utm_source') || null,
            utm_medium: params.get('utm_medium') || null,
            utm_campaign: params.get('utm_campaign') || null,
            utm_content: params.get('utm_content') || null,
            utm_term: params.get('utm_term') || null,
            session_id: randomId(),
            first_touch_at: new Date().toISOString(),
        };
    }
    var cached = null;
    function getContext() {
        if (cached) return cached;
        try {
            var stored = sessionStorage.getItem(KEY);
            if (stored) { cached = JSON.parse(stored); return cached; }
            cached = capture();
            sessionStorage.setItem(KEY, JSON.stringify(cached));
        } catch (e) {
            cached = capture(); // storage unavailable -- still return a usable (just non-persisted) context
        }
        return cached;
    }
    function current() {
        var ctx = getContext() || {};
        return Object.assign({}, ctx, {
            page_path: location.pathname,
            tour_slug: (document.body && document.body.dataset && document.body.dataset.tourSlug) || null,
        });
    }
    return { getContext: current };
})();
window.WPAttribution = WPAttribution;

// Derives a coarse page_type from the URL path -- used to group analytics
// events without needing to hand-tag every template.
function getPageType() {
    const path = location.pathname.toLowerCase();
    if (path === '/' || path.endsWith('/index.html')) return 'home';
    if (path.includes('/blog/')) return 'blog';
    if (path.includes('/private-tours/')) return 'private_tours_landing';
    if (path.includes('/tours/')) return 'tour';
    if (path.includes('/hotels/')) return 'hotel';
    if (path.includes('/destinations/')) return 'destination';
    if (path.includes('/packages/')) return 'package';
    if (path.includes('/months/')) return 'month';
    if (path.includes('/categories/')) return 'category';
    if (path.includes('/profiles/')) return 'profile';
    if (path.includes('transport.html')) return 'transport';
    if (path.includes('bookingform.html')) return 'booking_form';
    if (path.includes('contact.html')) return 'contact';
    if (path.includes('guides.html')) return 'guides';
    if (path.includes('tour-finder.html')) return 'tour_finder';
    if (path.includes('destination-finder.html')) return 'destination_finder';
    if (path.includes('tours.html')) return 'tours_index';
    if (path.includes('hotels.html')) return 'hotels_index';
    return 'other';
}

// Best-effort label for where on the page a WhatsApp link lives, so 689
// untagged wa.me links across every template can still be grouped without
// hand-tagging each one individually.
function classifyCtaLocation(link) {
    if (link.closest('.whatsapp-float')) return 'floating_button';
    if (link.closest('.header-cta') || link.closest('.site-header')) return 'header';
    if (link.closest('.pkg-cta-band, .hp-cta, .reviews-section, .cta-band')) return 'cta_band';
    if (link.closest('.plain-hero, .hero, .hp-header-plain')) return 'hero';
    if (link.closest('article, .blog-article, .article-body')) return 'blog_final_cta';
    if (link.closest('.footer')) return 'footer';
    return 'content_body';
}

// ── NAVIGATION ──────────────────────────────────────────────────────────────
function initNavigation() {
    const hamburger = document.querySelector('.hamburger');
    const navLinks  = document.querySelector('.nav-links');
    const header    = document.querySelector('.site-header');

    if (hamburger && navLinks) {
        const toggle = e => {
            e.preventDefault();
            e.stopPropagation();
            const open = navLinks.classList.toggle('active');
            hamburger.setAttribute('aria-expanded', String(open));
        };
        hamburger.addEventListener('touchstart', toggle, { passive: false });
        hamburger.addEventListener('click', toggle);

        navLinks.querySelectorAll('a').forEach(a => a.addEventListener('click', () => {
            navLinks.classList.remove('active');
            hamburger.setAttribute('aria-expanded', 'false');
        }));

        document.addEventListener('click', e => {
            if (!hamburger.contains(e.target) && !navLinks.contains(e.target)) {
                navLinks.classList.remove('active');
                hamburger.setAttribute('aria-expanded', 'false');
            }
        });
    }

    // Discover dropdown — click-toggle (covers mobile/touch; desktop also gets CSS hover)
    document.querySelectorAll('.nav-dropdown').forEach(dropdown => {
        const trigger = dropdown.querySelector('.nav-dropdown-trigger');
        if (!trigger) return;
        trigger.addEventListener('click', e => {
            e.preventDefault();
            e.stopPropagation();
            const open = dropdown.classList.toggle('open');
            trigger.setAttribute('aria-expanded', String(open));
        });
        dropdown.querySelectorAll('.nav-dropdown-menu a').forEach(a => a.addEventListener('click', () => {
            dropdown.classList.remove('open');
            trigger.setAttribute('aria-expanded', 'false');
        }));
    });
    document.addEventListener('click', e => {
        document.querySelectorAll('.nav-dropdown.open').forEach(dropdown => {
            if (!dropdown.contains(e.target)) {
                dropdown.classList.remove('open');
                dropdown.querySelector('.nav-dropdown-trigger')?.setAttribute('aria-expanded', 'false');
            }
        });
    });

    // Active page link highlight
    const currentPage = location.pathname.split('/').pop() || 'index.html';
    document.querySelectorAll('.nav-links a').forEach(a => {
        if (a.getAttribute('href') === currentPage) a.setAttribute('aria-current', 'page');
    });

    // Scrolled navbar — adds .scrolled class for a more solid background feel
    if (header) {
        const onScroll = () => header.classList.toggle('scrolled', window.scrollY > 50);
        window.addEventListener('scroll', onScroll, { passive: true });
        onScroll();
    }
}

// ── WHATSAPP BUTTONS ────────────────────────────────────────────────────────
function initWhatsApp() {
    document.querySelectorAll('[data-whatsapp]').forEach(btn => btn.addEventListener('click', e => {
        e.preventDefault();
        const msg = btn.dataset.message || 'Hello Wild Papagayo! I want more information.';
        const ctaId = btn.dataset.intent || 'tour_inquiry';
        trackEvent('whatsapp_click', Object.assign({
            cta_id: ctaId,
            whatsapp_intent: ctaId,
            cta_location: classifyCtaLocation(btn),
            cta_label: btn.dataset.label || btn.getAttribute('title') || 'generic',
            page_type: getPageType(),
            content_name: (document.querySelector('h1')?.textContent || document.title || '').trim().slice(0, 100),
        }, WPAttribution.getContext()));
        window.open(`https://wa.me/${CONFIG.WHATSAPP}?text=${encodeURIComponent(msg)}`, '_blank');
    }));
}

// Single delegated listener covers every plain <a href="https://wa.me/...">
// link sitewide (nav CTA, hero, mid-page bands, blog CTAs, footer, hotel/tour
// pages, package pages) without needing a data-attribute on each one. Links
// inside [data-whatsapp] never have a real wa.me href (built at click time),
// so there's no double-count there. Links inside the Bubu chat panel are
// tracked separately by assistant-widget.js as assistant_whatsapp_click, so
// they're explicitly skipped here to avoid firing both events for one click.
// Never includes the link's href/text query string -- only safe, generic
// classification params, since that URL can carry a visitor's name/email
// once it's built from a submitted form.
function initGlobalWhatsAppTracking() {
    document.addEventListener('click', e => {
        const link = e.target.closest('a[href*="wa.me"]');
        if (!link) return;
        if (link.closest('.wpa-panel')) return;
        const ctaId = link.dataset.intent || 'general_inquiry';
        trackEvent('whatsapp_click', Object.assign({
            cta_id: ctaId,
            whatsapp_intent: ctaId,
            cta_location: classifyCtaLocation(link),
            cta_label: (link.textContent || link.getAttribute('aria-label') || '').trim().slice(0, 80) || 'icon_only',
            page_type: getPageType(),
            content_name: (document.querySelector('h1')?.textContent || document.title || '').trim().slice(0, 100),
        }, WPAttribution.getContext()));
    });
}

// ── FORMS → WHATSAPP ────────────────────────────────────────────────────────
function initForms() {
    document.querySelectorAll('form:not([id])').forEach(form => form.addEventListener('submit', e => {
        e.preventDefault();
        const data = [...new FormData(form).entries()].map(([k, v]) => `${k}: ${v}`).join('\n');
        trackEvent('form_whatsapp_submit', Object.assign({ cta_id: 'form_whatsapp_submit', page_type: getPageType() }, WPAttribution.getContext()));
        window.open(`https://wa.me/${CONFIG.WHATSAPP}?text=${encodeURIComponent('Hello Wild Papagayo! I want to request this service:\n' + data)}`, '_blank');
    }));
}

// ── SCROLL REVEAL ───────────────────────────────────────────────────────────
function initReveal() {
    if (!document.querySelector('.reveal')) return;
    const obs = new IntersectionObserver(entries => entries.forEach(en => {
        if (en.isIntersecting) { en.target.classList.add('visible'); obs.unobserve(en.target); }
    }), { threshold: 0.12, rootMargin: '0px 0px -80px 0px' });
    document.querySelectorAll('.reveal').forEach(el => obs.observe(el));
}

// ── TOUR FILTERS ────────────────────────────────────────────────────────────
function initFilters() {
    const search = document.getElementById('tourSearch');
    const cat    = document.getElementById('categoryFilter');
    const dur    = document.getElementById('durationFilter');
    if (!search && !cat && !dur) return;

    // "No results" empty state
    let noResults = document.querySelector('.no-tours-message');
    if (!noResults) {
        noResults = document.createElement('p');
        noResults.className = 'no-tours-message';
        noResults.textContent = 'No tours found for your search. Try a different filter.';
        Object.assign(noResults.style, {
            textAlign: 'center', color: '#667085', padding: '48px 0',
            display: 'none', gridColumn: '1 / -1', fontSize: '.95rem',
        });
        const grid = document.querySelector('.tour-grid, .grid');
        grid?.appendChild(noResults);
    }

    function filterTours() {
        const q = (search?.value || '').toLowerCase();
        const c = cat?.value  || 'all';
        const d = dur?.value  || 'all';
        const isFiltered = q.length > 0 || c !== 'all' || d !== 'all';
        let visible = 0;
        document.querySelectorAll('.tour-section-header').forEach(h => { h.style.display = isFiltered ? 'none' : ''; });
        document.querySelectorAll('.tour-card').forEach(card => {
            const match = card.innerText.toLowerCase().includes(q)
                && (c === 'all' || card.dataset.category === c)
                && (d === 'all' || card.dataset.duration === d);
            card.style.display = match ? '' : 'none';
            if (match) visible++;
        });
        noResults.style.display = visible === 0 && isFiltered ? 'block' : 'none';
    }

    const debouncedFilter = debounce(filterTours, CONFIG.DEBOUNCE_DELAY);
    [search, cat, dur].forEach(el => el?.addEventListener('input', debouncedFilter));

    // Apply URL params (from category cards on home page)
    const params = new URLSearchParams(window.location.search);
    const pCat = params.get('cat'), pQ = params.get('q');
    if (pCat && cat) cat.value = pCat;
    if (pQ && search) search.value = pQ;
    if (pCat || pQ) {
        filterTours();
        setTimeout(() => document.querySelector('.filters')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 250);
    }
}

// ── IMAGE SLIDER ────────────────────────────────────────────────────────────
function initSlider() {
    if (!document.querySelector('.slider')) return;
    document.querySelectorAll('.slider').forEach(slider => {
        let i = 0;
        const slides = slider.querySelector('.slides');
        const total  = slider.querySelectorAll('.slide').length;
        slider.querySelector('.next')?.addEventListener('click', () => { i = (i + 1) % total; slides.style.transform = `translateX(-${i * 100}%)`; });
        slider.querySelector('.prev')?.addEventListener('click', () => { i = (i - 1 + total) % total; slides.style.transform = `translateX(-${i * 100}%)`; });
    });
}

// ── PREMIUM GALLERY ─────────────────────────────────────────────────────────
function initGallery() {
    if (!document.querySelector('.premium-gallery-card')) return;
    document.querySelectorAll('.premium-gallery-card').forEach(card => {
        const imgs    = [...card.querySelectorAll('.gallery-main img')];
        const thumbs  = [...card.querySelectorAll('.gallery-thumbs button')];
        const counter = card.querySelector('.gallery-counter');
        let index = 0, autoTimer = null;

        const show = n => {
            index = (n + imgs.length) % imgs.length;
            imgs.forEach((img, i) => img.classList.toggle('active', i === index));
            thumbs.forEach((btn, i) => btn.classList.toggle('active', i === index));
            if (counter) counter.textContent = `${index + 1} / ${imgs.length}`;
        };

        // Optional autoplay: add data-autoplay="true" to .premium-gallery-card
        const startAuto = () => {
            if (card.dataset.autoplay !== 'true') return;
            autoTimer = setInterval(() => show(index + 1), CONFIG.AUTOPLAY_INTERVAL);
        };
        const stopAuto = () => clearInterval(autoTimer);

        card.querySelector('.gallery-next')?.addEventListener('click', () => { stopAuto(); show(index + 1); });
        card.querySelector('.gallery-prev')?.addEventListener('click', () => { stopAuto(); show(index - 1); });
        thumbs.forEach((btn, i) => btn.addEventListener('click', () => { stopAuto(); show(i); }));
        imgs.forEach((img, i) => img.addEventListener('click', () => { stopAuto(); show(i); openLightbox(card, i); }));

        card.addEventListener('mouseenter', stopAuto);
        card.addEventListener('mouseleave', startAuto);
        show(0);
        startAuto();
    });
}

// ── DESTINATION PHOTO GALLERY (click to open lightbox) ─────────────────────
function initDestinationGallery() {
    const gallery = document.querySelector('.destination-gallery');
    if (!gallery) return;
    const imgs = [...gallery.querySelectorAll('img')];
    imgs.forEach((img, i) => {
        img.style.cursor = 'zoom-in';
        img.addEventListener('click', () => openLightbox(gallery, i));
    });
}

// ── ACCORDION (close-others behavior) ──────────────────────────────────────
function initAccordion() {
    const triggers = [...document.querySelectorAll('.accordion-trigger')];
    if (!triggers.length) return;
    triggers.forEach(btn => {
        btn.setAttribute('aria-expanded', 'false');
        btn.addEventListener('click', () => {
            const item   = btn.closest('.accordion-item');
            const isOpen = item?.classList.contains('active');
            // Close all
            triggers.forEach(other => {
                other.closest('.accordion-item')?.classList.remove('active');
                other.setAttribute('aria-expanded', 'false');
            });
            // Re-open if it was closed
            if (!isOpen) {
                item?.classList.add('active');
                btn.setAttribute('aria-expanded', 'true');
            }
        });
    });
}

// ── COPY PAGE LINK ───────────────────────────────────────────────────────────
function initCopyLink() {
    document.querySelectorAll('[data-copy-link]').forEach(btn => btn.addEventListener('click', e => {
        e.preventDefault();
        navigator.clipboard?.writeText(location.href)
            .then(() => {
                const orig = btn.textContent;
                btn.textContent = '✓ Copied!';
                setTimeout(() => btn.textContent = orig, 1500);
            })
            .catch(() => showToast('Unable to copy link.', 'error'));
    }));
}

// ── SMOOTH SCROLL WITH NAV OFFSET ──────────────────────────────────────────
function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(a => a.addEventListener('click', e => {
        const target = document.querySelector(a.getAttribute('href'));
        if (!target) return;
        e.preventDefault();
        const top = target.getBoundingClientRect().top + window.scrollY - CONFIG.SCROLL_OFFSET;
        window.scrollTo({ top, behavior: 'smooth' });
    }));
}

// ── BACK TO TOP ─────────────────────────────────────────────────────────────
function initBackToTop() {
    const btn = document.createElement('button');
    btn.className = 'back-to-top';
    btn.setAttribute('aria-label', 'Back to top');
    btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg>';
    Object.assign(btn.style, {
        position: 'fixed', bottom: '90px', right: '22px',
        width: '40px', height: '40px', borderRadius: '50%',
        background: '#062448', color: '#fff', border: 'none',
        cursor: 'pointer', zIndex: '998',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        opacity: '0', pointerEvents: 'none',
        transition: 'opacity .25s, transform .25s',
        boxShadow: '0 2px 12px rgba(6,36,72,.3)',
    });
    document.body.appendChild(btn);

    window.addEventListener('scroll', () => {
        const show = window.scrollY > CONFIG.BACK_TO_TOP_THRESHOLD;
        btn.style.opacity     = show ? '1' : '0';
        btn.style.pointerEvents = show ? 'auto' : 'none';
        btn.style.transform   = show ? 'translateY(0)' : 'translateY(8px)';
    }, { passive: true });

    btn.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
}

// ── HERO PARALLAX (rAF-throttled) ───────────────────────────────────────────
function initParallax() {
    const wrap = document.querySelector('.seo-hero-image');
    if (!wrap) return;
    if (window.innerWidth <= 768 || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let ticking = false;
    window.addEventListener('scroll', () => {
        if (!ticking) {
            requestAnimationFrame(() => {
                const y = window.pageYOffset;
                if (y < window.innerHeight * 1.5) wrap.style.transform = `translateY(${y * 0.22}px)`;
                ticking = false;
            });
            ticking = true;
        }
    }, { passive: true });
}

// ── LIGHTBOX (with keyboard ← → and mobile swipe) ──────────────────────────
let _lbImages = [];
let _lbIndex  = 0;

function openLightbox(cardOrSrc, indexOrAlt) {
    if (typeof cardOrSrc === 'string') {
        // Legacy call: openLightbox(src, alt)
        _lbImages = [{ src: cardOrSrc, alt: indexOrAlt || 'Tour photo' }];
        _lbIndex  = 0;
    } else {
        // New call from initGallery: openLightbox(card, index). Falls back to
        // any direct <img> children for simple grids (e.g. destination gallery)
        // that aren't built from the tour page's .gallery-main structure.
        const imgs = cardOrSrc.querySelectorAll('.gallery-main img').length
            ? cardOrSrc.querySelectorAll('.gallery-main img')
            : cardOrSrc.querySelectorAll('img');
        _lbImages = [...imgs].map(img => ({ src: img.src, alt: img.alt || 'Photo' }));
        _lbIndex  = typeof indexOrAlt === 'number' ? indexOrAlt : 0;
    }

    let lb = document.querySelector('.lightbox');
    const triggerEl = document.activeElement;

    if (!lb) {
        lb = document.createElement('div');
        lb.className = 'lightbox';
        lb.setAttribute('role', 'dialog');
        lb.setAttribute('aria-modal', 'true');
        lb.setAttribute('aria-label', 'Photo viewer');
        lb.innerHTML = `
            <button class="lightbox-close" aria-label="Close photo viewer">&times;</button>
            <button class="lightbox-prev" aria-label="Previous photo" style="position:absolute;left:16px;top:50%;transform:translateY(-50%);background:rgba(0,0,0,.45);border:none;color:#fff;font-size:1.8rem;width:44px;height:44px;border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;">&#8592;</button>
            <img alt="">
            <button class="lightbox-next" aria-label="Next photo" style="position:absolute;right:16px;top:50%;transform:translateY(-50%);background:rgba(0,0,0,.45);border:none;color:#fff;font-size:1.8rem;width:44px;height:44px;border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;">&#8594;</button>
        `;
        document.body.appendChild(lb);

        const closeLb = () => { lb.classList.remove('active'); triggerEl?.focus?.(); };

        lb.addEventListener('click', e => {
            if (e.target === lb || e.target.classList.contains('lightbox-close')) closeLb();
        });

        lb.querySelector('.lightbox-prev').addEventListener('click', e => { e.stopPropagation(); _showLbImg(_lbIndex - 1); });
        lb.querySelector('.lightbox-next').addEventListener('click', e => { e.stopPropagation(); _showLbImg(_lbIndex + 1); });

        // Keyboard: ← → Esc Tab
        document.addEventListener('keydown', e => {
            if (!lb.classList.contains('active')) return;
            if (e.key === 'Escape')     { closeLb(); return; }
            if (e.key === 'ArrowLeft')  { _showLbImg(_lbIndex - 1); return; }
            if (e.key === 'ArrowRight') { _showLbImg(_lbIndex + 1); return; }
            if (e.key === 'Tab')        { e.preventDefault(); lb.querySelector('.lightbox-close').focus(); }
        });

        // Swipe support (mobile)
        let swipeX = 0;
        lb.addEventListener('touchstart', e => { swipeX = e.touches[0].clientX; }, { passive: true });
        lb.addEventListener('touchend', e => {
            const dx = e.changedTouches[0].clientX - swipeX;
            if (Math.abs(dx) > 50) _showLbImg(dx < 0 ? _lbIndex + 1 : _lbIndex - 1);
        });
    }

    _showLbImg(_lbIndex);
    lb.classList.add('active');
    requestAnimationFrame(() => lb.querySelector('.lightbox-close').focus());
}

function _showLbImg(n) {
    if (!_lbImages.length) return;
    _lbIndex = (n + _lbImages.length) % _lbImages.length;
    const lb  = document.querySelector('.lightbox');
    const img = lb?.querySelector('img');
    if (img) { img.src = _lbImages[_lbIndex].src; img.alt = _lbImages[_lbIndex].alt; }
    // Hide nav arrows when only one image
    const showNav = _lbImages.length > 1;
    if (lb?.querySelector('.lightbox-prev')) lb.querySelector('.lightbox-prev').style.display = showNav ? '' : 'none';
    if (lb?.querySelector('.lightbox-next')) lb.querySelector('.lightbox-next').style.display = showNav ? '' : 'none';
}

// ── NEWSLETTER ──────────────────────────────────────────────────────────────
function enviarNewsletter(emailId, btnId) {
    const emailInput = document.getElementById(emailId || 'newsletterEmail');
    const submitBtn  = document.getElementById(btnId || 'btnNewsletterReal');
    if (!emailInput || !submitBtn) return;

    const emailValue = emailInput.value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailValue)) {
        showToast('Please enter a valid email address.', 'error');
        emailInput.focus();
        return;
    }

    // Inject spinner keyframe once
    if (!document.getElementById('_wp_spin')) {
        const s = document.createElement('style');
        s.id = '_wp_spin';
        s.textContent = '@keyframes _wpSpin{to{transform:rotate(360deg)}}';
        document.head.appendChild(s);
    }

    const originalHTML = submitBtn.innerHTML;
    submitBtn.innerHTML = '<span style="display:inline-block;width:15px;height:15px;border:2px solid rgba(255,255,255,.35);border-top-color:#fff;border-radius:50%;animation:_wpSpin .7s linear infinite;vertical-align:middle;"></span>';
    submitBtn.disabled = true;

    const webhookURL = 'https://script.google.com/macros/s/AKfycbwfidEr26PXeBGFAFSUpXJa1EZILQcNC99l6TpZp8OX5feiNwBF8lIHlevvMxIP4aBMXw/exec';

    fetch(webhookURL + '?newsletterEmail=' + encodeURIComponent(emailValue), { method: 'POST', mode: 'no-cors' })
        .then(() => {
            submitBtn.innerHTML = '✓';
            submitBtn.style.background = 'linear-gradient(135deg,#25d366,#1aab52)';
            emailInput.value = '';
            showToast("You're subscribed! Watch your inbox for trip tips.");
            trackEvent('newsletter_signup');
            setTimeout(() => {
                submitBtn.innerHTML = originalHTML;
                submitBtn.style.background = '';
                submitBtn.disabled = false;
            }, 4000);
        })
        .catch(() => {
            submitBtn.innerHTML = originalHTML;
            submitBtn.disabled = false;
            showToast('Something went wrong. Please try again.', 'error');
        });
}

// ── SERVICE WORKER ──────────────────────────────────────────────────────────
if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js').catch(() => {});
    });
}

// ── INIT ────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initWhatsApp();
    initGlobalWhatsAppTracking();
    initForms();
    initReveal();
    initFilters();
    initSlider();
    initGallery();
    initDestinationGallery();
    initAccordion();
    initCopyLink();
    initSmoothScroll();
    initBackToTop();
    initParallax();

    // Footer year (also set inline as failsafe on some pages)
    const yearEl = document.getElementById('year');
    if (yearEl) yearEl.textContent = new Date().getFullYear();
});
