const WHATSAPP = '50688566325';

document.addEventListener('DOMContentLoaded', () => {

    // ── HAMBURGER MENU ─────────────────────────────────────────────
    const hamburger = document.querySelector('.hamburger');
    const navLinks  = document.querySelector('.nav-links');
    if (hamburger && navLinks) {
        const toggleMenu = e => { e.preventDefault(); e.stopPropagation(); navLinks.classList.toggle('active'); };
        hamburger.addEventListener('touchstart', toggleMenu, { passive: false });
        hamburger.addEventListener('click', toggleMenu);

        // Close menu when a nav link is clicked (mobile)
        navLinks.querySelectorAll('a').forEach(a =>
            a.addEventListener('click', () => navLinks.classList.remove('active'))
        );

        // Close menu when clicking outside
        document.addEventListener('click', e => {
            if (!hamburger.contains(e.target) && !navLinks.contains(e.target))
                navLinks.classList.remove('active');
        });
    }

    // ── ACTIVE NAV LINK (current page highlight) ───────────────────
    const currentPage = location.pathname.split('/').pop() || 'index.html';
    document.querySelectorAll('.nav-links a').forEach(a => {
        if (a.getAttribute('href') === currentPage)
            a.setAttribute('aria-current', 'page');
    });

    // ── WHATSAPP DATA BUTTONS ──────────────────────────────────────
    document.querySelectorAll('[data-whatsapp]').forEach(btn => btn.addEventListener('click', e => {
        e.preventDefault();
        const msg = btn.dataset.message || 'Hello Tico Host! I want more information.';
        window.open(`https://wa.me/${WHATSAPP}?text=${encodeURIComponent(msg)}`, '_blank');
    }));

    // ── GLOBAL FORM → WHATSAPP (only forms without their own handler) ──
    document.querySelectorAll('form:not([id])').forEach(form => form.addEventListener('submit', e => {
        e.preventDefault();
        const data = [...new FormData(form).entries()].map(([k, v]) => `${k}: ${v}`).join('\n');
        window.open(`https://wa.me/${WHATSAPP}?text=${encodeURIComponent('Hello Tico Host! I want to request this service:\n' + data)}`, '_blank');
    }));

    // ── SCROLL REVEAL ──────────────────────────────────────────────
    const revealObs = new IntersectionObserver(entries => entries.forEach(en => {
        if (en.isIntersecting) {
            en.target.classList.add('visible');
            revealObs.unobserve(en.target); // stop watching after first reveal
        }
    }), { threshold: 0.12 });
    document.querySelectorAll('.reveal').forEach(el => revealObs.observe(el));

    // ── FOOTER YEAR ────────────────────────────────────────────────
    const yearEl = document.getElementById('year');
    if (yearEl) yearEl.textContent = new Date().getFullYear();

    // ── TOUR SEARCH & FILTER ───────────────────────────────────────
    const search = document.getElementById('tourSearch');
    const cat    = document.getElementById('categoryFilter');
    const dur    = document.getElementById('durationFilter');
    if (search || cat || dur) {
        function filterTours() {
            const q = (search?.value || '').toLowerCase();
            const c = cat?.value || 'all';
            const d = dur?.value || 'all';
            document.querySelectorAll('.tour-card').forEach(card => {
                const match = card.innerText.toLowerCase().includes(q)
                    && (c === 'all' || card.dataset.category === c)
                    && (d === 'all' || card.dataset.duration === d);
                card.style.display = match ? '' : 'none';
            });
        }
        [search, cat, dur].forEach(el => el && el.addEventListener('input', filterTours));
    }

    // ── IMAGE SLIDER ───────────────────────────────────────────────
    document.querySelectorAll('.slider').forEach(slider => {
        let i = 0;
        const slides = slider.querySelector('.slides');
        const total  = slider.querySelectorAll('.slide').length;
        slider.querySelector('.next')?.addEventListener('click', () => {
            i = (i + 1) % total;
            slides.style.transform = `translateX(-${i * 100}%)`;
        });
        slider.querySelector('.prev')?.addEventListener('click', () => {
            i = (i - 1 + total) % total;
            slides.style.transform = `translateX(-${i * 100}%)`;
        });
    });

    // ── PREMIUM GALLERY ────────────────────────────────────────────
    document.querySelectorAll('.premium-gallery-card').forEach(card => {
        const imgs    = [...card.querySelectorAll('.gallery-main img')];
        const thumbs  = [...card.querySelectorAll('.gallery-thumbs button')];
        const counter = card.querySelector('.gallery-counter');
        let index = 0;
        const show = n => {
            index = (n + imgs.length) % imgs.length;
            imgs.forEach((img, i) => img.classList.toggle('active', i === index));
            thumbs.forEach((btn, i) => btn.classList.toggle('active', i === index));
            if (counter) counter.textContent = `${index + 1} / ${imgs.length}`;
        };
        card.querySelector('.gallery-next')?.addEventListener('click', () => show(index + 1));
        card.querySelector('.gallery-prev')?.addEventListener('click', () => show(index - 1));
        thumbs.forEach((btn, i) => btn.addEventListener('click', () => show(i)));
        imgs.forEach((img, i) => img.addEventListener('click', () => { show(i); openLightbox(img.src, img.alt); }));
        show(0);
    });

    // ── ACCORDION ──────────────────────────────────────────────────
    document.querySelectorAll('.accordion-trigger').forEach(btn => {
        btn.setAttribute('aria-expanded', 'false');
        btn.addEventListener('click', () => {
            const item = btn.closest('.accordion-item');
            item?.classList.toggle('active');
            btn.setAttribute('aria-expanded', item?.classList.contains('active') ? 'true' : 'false');
        });
    });

    // ── COPY PAGE LINK ─────────────────────────────────────────────
    document.querySelectorAll('[data-copy-link]').forEach(btn => btn.addEventListener('click', e => {
        e.preventDefault();
        navigator.clipboard?.writeText(location.href);
        const original = btn.textContent;
        btn.textContent = '✓ Copied!';
        setTimeout(() => btn.textContent = original, 1500);
    }));

    // ── SMOOTH SCROLL FOR ANCHOR LINKS ─────────────────────────────
    document.querySelectorAll('a[href^="#"]').forEach(a => a.addEventListener('click', e => {
        const target = document.querySelector(a.getAttribute('href'));
        if (target) {
            e.preventDefault();
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }));

});

// ── LIGHTBOX (global scope — called from gallery clicks) ───────────
function openLightbox(src, alt) {
    let lb = document.querySelector('.lightbox');
    if (!lb) {
        lb = document.createElement('div');
        lb.className = 'lightbox';
        lb.innerHTML = '<button class="lightbox-close" aria-label="Close">×</button><img alt="">';
        document.body.appendChild(lb);

        // Close on backdrop or button click
        lb.addEventListener('click', e => {
            if (e.target === lb || e.target.classList.contains('lightbox-close'))
                lb.classList.remove('active');
        });

        // Close with Escape key
        document.addEventListener('keydown', e => {
            if (e.key === 'Escape') lb.classList.remove('active');
        });
    }
    lb.querySelector('img').src = src;
    lb.querySelector('img').alt = alt || 'Tour photo';
    lb.classList.add('active');
}

// ── HERO PARALLAX ──────────────────────────────────────────────────
(function () {
    const wrap = document.querySelector('.seo-hero-image');
    if (!wrap) return;
    window.addEventListener('scroll', () => {
        const y = window.pageYOffset;
        if (y < window.innerHeight * 1.5)
            wrap.style.transform = `translateY(${y * 0.22}px)`;
    }, { passive: true });
})();

// ── NEWSLETTER ─────────────────────────────────────────────────────
function enviarNewsletter() {
    const emailInput = document.getElementById('newsletterEmail');
    const submitBtn  = document.getElementById('btnNewsletterReal');
    if (!emailInput || !submitBtn) return;

    const emailValue = emailInput.value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailValue)) {
        alert('Please enter a valid email address.');
        return;
    }

    const originalText = submitBtn.innerText;
    submitBtn.innerText = 'Sending...';
    submitBtn.disabled  = true;

    const webhookURL = 'https://script.google.com/macros/s/AKfycbwfidEr26PXeBGFAFSUpXJa1EZILQcNC99l6TpZp8OX5feiNwBF8lIHlevvMxIP4aBMXw/exec';

    fetch(webhookURL + '?newsletterEmail=' + encodeURIComponent(emailValue), {
        method: 'POST',
        mode: 'no-cors'
    })
    .then(() => {
        submitBtn.innerText = '✓ Subscribed!';
        submitBtn.style.background = 'linear-gradient(135deg, #25d366, #1aab52)';
        emailInput.value = '';
        setTimeout(() => {
            submitBtn.innerText  = originalText;
            submitBtn.style.background = '';
            submitBtn.disabled   = false;
        }, 4000);
    })
    .catch(() => {
        submitBtn.innerText = 'Error. Try again.';
        submitBtn.disabled  = false;
    });
}
