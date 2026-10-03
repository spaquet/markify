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
