// Wild Papagayo -- Smart Quote Form estimator.
// Enhances the existing .premium-form (tour-generator.ps1 / templates/tour.html)
// in place -- there is no second form. If tour-pricing.json can't be loaded,
// or this tour/its pickup hotel isn't in it, the form silently stays exactly
// as server-rendered (free-text pickup field, static option list, no price
// block) so a visitor can always submit a manual request. Nothing here ever
// blocks submission.
(function () {
  'use strict';

  var OTHER_HOTEL_VALUE = '__other__';

  function trackEvent(name, params) {
    if (typeof gtag !== 'function') return;
    var attributionCtx = (window.WPAttribution && window.WPAttribution.getContext()) || {};
    gtag('event', name, Object.assign({}, params || {}, attributionCtx));
  }

  function fmtMoney(n) {
    return '$' + Math.round(n).toLocaleString('en-US');
  }

  document.addEventListener('DOMContentLoaded', function () {
    var form = document.querySelector('.premium-form');
    if (!form) return;
    var tourSlug = form.dataset.tourSlug;
    if (!tourSlug) return;

    var optionGroup = document.getElementById('tf-option-group');
    var optionSelect = document.getElementById('tf-option');
    var pickupInput = document.getElementById('tf-pickup');
    var pickupGroup = document.getElementById('est-pickup-group');
    var hotelSelect = document.getElementById('est-hotel-select');
    var hotelOtherInput = document.getElementById('est-hotel-other');
    var zoneField = document.getElementById('est-pickup-zone');
    var travelersInput = document.getElementById('tf-travelers');
    var resultBox = document.getElementById('est-result');
    var resultInner = document.getElementById('est-result-inner');
    var ppField = document.getElementById('est-pp');
    var totalField = document.getElementById('est-total');
    var shownField = document.getElementById('est-shown');
    var versionField = document.getElementById('est-version');
    var optionIdField = document.getElementById('est-option-id');

    // Global, non-PII state read by the submit handler for the
    // quote_form_submitted GA4 event -- never touches name/email/phone/message.
    window.WPEstimatorState = { tourSlug: tourSlug };

    fetch('../tour-pricing.json', { cache: 'no-cache' })
      .then(function (r) { if (!r.ok) throw new Error('tour-pricing.json ' + r.status); return r.json(); })
      .then(function (data) {
        var tourData = data.tours && data.tours[tourSlug];
        if (!tourData || !Array.isArray(tourData.options) || tourData.options.length === 0) return; // fallback: leave form as-is

        window.WPEstimatorState.pricingVersion = data.pricing_version;
        if (versionField) versionField.value = data.pricing_version || '';

        setUpOptions(tourData.options);
        setUpHotels(data.hotels || []);
        if (travelersInput) travelersInput.addEventListener('input', recalc);

        recalc(); // initial state (neutral placeholder until hotel/guests chosen)
      })
      .catch(function () {
        // tour-pricing.json missing/unreachable/malformed -- the form already
        // works exactly as generated; nothing further to do.
      });

    function setUpOptions(options) {
      if (!optionSelect) return;
      optionSelect.innerHTML = '';
      options.forEach(function (opt) {
        var el = document.createElement('option');
        // The submitted "Option" field stays the human-readable label (what
        // the ops team reads in the FormSubmit email); the stable id travels
        // separately in the "Option ID" hidden field, kept in sync below --
        // never overloaded onto the same attribute.
        el.value = opt.label;
        el.dataset.optionId = opt.id;
        el.textContent = opt.label;
        optionSelect.appendChild(el);
      });
      if (options.length <= 1) {
        if (optionGroup) optionGroup.style.display = 'none';
      } else {
        if (optionGroup) {
          var label = optionGroup.querySelector('label');
          if (label) label.textContent = 'Choose your experience';
        }
      }
      optionSelect.addEventListener('change', function () { syncOptionId(); recalc(); });
      window.__wpTourOptions = options;
      syncOptionId();
    }

    function syncOptionId() {
      if (!optionSelect || !optionIdField) return;
      var selected = optionSelect.options[optionSelect.selectedIndex];
      optionIdField.value = selected ? (selected.dataset.optionId || '') : '';
    }

    function setUpHotels(hotels) {
      if (!hotelSelect) return;
      hotelSelect.innerHTML = '';
      var placeholder = document.createElement('option');
      placeholder.value = '';
      placeholder.textContent = 'Select your hotel...';
      placeholder.disabled = true;
      placeholder.selected = true;
      hotelSelect.appendChild(placeholder);

      var otherEntry = null;
      hotels.forEach(function (h) {
        if (h.zone === 'especial') { otherEntry = h; return; } // rendered last, below
        var el = document.createElement('option');
        el.value = h.name;
        el.dataset.zone = h.zone;
        el.textContent = h.name;
        hotelSelect.appendChild(el);
      });
      var otherOpt = document.createElement('option');
      otherOpt.value = OTHER_HOTEL_VALUE;
      otherOpt.dataset.zone = otherEntry ? otherEntry.zone : 'especial';
      otherOpt.textContent = (otherEntry && otherEntry.name) || 'Other / My hotel is not listed';
      hotelSelect.appendChild(otherOpt);

      // Swap the free-text input for the select -- keep the original input in
      // the DOM (still the field FormData actually submits as "Pickup Place"),
      // just hidden and kept in sync, so nothing about the submission changes.
      pickupInput.type = 'hidden';
      pickupInput.classList.add('est-replaced');
      hotelSelect.classList.remove('est-js-only');
      hotelSelect.removeAttribute('aria-hidden');
      if (pickupGroup) {
        var label = pickupGroup.querySelector('label');
        if (label) label.setAttribute('for', 'est-hotel-select');
      }

      hotelSelect.addEventListener('change', function () {
        var selected = hotelSelect.options[hotelSelect.selectedIndex];
        var zone = selected ? selected.dataset.zone : '';
        if (hotelSelect.value === OTHER_HOTEL_VALUE) {
          hotelOtherInput.classList.remove('est-js-only');
          hotelOtherInput.removeAttribute('aria-hidden');
          hotelOtherInput.required = true;
          pickupInput.value = hotelOtherInput.value || '';
        } else {
          hotelOtherInput.classList.add('est-js-only');
          hotelOtherInput.required = false;
          pickupInput.value = hotelSelect.value;
        }
        zoneField.value = zone || '';
        recalc();
      });
      hotelOtherInput.addEventListener('input', function () {
        pickupInput.value = hotelOtherInput.value;
        recalc();
      });
    }

    function currentOption() {
      var options = window.__wpTourOptions || [];
      if (!optionSelect) return options[0] || null;
      var selected = optionSelect.options[optionSelect.selectedIndex];
      var id = selected ? selected.dataset.optionId : null;
      if (!id) return options[0] || null;
      var found = null;
      options.forEach(function (o) { if (o.id === id) found = o; });
      return found;
    }

    function ppForGuests(option, guests) {
      if (guests === 2) return option.pp_2;
      if (guests === 3) return option.pp_3;
      if (guests >= 4) return option.pp_4plus;
      return null; // 1 guest (or 0/invalid) isn't defined in the matrix
    }

    var startedFired = false;

    function recalc() {
      var option = currentOption();
      var guests = parseInt(travelersInput && travelersInput.value, 10);
      var zone = zoneField ? zoneField.value : '';

      if (!startedFired && (zone || (guests && guests !== 2))) {
        startedFired = true;
        trackEvent('tour_estimate_started', { tour: tourSlug });
      }

      if (!option || !zone || !guests || guests < 1) {
        renderPlaceholder();
        return;
      }

      // Known from this point on regardless of outcome -- so the submitted
      // form and any GA4 event (including a Custom Quote Required one)
      // always reflect what the visitor actually selected, not just the
      // subset of cases that resolved to a numeric estimate.
      window.WPEstimatorState.optionId = option.id;
      window.WPEstimatorState.zone = zone;
      window.WPEstimatorState.guests = guests;
      window.WPEstimatorState.estimatedPp = null;
      window.WPEstimatorState.estimatedTotal = null;

      // Evaluation order: estimator_status -> hotel/Other -> base rate ->
      // zone_adjustment_applies. Any status other than the two known,
      // explicit values is treated as Custom Quote Required -- "active" is
      // never assumed just because a status string is merely absent/unknown.
      if (option.estimator_status !== 'active' && option.estimator_status !== 'manual_quote') {
        renderCustomQuote();
        trackEvent('custom_quote_required', { tour: tourSlug, package: option.id, guests: guests, reason: 'unknown_status' });
        return;
      }

      if (option.estimator_status === 'manual_quote') {
        renderCustomQuote();
        trackEvent('custom_quote_required', { tour: tourSlug, package: option.id, guests: guests, reason: 'manual_quote' });
        return;
      }

      if (zone === 'especial') {
        renderCustomQuote();
        trackEvent('custom_quote_required', { tour: tourSlug, package: option.id, guests: guests, reason: 'other_hotel' });
        return;
      }

      var pp = ppForGuests(option, guests);
      if (pp === null || pp === undefined) {
        renderCustomQuote();
        trackEvent('custom_quote_required', { tour: tourSlug, package: option.id, guests: guests, reason: 'no_price' });
        return;
      }

      var estimatedPp, estimatedGroupTotal;
      if (option.zone_adjustment_applies === false) {
        // Zone adjustments are opt-in and explicitly do not apply to this
        // option -- the base per-guest-count rate IS the estimate for any
        // approved listed hotel. Zone A/B/C values are never consulted.
        estimatedPp = pp;
        estimatedGroupTotal = pp * guests;
      } else {
        // true, or null/unconfirmed (legacy per-zone-cell behavior): a
        // required-but-missing adjustment is Custom Quote Required, never $0.
        var adjustment = option.zone_adjustment ? option.zone_adjustment[zone] : null;
        if (adjustment === null || adjustment === undefined) {
          renderCustomQuote();
          trackEvent('custom_quote_required', { tour: tourSlug, package: option.id, guests: guests, reason: 'zone_unconfirmed' });
          return;
        }
        estimatedGroupTotal = (pp * guests) + adjustment;
        estimatedPp = estimatedGroupTotal / guests;
      }

      renderEstimate(estimatedPp, estimatedGroupTotal);

      window.WPEstimatorState.estimatedPp = Math.round(estimatedPp);
      window.WPEstimatorState.estimatedTotal = Math.round(estimatedGroupTotal);

      if (ppField) ppField.value = String(Math.round(estimatedPp));
      if (totalField) totalField.value = String(Math.round(estimatedGroupTotal));
      if (shownField) shownField.value = 'Website estimate shown: ' + fmtMoney(estimatedPp) + ' p.p. / ' + fmtMoney(estimatedGroupTotal) + ' group total';

      trackEvent('tour_estimate_generated', {
        tour: tourSlug, package: option.id, guests: guests,
        estimated_pp: Math.round(estimatedPp), estimated_total: Math.round(estimatedGroupTotal)
      });
    }

    function renderPlaceholder() {
      if (!resultBox || !resultInner) return;
      resultBox.classList.remove('est-has-price', 'est-custom-quote');
      resultInner.innerHTML = '<p class="est-placeholder">Select your pickup hotel and party size to see an estimated price.</p>';
      if (ppField) ppField.value = '';
      if (totalField) totalField.value = '';
      if (shownField) shownField.value = '';
    }

    function renderCustomQuote() {
      if (!resultBox || !resultInner) return;
      resultBox.classList.remove('est-has-price');
      resultBox.classList.add('est-custom-quote');
      resultInner.innerHTML =
        '<p class="est-title">Custom Quote Required</p>' +
        '<p class="est-custom-quote-note">Pricing for this experience requires confirmation based on availability and operating conditions.</p>' +
        '<p class="est-disclaimer">Final price will be confirmed by Wild Papagayo before booking.</p>';
      if (ppField) ppField.value = '';
      if (totalField) totalField.value = '';
      if (shownField) shownField.value = 'Custom Quote Required (shown on website)';
    }

    function renderEstimate(pp, total) {
      if (!resultBox || !resultInner) return;
      resultBox.classList.remove('est-custom-quote');
      resultBox.classList.add('est-has-price');
      resultInner.innerHTML =
        '<p class="est-title">Estimated Private Tour Price</p>' +
        '<p class="est-price-pp">' + fmtMoney(pp) + ' <small>per person</small></p>' +
        '<p class="est-price-total">Estimated group total: ' + fmtMoney(total) + '</p>' +
        '<p class="est-disclaimer">Estimated price. Final pricing may vary based on pickup location, availability, selected activities and operational conditions. Final price will be confirmed by Wild Papagayo before booking.</p>';
    }
  });
})();
