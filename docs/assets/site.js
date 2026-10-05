// Shared by every page of the website: theme, scroll reveals and the download button for this Mac.
// Each part looks for its own elements and does nothing when a page doesn't have them.
(() => {
  const root = document.documentElement;
  const KEY = 'markify.theme';
  const dark = matchMedia('(prefers-color-scheme: dark)');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Theme: "system" follows macOS; "light" and "dark" are kept for the next visit.
  const stored = () => { try { const t = localStorage.getItem(KEY); return t === 'light' || t === 'dark' ? t : 'system'; } catch { return 'system'; } };
  const resolved = (t) => t === 'system' ? (dark.matches ? 'dark' : 'light') : t;
  const paint = (t) => {
    if (t === 'system') delete root.dataset.theme; else root.dataset.theme = t;
    const r = resolved(t);
    root.dataset.resolved = r;
    const bg = getComputedStyle(document.body).backgroundColor;
    document.querySelectorAll('meta[name="theme-color"]').forEach(m => { m.content = bg; m.removeAttribute('media'); });
    document.querySelectorAll('[data-theme-set]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.themeSet === t)));
    document.querySelectorAll('.theme-btn').forEach(b => b.setAttribute('aria-label', r === 'dark' ? 'Switch to light appearance' : 'Switch to dark appearance'));
  };
  const setTheme = (t, x, y) => {
    try { if (t === 'system') localStorage.removeItem(KEY); else localStorage.setItem(KEY, t); } catch {}
    if (resolved(t) === root.dataset.resolved || reduce || !document.startViewTransition) { paint(t); return; }
    const cx = x ?? innerWidth - 60, cy = y ?? 36;
    const radius = Math.hypot(Math.max(cx, innerWidth - cx), Math.max(cy, innerHeight - cy));
    const vt = document.startViewTransition(() => paint(t));
    vt.ready.then(() => root.animate(
      { clipPath: [`circle(0px at ${cx}px ${cy}px)`, `circle(${radius}px at ${cx}px ${cy}px)`] },
      { duration: 700, easing: 'cubic-bezier(.2,.8,.2,1)', pseudoElement: '::view-transition-new(root)' }
    )).catch(() => {});
  };
  paint(stored());
  dark.addEventListener('change', () => { if (stored() === 'system') paint('system'); });
  document.querySelectorAll('.theme-btn').forEach(b => b.addEventListener('click', (e) => {
    const r = b.getBoundingClientRect();
    setTheme(root.dataset.resolved === 'dark' ? 'light' : 'dark', r.left + r.width / 2, r.top + r.height / 2);
  }));
  document.querySelectorAll('[data-theme-set]').forEach(b => b.addEventListener('click', (e) => setTheme(b.dataset.themeSet, e.clientX, e.clientY)));

  // Scroll reveal. Items in a .stagger container cascade.
  document.querySelectorAll('.stagger').forEach(group => {
    [...group.children].forEach((el, i) => { el.style.setProperty('--d', (i * 0.08) + 's'); });
  });
  const reveal = new IntersectionObserver((entries) => entries.forEach(en => {
    if (en.isIntersecting) { en.target.classList.add('in'); reveal.unobserve(en.target); }
  }), { rootMargin: '0px 0px -8% 0px' });
  document.querySelectorAll('.rv,.rv-scale').forEach(el => reveal.observe(el));

  // Download: pick the build for this Mac. Chrome and Edge report the architecture; Safari and Firefox don't,
  // so the GPU decides (Apple GPUs support ASTC textures, Intel and AMD don't). Unknown means Apple silicon,
  // which nearly every Mac on macOS 26 has. The other build is always one click away.
  const buttons = document.querySelectorAll('[data-dl]');
  if (!buttons.length) return;
  const BUILDS = {
    as: { url: 'https://github.com/spaquet/markify/releases/latest/download/markify-as.dmg', name: 'Apple silicon', long: 'Macs with M1 or later' },
    intel: { url: 'https://github.com/spaquet/markify/releases/latest/download/markify-intel.dmg', name: 'Intel', long: 'Macs with an Intel processor' }
  };
  const fromGPU = () => {
    try {
      const gl = document.createElement('canvas').getContext('webgl');
      if (!gl) return null;
      const info = gl.getExtension('WEBGL_debug_renderer_info');
      const name = info ? String(gl.getParameter(info.UNMASKED_RENDERER_WEBGL)) : '';
      if (/Intel|AMD|Radeon|NVIDIA|GeForce/i.test(name)) return 'intel';
      if (/Apple M\d/i.test(name)) return 'as';
      const exts = gl.getSupportedExtensions() || [];
      if (exts.includes('WEBGL_compressed_texture_astc')) return 'as';
      return null;
    } catch { return null; }
  };
  const detect = async () => {
    const ua = navigator.userAgent;
    const iPad = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
    if (!/Macintosh|Mac OS X/.test(ua) || iPad) return { mac: false, arch: 'as', sure: false };
    try {
      if (navigator.userAgentData?.getHighEntropyValues) {
        const { architecture } = await navigator.userAgentData.getHighEntropyValues(['architecture']);
        if (architecture === 'arm') return { mac: true, arch: 'as', sure: true };
        if (architecture === 'x86') return { mac: true, arch: 'intel', sure: true };
      }
    } catch {}
    const gpu = fromGPU();
    return { mac: true, arch: gpu || 'as', sure: !!gpu };
  };
  detect().then(({ mac, arch, sure }) => {
    const main = BUILDS[arch], other = BUILDS[arch === 'as' ? 'intel' : 'as'];
    buttons.forEach(b => {
      b.href = main.url;
      const sub = b.querySelector('[data-dl-sub]');
      if (sub) sub.textContent = `${main.name} · ${sub.dataset.version || ''}`.replace(/ · $/, '');
      const name = b.querySelector('[data-dl-name]');
      if (name) name.textContent = mac ? 'Download for Mac' : 'Download for macOS';
    });
    document.querySelectorAll('[data-dl-alt]').forEach(a => { a.href = other.url; a.textContent = `Download for ${other.name}`; });
    document.querySelectorAll('[data-dl-note]').forEach(n => {
      n.textContent = !mac ? 'Markify runs on a Mac with macOS 26.' : sure ? `This looks like a Mac with ${main.name === 'Intel' ? 'an Intel processor' : 'Apple silicon'}.` : `For ${main.long}.`;
    });
    document.querySelectorAll('[data-dl-other-label]').forEach(n => { n.textContent = arch === 'as' ? 'Have an Intel Mac?' : 'Have a Mac with Apple silicon?'; });
  });
})();

// Cookie consent for Google Analytics (Consent Mode; the tag in each page's <head> waits for it). Nothing loads
// until the visitor accepts. A choice is kept for 12 months, a refusal for 6; Global Privacy Control counts as a
// refusal until the visitor accepts. Any [data-consent-open] button reopens the banner.
(() => {
  const KEY = 'markify.consent';
  const MONTH = 30 * 864e5;
  const script = document.currentScript;
  const siteRoot = script ? new URL('..', script.src) : new URL('./', location.href);
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const gpc = navigator.globalPrivacyControl === true;

  const read = () => {
    try {
      const c = JSON.parse(localStorage.getItem(KEY));
      if (!c || (c.choice !== 'granted' && c.choice !== 'denied')) return null;
      return Date.now() - c.at < (c.choice === 'granted' ? 12 : 6) * MONTH ? c : null;
    } catch { return null; }
  };
  let current = read();

  const clearCookies = () => {
    const host = location.hostname;
    document.cookie.split(';').map(c => c.split('=')[0].trim()).filter(n => n.startsWith('_ga')).forEach(name => {
      [undefined, host, '.' + host].forEach(domain => {
        document.cookie = `${name}=; Max-Age=0; path=/` + (domain ? `; domain=${domain}` : '');
      });
    });
  };
  const apply = (choice) => {
    if (choice === 'granted') {
      if (window.markifyAnalytics?.on) window.gtag?.('consent', 'update', { analytics_storage: 'granted' });
      else window.markifyAnalytics?.();
    } else if (window.markifyAnalytics?.on) {
      window.gtag?.('consent', 'update', { analytics_storage: 'denied' });
      clearCookies();
    }
  };
  const choose = (choice) => {
    current = { choice, at: Date.now() };
    try { localStorage.setItem(KEY, JSON.stringify(current)); } catch {}
    apply(choice);
    hide();
  };

  const css = `
.cc{position:fixed;z-index:1000;left:20px;bottom:20px;width:min(440px,calc(100vw - 40px));display:grid;grid-template-columns:auto 1fr;gap:16px;padding:20px 20px 18px;
  border-radius:24px;border:1px solid var(--line,var(--rule));background:color-mix(in srgb,var(--surface,var(--page)) 86%,transparent);color:var(--ink);font:15px/1.5 var(--ui,-apple-system,BlinkMacSystemFont,sans-serif);
  -webkit-backdrop-filter:blur(24px) saturate(1.6);backdrop-filter:blur(24px) saturate(1.6);
  box-shadow:0 1px 0 rgba(255,255,255,.08) inset,0 24px 60px -18px rgba(0,0,0,.35),0 8px 20px -10px rgba(0,0,0,.18);
  transform:translateY(calc(100% + 40px));opacity:0;transition:transform .6s cubic-bezier(.2,.9,.25,1.15),opacity .35s ease}
.cc.on{transform:none;opacity:1}
.cc[hidden],.cc [hidden]{display:none!important}
.cc-mark{width:46px;height:46px;border-radius:15px;display:grid;place-items:center;color:#fff;
  background:linear-gradient(145deg,#2E63D8,#0B2368);box-shadow:0 8px 18px -8px rgba(10,40,120,.7),0 1px 0 rgba(255,255,255,.25) inset}
.cc-mark svg{width:26px;height:26px}
.cc h2{font:600 16px/1.3 var(--ui,inherit);letter-spacing:-.01em;margin:2px 0 4px;color:var(--ink)}
.cc p{margin:0;font-size:14px;color:var(--ink2);text-wrap:pretty}
.cc p a{color:var(--ink);text-decoration:underline;text-decoration-color:var(--line2,var(--rule));text-underline-offset:3px}
.cc p a:hover{text-decoration-color:currentColor}
.cc-note{display:flex;gap:8px;align-items:flex-start;margin-top:10px;padding:9px 11px;border-radius:12px;background:var(--field);font-size:13px;color:var(--ink2)}
.cc-note svg{flex:none;width:15px;height:15px;margin-top:2px}
.cc-actions{grid-column:1/-1;display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:2px}
.cc-actions button{height:40px;border-radius:999px;border:0;font:600 14px var(--ui,inherit);cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:7px;
  transition:transform .3s cubic-bezier(.3,1.4,.5,1),box-shadow .25s,background .2s}
.cc-actions button:hover{transform:translateY(-1px)}
.cc-actions button:active{transform:scale(.97)}
.cc-actions button:focus-visible,.cc-x:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.cc-actions svg{width:16px;height:16px}
.cc-no{background:var(--field);color:var(--ink)}
.cc-no:hover{background:var(--line2,var(--rule))}
.cc-yes{background:var(--ink);color:var(--bg,var(--page))}
.cc-yes:hover{box-shadow:0 10px 24px -10px rgba(0,0,0,.5)}
.cc-x{position:absolute;top:12px;right:12px;width:28px;height:28px;border-radius:50%;border:0;background:transparent;color:var(--ink3);cursor:pointer;display:grid;place-items:center}
.cc-x:hover{background:var(--field);color:var(--ink)}
.cc-x svg{width:14px;height:14px}
[data-consent-open]{background:none;border:0;padding:0;font:inherit;color:inherit;cursor:pointer;transition:color .2s}
[data-consent-open]:hover{color:var(--ink)}
@media (max-width:520px){.cc{left:12px;right:12px;bottom:12px;width:auto;padding:18px 16px 16px;gap:14px}.cc-mark{width:40px;height:40px;border-radius:13px}}
@media print{.cc{display:none}}
@media (prefers-reduced-motion:reduce){.cc{transition:opacity .2s}}`;

  const cookie = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" fill-opacity=".18" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" d="M20.9 12.6a8.9 8.9 0 1 1-9.4-9.5 3 3 0 0 0 3.6 3.6 3 3 0 0 0 3.2 3.4 2.6 2.6 0 0 0 2.6 2.5z"/><g fill="currentColor"><circle cx="8.4" cy="9.6" r="1.25"/><circle cx="12.6" cy="13.2" r="1.25"/><circle cx="8.6" cy="15.6" r="1.05"/><circle cx="15.9" cy="16.4" r="1.05"/><circle cx="11.6" cy="8.2" r=".8"/></g></svg>';
  const check = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" d="m5 12.5 4.5 4.5L19 7.5"/></svg>';
  const cross = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" d="M6.5 6.5l11 11m0-11-11 11"/></svg>';
  const shield = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" d="M12 3 5 6v5.5c0 4.3 3 8 7 9.5 4-1.5 7-5.2 7-9.5V6z"/></svg>';

  let box = null;
  const build = () => {
    const style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
    box = document.createElement('section');
    box.className = 'cc';
    box.hidden = true;
    box.setAttribute('role', 'region');
    box.setAttribute('aria-labelledby', 'cc-title');
    box.innerHTML = `
      <div class="cc-mark" aria-hidden="true">${cookie}</div>
      <div>
        <h2 id="cc-title">Cookies, only if you say so</h2>
        <p>May we use Google Analytics to count visits and see which pages help? It sets cookies only if you accept. The Markify app never tracks you. <a href="${new URL('privacy.html#cookies', siteRoot)}">Privacy policy</a></p>
        <p class="cc-note" hidden></p>
      </div>
      <div class="cc-actions">
        <button type="button" class="cc-no" data-cc="denied">${cross}Decline</button>
        <button type="button" class="cc-yes" data-cc="granted">${check}Accept</button>
      </div>
      <button type="button" class="cc-x" aria-label="Close" hidden>${cross}</button>`;
    box.querySelectorAll('[data-cc]').forEach(b => b.addEventListener('click', () => choose(b.dataset.cc)));
    box.querySelector('.cc-x').addEventListener('click', hide);
    box.addEventListener('keydown', (e) => { if (e.key === 'Escape' && current) hide(); });
    document.body.appendChild(box);
  };
  const show = (focus) => {
    if (!box) build();
    const note = box.querySelector('.cc-note');
    const when = current ? new Date(current.at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' }) : '';
    const text = current ? `You ${current.choice === 'granted' ? 'accepted' : 'declined'} on ${when}. You can change your mind at any time.`
      : gpc ? 'Your browser sends Global Privacy Control, so analytics stay off unless you accept.' : '';
    note.hidden = !text;
    note.innerHTML = text ? shield + '<span></span>' : '';
    if (text) note.querySelector('span').textContent = text;
    box.querySelector('.cc-x').hidden = !current;
    box.hidden = false;
    void box.offsetWidth; // start the slide-in from the hidden position
    box.classList.add('on');
    if (focus) box.querySelector(current?.choice === 'granted' ? '.cc-yes' : '.cc-no').focus({ preventScroll: true });
  };
  function hide() {
    if (!box || box.hidden) return;
    box.classList.remove('on');
    setTimeout(() => { box.hidden = true; }, reduce ? 200 : 600);
  }

  document.querySelectorAll('[data-consent-open]').forEach(b => b.addEventListener('click', (e) => { e.preventDefault(); show(true); }));
  if (current) apply(current.choice);
  else if (!gpc) setTimeout(() => show(false), reduce ? 0 : 900);
})();
