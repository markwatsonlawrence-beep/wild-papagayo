(function () {
  var ENDPOINT = '/assistant';
  var history = [];

  // A random, non-identifying id so Bubu can recall context across page
  // reloads within the same browser -- never an email, phone, or IP.
  // localStorage (not sessionStorage) so it survives closing the tab.
  function getConversationId() {
    try {
      var id = localStorage.getItem('wpaConversationId');
      if (id) return id;
      id = (crypto && crypto.randomUUID) ? crypto.randomUUID() : (
        'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
          var r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
          return v.toString(16);
        })
      );
      localStorage.setItem('wpaConversationId', id);
      return id;
    } catch (e) {
      return null; // localStorage unavailable (private mode etc.) -- Bubu just won't remember across reloads
    }
  }
  var conversationId = getConversationId();

  // Never pass question/answer text here -- it can contain names, phone
  // numbers or other personal details a visitor typed into the chat.
  function bubuTrack(name, params) {
    if (typeof gtag !== 'function') return;
    var attributionCtx = (window.WPAttribution && window.WPAttribution.getContext()) || {};
    gtag('event', name, Object.assign({}, params || {}, attributionCtx));
  }
  function bubuPageType() {
    var path = location.pathname.toLowerCase();
    if (path === '/' || path.indexOf('/index.html') !== -1) return 'home';
    if (path.indexOf('/blog/') !== -1) return 'blog';
    if (path.indexOf('/tours/') !== -1) return 'tour';
    if (path.indexOf('/hotels/') !== -1) return 'hotel';
    if (path.indexOf('/destinations/') !== -1) return 'destination';
    return 'other';
  }
  // Same non-PII context sent to GA4 (landing page, referrer host, UTMs,
  // session id, tour slug) -- also attached to the /assistant POST body so a
  // lead created server-side (upsertLead in functions/assistant.js) can be
  // traced back to it. Never includes message text or anything the visitor typed.
  function bubuAttributionPayload() {
    return (window.WPAttribution && window.WPAttribution.getContext()) || {};
  }

  var css = '.wpa-fab{position:fixed;bottom:98px;right:28px;width:58px;height:58px;border-radius:50%;background:#062448;color:#fff;border:none;box-shadow:0 8px 24px rgba(6,36,72,.3);cursor:pointer;z-index:9998;font-size:26px;display:flex;align-items:center;justify-content:center}' +
    '.wpa-fab:hover{background:#0a3768}' +
    '.wpa-panel{position:fixed;bottom:166px;right:24px;width:min(360px,92vw);height:min(520px,72vh);background:#fff;border-radius:12px;box-shadow:0 20px 60px rgba(6,36,72,.25);z-index:9999;display:none;flex-direction:column;overflow:hidden;font-family:Arial,Helvetica,sans-serif}' +
    '.wpa-panel.open{display:flex}' +
    '.wpa-head{background:#062448;color:#fff;padding:16px 18px;display:flex;justify-content:space-between;align-items:center;flex-shrink:0}' +
    '.wpa-head strong{font-size:.95rem}' +
    '.wpa-head small{display:block;color:#C9A24B;font-size:.7rem;font-weight:700;letter-spacing:.06em}' +
    '.wpa-close{background:none;border:none;color:#fff;font-size:20px;cursor:pointer;line-height:1}' +
    '.wpa-body{flex:1;overflow-y:auto;padding:16px;background:#F7F4EE}' +
    '.wpa-msg{margin-bottom:12px;max-width:88%;font-size:.87rem;line-height:1.5;padding:10px 13px;border-radius:10px}' +
    '.wpa-msg a{color:#0d7a5f;font-weight:700}' +
    '.wpa-msg.user{background:#062448;color:#fff;margin-left:auto;border-bottom-right-radius:2px}' +
    '.wpa-msg.bot{background:#fff;color:#062448;border:1px solid #e4dfd4;border-bottom-left-radius:2px}' +
    '.wpa-msg.typing{color:#8a94a3;font-style:italic}' +
    '.wpa-suggestions{display:flex;flex-wrap:wrap;gap:6px;padding:0 16px 12px}' +
    '.wpa-sugg{background:#fff;border:1px solid #e4dfd4;border-radius:20px;padding:6px 12px;font-size:.76rem;cursor:pointer;color:#062448}' +
    '.wpa-sugg:hover{border-color:#C9A24B}' +
    '.wpa-inputrow{display:flex;border-top:1px solid #e4dfd4;padding:10px;flex-shrink:0;padding-bottom:calc(10px + env(safe-area-inset-bottom))}' +
    '.wpa-inputrow input{flex:1;border:none;padding:10px 12px;font-size:16px;outline:none}' +
    '.wpa-inputrow button{background:#C9A24B;color:#062448;border:none;border-radius:6px;padding:0 16px;font-weight:800;cursor:pointer;margin-left:8px}' +
    '.wpa-lead input{display:block;width:100%;box-sizing:border-box;border:1px solid #e4dfd4;border-radius:6px;padding:8px 10px;font-size:.85rem;margin-bottom:6px;font-family:Arial,Helvetica,sans-serif}' +
    '.wpa-lead-actions{display:flex;gap:8px;margin-top:2px;align-items:center}' +
    '.wpa-lead-send{background:#C9A24B;color:#062448;border:none;border-radius:6px;padding:7px 14px;font-weight:800;cursor:pointer;font-size:.8rem}' +
    '.wpa-lead-send:disabled{opacity:.6;cursor:default}' +
    '.wpa-lead-skip{background:none;border:none;color:#8a94a3;cursor:pointer;font-size:.8rem;text-decoration:underline}' +
    '.wpa-lead-status{color:#b3261e;font-size:.78rem;margin:6px 0 0}' +
    '.wpa-tip{position:fixed;bottom:104px;right:96px;max-width:200px;background:#fff;color:#062448;font-size:.82rem;line-height:1.4;padding:11px 14px;border-radius:10px;box-shadow:0 10px 30px rgba(6,36,72,.22);z-index:9997;font-family:Arial,Helvetica,sans-serif;display:flex;align-items:flex-start;gap:8px;animation:wpaFadeIn .3s ease}' +
    '.wpa-tip:after{content:"";position:absolute;right:-6px;top:22px;width:12px;height:12px;background:#fff;transform:rotate(45deg);box-shadow:3px -3px 6px rgba(6,36,72,.04)}' +
    '.wpa-tip-close{background:none;border:none;color:#8a94a3;font-size:15px;cursor:pointer;line-height:1;padding:0;flex-shrink:0}' +
    '@keyframes wpaFadeIn{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:translateY(0)}}' +
    '@keyframes wpaSheetUp{from{transform:translateY(100%)}to{transform:translateY(0)}}' +
    '@media(max-width:600px){' +
      '.wpa-panel{top:0;left:0;right:0;bottom:0;width:100%;height:100dvh;max-height:100dvh;border-radius:0;animation:wpaSheetUp 280ms cubic-bezier(.22,1,.36,1)}' +
      '.wpa-head{padding-top:calc(16px + env(safe-area-inset-top))}' +
      '.wpa-fab{right:16px;bottom:78px}' +
      '.wpa-tip{right:16px;bottom:84px;max-width:calc(100vw - 32px)}' +
    '}' +
    '@media(max-width:600px) and (prefers-reduced-motion:reduce){.wpa-panel{animation:none}}';
  var styleEl = document.createElement('style');
  styleEl.textContent = css;
  document.head.appendChild(styleEl);

  var fab = document.createElement('button');
  fab.className = 'wpa-fab';
  fab.setAttribute('aria-label', 'Chat with Bubu, the Wild Papagayo Travel Assistant');
  fab.innerHTML = '&#128172;';

  var panel = document.createElement('div');
  panel.className = 'wpa-panel';
  panel.innerHTML =
    '<div class="wpa-head"><div><strong>Bubu</strong><small>Your Wild Papagayo Travel Assistant</small></div><button class="wpa-close" aria-label="Close chat">&times;</button></div>' +
    '<div class="wpa-body" id="wpa-body"></div>' +
    '<div class="wpa-suggestions" id="wpa-suggestions">' +
      '<span class="wpa-sugg" data-q="What tours do you recommend for couples?">Tours for couples</span>' +
      '<span class="wpa-sugg" data-q="Do I need a rental car in Guanacaste?">Rental car?</span>' +
      '<span class="wpa-sugg" data-q="What is the best time to visit Rio Celeste?">Best time for Rio Celeste</span>' +
    '</div>' +
    '<div class="wpa-inputrow"><input id="wpa-input" type="text" placeholder="Ask a question..." maxlength="500"><button id="wpa-send">Send</button></div>';

  document.addEventListener('DOMContentLoaded', function () {
    document.body.appendChild(fab);
    document.body.appendChild(panel);

    // A short-lived tooltip explaining what the button is -- shown once per
    // browser session (not every single page) so it doesn't nag repeat
    // visitors while still introducing the feature during the current visit.
    if (!sessionStorage.getItem('wpaTipSeen')) {
      var tipTimer = setTimeout(function () {
        var tip = document.createElement('div');
        tip.className = 'wpa-tip';
        tip.innerHTML = '<span>Hi, I\'m Bubu! Questions about hotels, tours or trip planning? Ask me anything.</span><button class="wpa-tip-close" aria-label="Dismiss">&times;</button>';
        document.body.appendChild(tip);
        sessionStorage.setItem('wpaTipSeen', '1');
        var hideTip = function () { if (tip.parentNode) tip.remove(); };
        var autoHide = setTimeout(hideTip, 7000);
        tip.querySelector('.wpa-tip-close').addEventListener('click', function () { clearTimeout(autoHide); hideTip(); });
        fab.addEventListener('click', function () { clearTimeout(autoHide); hideTip(); }, { once: true });
      }, 2000);
    }

    var body = panel.querySelector('#wpa-body');
    var input = panel.querySelector('#wpa-input');
    var sendBtn = panel.querySelector('#wpa-send');
    var suggestions = panel.querySelector('#wpa-suggestions');

    function addMessage(role, html) {
      var el = document.createElement('div');
      el.className = 'wpa-msg ' + (role === 'user' ? 'user' : 'bot');
      el.innerHTML = html;
      body.appendChild(el);
      body.scrollTop = body.scrollHeight;
      return el;
    }

    function linkify(text) {
      var escaped = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      escaped = escaped.replace(/(\/[a-zA-Z0-9\-_/]+\.html)/g, '<a href="$1">$1</a>');
      return escaped.replace(/\n/g, '<br>');
    }

    // Shown once per browser tab, after the first answer, so visitors who
    // find the chat useful have an easy way to ask for a follow-up. Skipping
    // is always one click away and nothing is required to keep chatting.
    function maybeShowLeadCapture() {
      if (sessionStorage.getItem('wpaLeadPromptShown')) return;
      sessionStorage.setItem('wpaLeadPromptShown', '1');

      var el = document.createElement('div');
      el.className = 'wpa-msg bot wpa-lead';
      el.innerHTML =
        '<p style="margin:0 0 8px;">Want us to follow up with more details? Leave your name and email (totally optional):</p>' +
        '<input type="text" class="wpa-lead-name" placeholder="Your name" maxlength="80">' +
        '<input type="email" class="wpa-lead-email" placeholder="Your email" maxlength="120">' +
        '<div class="wpa-lead-actions">' +
          '<button type="button" class="wpa-lead-send">Send</button>' +
          '<button type="button" class="wpa-lead-skip">No thanks</button>' +
        '</div>' +
        '<p class="wpa-lead-status" style="display:none;"></p>';
      body.appendChild(el);
      body.scrollTop = body.scrollHeight;
      bubuTrack('assistant_lead_shown', { page_type: bubuPageType() });

      var nameInput = el.querySelector('.wpa-lead-name');
      var emailInput = el.querySelector('.wpa-lead-email');
      var status = el.querySelector('.wpa-lead-status');
      var sendBtn = el.querySelector('.wpa-lead-send');

      el.querySelector('.wpa-lead-skip').addEventListener('click', function () {
        bubuTrack('assistant_lead_dismissed', { page_type: bubuPageType() });
        el.remove();
      });

      sendBtn.addEventListener('click', function () {
        var name = nameInput.value.trim();
        var email = emailInput.value.trim();
        if (!name && !email) { el.remove(); return; }

        sendBtn.disabled = true;
        sendBtn.textContent = 'Sending...';
        status.style.display = 'none';

        var lastQuestion = '';
        for (var i = history.length - 1; i >= 0; i--) {
          if (history[i].role === 'user') { lastQuestion = history[i].content; break; }
        }

        fetch('https://formsubmit.co/ajax/reservas@wildpapagayo.com', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
          body: JSON.stringify({
            '_subject': 'New Chat Lead (Bubu) — Wild Papagayo',
            '_template': 'table',
            '_captcha': 'false',
            'Name': name || '(not provided)',
            'Email': email || '(not provided)',
            'Page': location.href,
            'Last Question Asked': lastQuestion || '(none)',
            'Conversation ID': conversationId || '(none)'
          })
        })
          .then(function (r) { return r.json(); })
          .then(function (result) {
            if (!result || !result.success) throw new Error('failed');
            bubuTrack('assistant_lead_submitted', { page_type: bubuPageType() });
            el.innerHTML = '<p style="margin:0;">Thanks! We\'ll follow up soon.</p>';
          })
          .catch(function () {
            status.textContent = "Couldn't send — please try WhatsApp instead.";
            status.style.display = 'block';
            sendBtn.disabled = false;
            sendBtn.textContent = 'Send';
          });
      });
    }

    function send(text) {
      if (!text.trim()) return;
      suggestions.style.display = 'none';
      addMessage('user', text.replace(/&/g, '&amp;').replace(/</g, '&lt;'));
      history.push({ role: 'user', content: text });
      input.value = '';
      var typing = addMessage('bot', '<span class="wpa-msg typing">Thinking...</span>');
      typing.classList.add('typing');
      bubuTrack('assistant_question', { page_type: bubuPageType() });

      fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: text, history: history, conversation_id: conversationId, attribution: bubuAttributionPayload() })
      })
        .then(function (r) { return r.json(); })
        .then(function (data) {
          typing.remove();
          if (data.reply) {
            addMessage('bot', linkify(data.reply));
            history.push({ role: 'assistant', content: data.reply });
            bubuTrack('assistant_response', { page_type: bubuPageType() });
            maybeShowLeadCapture();
          } else {
            addMessage('bot', data.error || "Sorry, something went wrong. Please try WhatsApp instead.");
            bubuTrack('assistant_error', { page_type: bubuPageType(), error_type: 'api_error' });
          }
        })
        .catch(function () {
          typing.remove();
          addMessage('bot', 'Sorry, the assistant is temporarily unavailable. Please reach us on <a href="https://wa.me/50688566325" target="_blank">WhatsApp</a>.');
          bubuTrack('assistant_error', { page_type: bubuPageType(), error_type: 'network_error' });
        });
    }

    fab.addEventListener('click', function () {
      panel.classList.toggle('open');
      if (panel.classList.contains('open')) {
        bubuTrack('assistant_open', { page_type: bubuPageType() });
        if (!body.dataset.greeted) {
          body.dataset.greeted = '1';
          addMessage('bot', "Hi! I'm Bubu, your Wild Papagayo travel assistant. Ask me about our hotels, tours, destinations or trip planning.");
        }
      }
    });
    panel.querySelector('.wpa-close').addEventListener('click', function () { panel.classList.remove('open'); });
    sendBtn.addEventListener('click', function () { send(input.value); });
    input.addEventListener('keydown', function (e) { if (e.key === 'Enter') send(input.value); });
    suggestions.addEventListener('click', function (e) {
      if (e.target.classList.contains('wpa-sugg')) send(e.target.dataset.q);
    });
    panel.addEventListener('click', function (e) {
      var link = e.target.closest && e.target.closest('a[href*="wa.me"]');
      if (link) bubuTrack('assistant_whatsapp_click', { page_type: bubuPageType() });
    });
  });
})();
