// Extrait de design/maquette/reference.html par outils/extraire-yumi.py. Ne pas modifier à la main.
/* ---------- Yumi: one SVG whose face is driven by CSS variables, so expressions blend instead of snapping ---------- */
const RIMS = {
  calm: ['#5B8CFF', '#8B6CFF', '#F58AD9'], work: ['#3F7BFF', '#4FA0FF', '#7FD0FF'], think: ['#7B5CFF', '#9B7BFF', '#C9A8FF'],
  warn: ['#FF9A3D', '#FFB547', '#FFD37A'], error: ['#FF4D5E', '#FF5D6C', '#FF9AA4'], done: ['#22C98A', '#3DDC97', '#9BF0C8'], joy: ['#B07BFF', '#F58AD9', '#FFB3E6'],
};
const BASE = { esl: 1, esr: 1, ps: 1, tl: 0, tr: 0, al: 0, ar: 0, bl: 0, br: 0, cl: 0, cr: 0, tilt: 0 };
const MOODS = {
  neutre: {}, heureux: { bl: .42, br: .42 }, curieux: { esl: .92, esr: 1.14, tilt: 7 },
  concentre: { tl: .38, tr: .38, look: [0, .5] }, reflechi: { tl: .16, tr: .16, look: [.8, -.8] },
  surpris: { esl: 1.16, esr: 1.16, ps: .72 }, inquiet: { tl: .3, tr: .3, al: -16, ar: 16 }, agace: { tl: .4, tr: .4, al: 16, ar: -16 },
  clin: { tr: 1.1, cr: 1 }, sommeil: { tl: 1.1, tr: 1.1, cl: 1, cr: 1 },
};
/* Faces taken only while a pose plays */
const POSE_FACES = { las: { tl: .46, tr: .46, look: [.5, .55] }, vide: { tl: .5, tr: .5, look: [0, -.8] }, ailleurs: { esl: .96, esr: .96, look: [.95, -.6] }, serre: { tl: .3, tr: .3, bl: .3, br: .3, ps: .85, al: 10, ar: -10 }, haut: { esl: 1.14, esr: 1.14, ps: .8, look: [0, -1] }, ferme: { tl: 1.1, tr: 1.1, cl: 1, cr: 1 } };
const BODY = 'M8 62C8 31 27 8 50 8s42 23 42 54c0 10-10 14-42 14S8 72 8 62Z';
const STAR = 'M0-5 1.3-1.3 5 0 1.3 1.3 0 5-1.3 1.3-5 0-1.3-1.3Z';
let uid = 0;

function moodVars(mood, rim) {
  const m = Object.assign({}, BASE, MOODS[mood] || POSE_FACES[mood]), [r1, r2, r3] = RIMS[rim], v = { r1, r2, r3 };
  for (const k in BASE) v[k] = m[k];
  if (m.look) { v.lx = m.look[0]; v.ly = m.look[1] }
  return { v, fixed: !!m.look };
}
function setMood(el, mood, rim, temp) {
  if (!temp) { el._mood = mood; el._rim = rim }
  const { v, fixed } = moodVars(mood, rim);
  for (const k in v) el.style.setProperty('--' + k, v[k]);
  if (fixed) el.dataset.fixed = ''; else delete el.dataset.fixed;
  el.setAttribute('aria-label', 'Yumi, ' + mood);
}
function eye(cx, s, id) {
  const o = `transform-origin:${cx}px 45px;`;
  return `<g class="eg" data-sd="${cx < 50 ? -1 : 1}"><g class="es" style="${o}transform:scale(var(--es${s}))"><g class="eye"><ellipse cx="${cx}" cy="45" rx="9" ry="11" fill="url(#${id}e)"/><g class="pupil"><g class="psg"><circle cx="${cx}" cy="46" r="5.4" fill="#000000"/><circle cx="${cx + 1.9}" cy="43.6" r="1.7" fill="#fff"/><circle cx="${cx - 1.6}" cy="48.2" r=".8" fill="#fff" opacity=".7"/></g></g></g></g>
    <rect class="lidt" x="${cx - 17}" y="8" width="34" height="26" fill="#000000" style="${o}transform:rotate(calc(var(--a${s}) * 1deg)) translateY(calc(var(--t${s}) * 25px - 3px))"/>
    <ellipse class="lidb" cx="${cx}" cy="68" rx="16" ry="12" fill="#000000" style="transform:translateY(calc(var(--b${s}) * -22px))"/>
    <path class="shut" d="M${cx - 8} 45q8 6 16 0" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" style="opacity:var(--c${s})"/></g>`;
}
function yumi({ size = 100, mood = 'neutre', rim = 'calm', rimW = 2.6, pose = '', cls = '' } = {}) {
  const id = 'y' + (++uid), g = `url(#${id}g)`, { v, fixed } = moodVars(mood, rim);
  const vars = Object.entries(v).map(([k, x]) => `--${k}:${x}`).join(';');
  const arm = (side, d) => `<g class="arm ${side}"><path d="${d}" stroke="${g}" stroke-width="12" stroke-linecap="round" fill="none"/><path d="${d}" stroke="#000000" stroke-width="8.4" stroke-linecap="round" fill="none"/></g>`;
  return `<svg class="yumi ${cls}" ${fixed ? 'data-fixed' : ''} ${pose ? `data-pose="${pose}"` : ''} viewBox="0 0 100 84" width="${size}" height="${size * .84}" style="${vars};--rw:${rimW}" role="img" aria-label="Yumi, ${mood}">
    <defs>
      <linearGradient id="${id}g" x1="0" x2="1"><stop offset="0" class="s1"/><stop offset=".5" class="s2"/><stop offset="1" class="s3"/></linearGradient>
      <linearGradient id="${id}f" gradientUnits="userSpaceOnUse" x1="0" x2="0" y1="-10" y2="100"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset=".55" stop-color="#fff"/></linearGradient>
      <mask id="${id}m" maskUnits="userSpaceOnUse" x="-120" y="-120" width="340" height="320"><rect x="-120" y="-120" width="340" height="320" fill="url(#${id}f)"/></mask>
      <linearGradient id="${id}k" gradientUnits="userSpaceOnUse" x1="0" x2="0" y1="20" y2="80"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff"/></linearGradient>
      <mask id="${id}n" maskUnits="userSpaceOnUse" x="-120" y="-120" width="340" height="320"><rect x="-120" y="-120" width="340" height="320" fill="url(#${id}k)"/></mask>
      <radialGradient id="${id}h"><stop offset="0" stop-color="#fff" stop-opacity=".2"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
      <radialGradient id="${id}e" cx=".42" cy=".36" r=".75"><stop offset=".45" stop-color="#fff"/><stop offset="1" stop-color="#B4BFE6"/></radialGradient>
      <clipPath id="${id}c"><path class="cp" d="${BODY}"/></clipPath>
      <filter id="${id}b" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3.2"/></filter>
    </defs>
    <g class="tiltg"><ellipse class="floor" cx="50" cy="78" rx="34" ry="4" fill="${g}" opacity=".35" filter="url(#${id}b)"/><g class="pose"><g class="breath">
      <g class="arms">${arm('l', 'M17 52 5 37')}${arm('r', 'M83 52 95 37')}</g>
      <path class="glow" d="${BODY}" fill="none" stroke="${g}" filter="url(#${id}b)" mask="url(#${id}m)" opacity=".85"/>
      <path class="bd" d="${BODY}" fill="#000000"/>
      <g clip-path="url(#${id}c)"><g class="facepos"><g class="eyes">${eye(37, 'l', id)}${eye(63, 'r', id)}</g></g>
        <path class="inner" d="${BODY}" fill="none" stroke="${g}" stroke-width="11" filter="url(#${id}b)" mask="url(#${id}n)" opacity=".5"/>
        <ellipse class="shine" cx="35" cy="24" rx="19" ry="11" fill="url(#${id}h)" transform="rotate(-28 35 24)"/>
        <ellipse class="glint" cx="31" cy="19" rx="4.2" ry="1.9" fill="#fff" opacity=".5" transform="rotate(-32 31 19)"/></g>
      <path class="rim" pathLength="100" d="${BODY}" fill="none" stroke="${g}" mask="url(#${id}m)"/>
      <g class="tops">
        <g class="prop p-casque"><path d="M9 47C9 16 28 1 50 1s41 15 41 46" fill="none" stroke="#2B2E3F" stroke-width="4.2" stroke-linecap="round"/><rect x="2" y="38" width="11" height="20" rx="5" fill="#1F2231" stroke="${g}" stroke-width="1.4"/><rect x="87" y="38" width="11" height="20" rx="5" fill="#1F2231" stroke="${g}" stroke-width="1.4"/></g>
        <g class="prop p-nuage"><g fill="#5A6078"><ellipse cx="50" cy="-9" rx="17" ry="6.5"/><circle cx="40" cy="-12" r="7"/><circle cx="53" cy="-15.5" r="8.5"/><circle cx="62" cy="-10.5" r="6"/></g><g class="rain" stroke="#7FB4FF" stroke-width="1.5" stroke-linecap="round"><path d="M40-1v4"/><path class="r2" d="M48-1v4"/><path class="r3" d="M56-1v4"/><path class="r4" d="M63-1v4"/></g></g>
      </g>
      <g class="props">
        <g class="prop p-clope"><path d="M57 60 75.5 64" stroke="#F1EDE4" stroke-width="3.2" stroke-linecap="round"/><path d="M57 60 61 60.9" stroke="#D9A066" stroke-width="3.2" stroke-linecap="round"/><circle class="ember" cx="76" cy="64.1" r="1.9" fill="#FF7A3D"/></g>
        <g class="prop p-cafe"><g transform="translate(8 8)"><g class="cup"><path d="M65 54h13v6a6.5 6.5 0 0 1-13 0z" fill="#F4F5F8"/><path d="M78 56q5.5 0 5.5 3.6T78 63" fill="none" stroke="#F4F5F8" stroke-width="1.9"/><path d="M66.6 55.4h9.8" stroke="#6B4226" stroke-width="1.7" stroke-linecap="round"/></g></g></g>
        <g class="prop p-soleil"><g class="shades"><rect x="24" y="37" width="24" height="15" rx="6" fill="#0A0B10" stroke="${g}" stroke-width="1.6"/><rect x="52" y="37" width="24" height="15" rx="6" fill="#0A0B10" stroke="${g}" stroke-width="1.6"/><path d="M48 42q2-1.6 4 0" fill="none" stroke="${g}" stroke-width="1.6"/><path d="M29 47l6-6M57 47l6-6" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity=".75"/></g></g>
        <g class="prop p-siffle"><circle cx="52" cy="61" r="2.7" fill="none" stroke="#fff" stroke-width="1.7"/></g>
        <g class="prop p-dodo"><circle class="bubble" cx="58" cy="57" r="6.5" fill="#9BB8FF" fill-opacity=".22" stroke="#9BB8FF" stroke-width="1"/></g>
      </g>
    </g></g><g class="drops" fill="${g}">${'<circle r="0"/>'.repeat(12)}</g><g class="smoke" fill="#D9DCE8">${'<circle r="0"/>'.repeat(16)}</g></g>
    <g fill="${g}" font-family="ui-rounded, Nunito, sans-serif" font-weight="800"><text class="note" x="84" y="22" font-size="11">♪</text><text class="note n2" x="93" y="10" font-size="14">♫</text><text class="note n3" x="100" y="26" font-size="10">♪</text></g>
    <g fill="${g}"><g transform="translate(8 14)"><path class="spark" d="${STAR}"/></g><g transform="translate(92 10) scale(1.3)"><path class="spark sp2" d="${STAR}"/></g><g transform="translate(50 -4) scale(.9)"><path class="spark sp3" d="${STAR}"/></g></g>
    <g fill="#9BB8FF" font-family="ui-rounded, Nunito, sans-serif" font-weight="800"><text class="zz" x="78" y="26" font-size="9">z</text><text class="zz z2" x="86" y="16" font-size="12">z</text><text class="zz z3" x="94" y="6" font-size="15">Z</text></g>
  </svg>`;
}
/* ---------- A soft body: height and lean are springs, the outline is rebuilt every frame, so Yumi wobbles instead of being scaled ---------- */
const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
function bodyPath(h, w, L) {
  const by = 76, ty = by - 68 * h, tx = 50 + L, sy = by - 14 * Math.pow(h, .7), wb = 1 + (w - 1) * .55;
  const lx = 50 - 42 * w + L * .12, rx = 50 + 42 * w + L * .12, cy = sy - 31 * h, my = sy + (by - sy) * .71, f = (n) => n.toFixed(1);
  return `M${f(lx)} ${f(sy)}C${f(lx)} ${f(cy)} ${f(tx - 23 * w)} ${f(ty)} ${f(tx)} ${f(ty)}C${f(tx + 23 * w)} ${f(ty)} ${f(rx)} ${f(cy)} ${f(rx)} ${f(sy)}C${f(rx)} ${f(my)} ${f(50 + 32 * wb)} ${by} 50 ${by}C${f(50 - 32 * wb)} ${by} ${f(lx)} ${f(my)} ${f(lx)} ${f(sy)}Z`;
}
const LIVE = [];
class Blob {
  constructor(svg) {
    this.el = svg; svg._blob = this; svg.classList.add('live');
    this.paths = [...svg.querySelectorAll('.bd,.rim,.glow,.cp,.inner')]; this.egs = [...svg.querySelectorAll('.eg')]; this.glint = svg.querySelector('.glint'); this.yaw = 0; this.pitch = 0;
    this.face = svg.querySelector('.facepos'); this.shine = svg.querySelector('.shine'); this.props = svg.querySelector('.props'); this.tops = svg.querySelector('.tops'); this.pose = svg.querySelector('.pose'); this.arms = svg.querySelector('.arms'); this.floor = svg.querySelector('.floor');
    this.dots = [...svg.querySelectorAll('.drops circle')]; this.parts = []; this.fog = [...svg.querySelectorAll('.smoke circle')]; this.puffs = []; this.scene = null; this.st = 0; this.sa = 0; this.fx = [0, 0, 1, 1];
    Object.assign(this, { h: 1, vh: 0, th: 1, lean: 0, vl: 0, tl: 0, gaze: 0, eye: 0, y: 0, vy: 0, air: false, sleep: false, t: Math.random() * 10, steps: [], t0: 0 });
    this.soft(); LIVE.push(this);
  }
  soft() { this.k = 170; this.c = 9; this.kl = 150; this.cl = 8 }
  hard() { this.k = 420; this.c = 34 }
  setScene(name) {
    this.scene = name ? SCENES[name] : null; this.st = 0; this.sa = 0; this.ex = 0; this.tl = 0; this.th = 1; this.sleep = name === 'dodo';
    delete this.el.dataset.drag; delete this.el.dataset.sip;
    if (name) { this.el.dataset.scene = name; setMood(this.el, this.scene.face, this.scene.rim) } else delete this.el.dataset.scene;
  }
  /* where a point of the face ends up once the body has moved */
  world(x, y) { const [dx, dy, sx, sy] = this.fx; return [50 + (x - 50) * sx + dx - this.lean * .12, 45 + (y - 45) * sy + dy + this.y] }
  puff(x, y, vx, vy, r, life) { this.puffs.push({ x, y, vx, vy, r, life, max: life, ph: Math.random() * 6 }) }
  play(name) { const p = POSE_FX[name]; if (!p) return; this.soft(); this.tl = 0; this.th = 1; this.steps = p.slice(); this.t0 = performance.now() }
  splat(n, pow) { for (const s of [-1, 1]) for (let i = 0; i < n; i++) this.parts.push({ x: 50 + s * 44, y: 71, vx: s * (50 + Math.random() * 80) * pow, vy: -(40 + Math.random() * 80) * pow, r: 1.5 + Math.random() * 1.5, life: .55 + Math.random() * .3 }) }
  fling(s) { for (let i = 0; i < 2; i++) this.parts.push({ x: 50 + s * 34 + this.lean * .5, y: 36 + Math.random() * 22, vx: s * (90 + Math.random() * 90), vy: -(20 + Math.random() * 70), r: 1.3 + Math.random() * 1.3, life: .45 + Math.random() * .3 }) }
  step(dt, now) {
    while (this.steps.length && now - this.t0 >= this.steps[0][0]) this.steps.shift()[1](this);
    this.t += dt; this.st += dt;
    if (this.scene && !this.steps.length && !this.air) (this.scene.tick || ((b) => { b.th = b.scene.th || 1 }))(this, dt);
    const th = this.sleep ? .56 : this.th;
    this.vh += (-(this.h - th) * this.k - this.vh * this.c) * dt; this.h = Math.max(.3, Math.min(1.9, this.h + this.vh * dt));
    this.vl += (-(this.lean - this.tl - this.gaze) * this.kl - this.vl * this.cl) * dt; this.lean += this.vl * dt;
    this.eye += (this.lean - this.eye) * Math.min(1, dt * 9);
    const st = this.el.style, k = Math.min(1, dt * 9);
    this.yaw += ((parseFloat(st.getPropertyValue('--lx')) || 0) * .5 - this.yaw) * k;
    this.pitch += ((parseFloat(st.getPropertyValue('--ly')) || 0) * .32 - this.pitch) * k;
    if (this.air) { this.vy += 900 * dt; this.y += this.vy * dt; if (this.y >= 0) { this.y = 0; this.air = false; this.th = 1; this.soft(); this.vh = -7; this.splat(2, .7) } }
    for (const p of this.parts) { p.vy += 420 * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt }
    this.parts = this.parts.filter(p => p.life > 0 && p.y < 82);
    for (const p of this.puffs) { p.vy -= 10 * dt; p.vx *= 1 - 1.4 * dt; p.x += (p.vx + Math.sin(this.t * 3 + p.ph) * 5) * dt; p.y += p.vy * dt; p.life -= dt }
    this.puffs = this.puffs.filter(p => p.life > 0).slice(-16);
    this.draw();
  }
  draw() {
    const amp = this.sleep ? .03 : .013, sp = this.sleep ? .9 : 1.5;
    const h = this.h + amp * Math.sin(this.t * sp), w = Math.max(.68, Math.min(1.55, 1 / Math.pow(h, .62))), L = this.lean;
    const d = bodyPath(h, w, L); for (const p of this.paths) p.setAttribute('d', d);
    const ey = 76 - 68 * h + 37 * Math.pow(h, .85);
    this.fx = [this.eye * .6, ey - 45, Math.pow(w, .45), Math.pow(h, .5)];
    const ft = `translate(${this.fx[0].toFixed(2)} ${this.fx[1].toFixed(2)}) translate(50 45) scale(${this.fx[2].toFixed(3)} ${this.fx[3].toFixed(3)}) translate(-50 -45)`;
    this.face.setAttribute('transform', ft); this.props.setAttribute('transform', ft);
    this.tops.setAttribute('transform', `translate(${L.toFixed(2)} ${(68 - 68 * h).toFixed(2)})`);
    /* eyes sit on a sphere: turning the head slides them sideways and narrows the one going round the edge */
    for (const g of this.egs) {
      const sd = +g.dataset.sd, ya = sd * .33 + this.yaw, pi = this.pitch, cx = 50 + sd * 13;
      const ex = Math.sin(ya) * Math.cos(pi) * 40.1, ey2 = Math.sin(pi) * 30, fx = Math.max(.35, Math.cos(ya)), fy = Math.max(.6, Math.cos(pi));
      g.setAttribute('transform', `translate(${(ex - sd * 13).toFixed(2)} ${ey2.toFixed(2)}) translate(${cx} 45) scale(${fx.toFixed(3)} ${fy.toFixed(3)}) translate(${-cx} -45)`);
    }
    const top = 76 - 68 * h, sx = 35 + L * .8 - this.yaw * 12, sy2 = top + 16 * h - this.pitch * 6;
    this.shine.setAttribute('cx', sx.toFixed(1)); this.shine.setAttribute('cy', sy2.toFixed(1)); this.shine.setAttribute('rx', (19 * w).toFixed(1)); this.shine.setAttribute('ry', (11 * Math.pow(h, .7)).toFixed(1)); this.shine.setAttribute('transform', `rotate(-28 ${sx.toFixed(1)} ${sy2.toFixed(1)})`);
    const gx = sx - 4, gy = top + 11 * h - this.pitch * 6;
    this.glint.setAttribute('cx', gx.toFixed(1)); this.glint.setAttribute('cy', gy.toFixed(1)); this.glint.setAttribute('transform', `rotate(-32 ${gx.toFixed(1)} ${gy.toFixed(1)})`);
    this.pose.setAttribute('transform', `translate(${(-L * .12).toFixed(2)} ${this.y.toFixed(2)})`);
    this.arms.setAttribute('transform', `translate(${(L * .35).toFixed(2)} ${((1 - h) * 24).toFixed(2)})`);
    this.floor.setAttribute('rx', (34 * w * (this.air ? .7 : 1)).toFixed(1));
    this.fog.forEach((c, i) => { const p = this.puffs[i]; if (p) { const k = p.life / p.max; c.setAttribute('cx', p.x.toFixed(1)); c.setAttribute('cy', p.y.toFixed(1)); c.setAttribute('r', (p.r * (1 + (1 - k) * 2.2)).toFixed(2)); c.setAttribute('opacity', (.5 * k).toFixed(2)) } else c.setAttribute('r', 0) });
    this.dots.forEach((c, i) => { const p = this.parts[i]; if (p) { c.setAttribute('cx', p.x.toFixed(1)); c.setAttribute('cy', p.y.toFixed(1)); c.setAttribute('r', (p.r * Math.min(1, p.life * 3)).toFixed(2)) } else c.setAttribute('r', 0) });
  }
}
const face = (m) => (b) => setMood(b.el, m, b.el._rim || 'calm', true);
const back = (b) => setMood(b.el, b.el._mood || 'neutre', b.el._rim || 'calm', true);
const crouch = (b) => { b.hard(); b.th = .66 }, leap = (b) => { b.soft(); b.th = 1.18; b.vy = -190; b.air = true };
const POSE_FX = {
  /* rise a little, slam flat with the eyes squeezed, hold, then spring back up and wobble */
  ecraser: [[0, b => { b.k = 300; b.c = 22; b.th = 1.12 }], [130, b => { b.hard(); b.th = .5; face('serre')(b) }], [240, b => b.splat(3, 1)], [780, b => { b.soft(); b.c = 7; b.th = 1; face('surpris')(b) }], [1250, back]],
  /* crouch, reach up thin while looking at the sky and swaying, then snap back */
  etirer: [[0, b => { b.hard(); b.th = .8 }], [170, b => { b.k = 110; b.c = 10; b.th = 1.45; b.tl = 5; face('haut')(b) }], [560, b => { b.tl = -5 }], [860, b => { b.tl = 0; b.k = 210; b.c = 6.5; b.th = 1 }], [1250, back]],
  /* eyes shut, the top whips left and right behind the base and throws droplets, then he comes to, a bit dazed */
  secouer: [[0, b => { face('ferme')(b); b.kl = 300; b.cl = 10; b.th = .95; b.tl = 16; b.fling(-1) }], [90, b => { b.tl = -16; b.fling(1) }], [180, b => { b.tl = 14; b.fling(-1) }], [270, b => { b.tl = -14; b.fling(1) }], [360, b => { b.tl = 10; b.fling(-1) }], [450, b => { b.tl = -8 }], [540, b => { b.tl = 0; b.th = 1; b.kl = 150; b.cl = 6 }], [700, face('surpris')], [1050, back]],
  saut: [[0, crouch], [150, leap]],
  celebrer: [[0, crouch], [130, leap], [640, crouch], [770, leap]],
  salut: [[0, b => { b.kl = 55; b.cl = 7; b.th = 1.05; b.tl = 7 }], [280, b => { b.tl = -7 }], [560, b => { b.tl = 7 }], [840, b => { b.tl = -7 }], [1120, b => { b.tl = 0; b.th = 1 }]],
  creux: [[0, b => { b.hard(); b.th = .76 }], [250, b => { b.soft(); b.th = 1 }]],
  arrive: [[0, b => { b.h = 1.45; b.vh = 0; b.c = 7 }]],
  boing: [[0, b => { b.h = .7; b.vh = 0; b.c = 7 }]],
  pop: [[0, b => { b.vh -= 2.4 }]],
};
/* Human habits on a slime. Each one has a face, a rim colour, a prop, and a small routine that runs every frame. */
const R = () => Math.random();
const SCENES = {
  clope: { label: 'Clope', face: 'las', rim: 'work', cap: 'Il bosse dur', hint: "Quand un agent travaille longtemps, Yumi s'en grille une, l'air blasé. Toutes les cinq secondes il tire une taffe (le bout rougit, il gonfle) puis souffle un nuage.",
    tick(b, dt) {
      b.sa += dt; const c = b.st % 5.5, tip = b.world(76, 64);
      if (b.sa > .22) { b.sa = 0; b.puff(tip[0], tip[1], 2 + R() * 4, -13, 1, 1.5) }
      if (c > 3.4 && c < 4.1) { b.th = 1.07; b.el.dataset.drag = ''; b.ex = 0 }
      else if (c >= 4.1 && c < 4.9) { delete b.el.dataset.drag; b.th = .9; if (!b.ex) { b.ex = 1; const m = b.world(62, 59); for (let i = 0; i < 7; i++) b.puff(m[0] + 4, m[1], 24 + R() * 34, -4 - R() * 16, 2.1, 1.7) } }
      else b.th = .94;
    } },
  epuise: { label: 'Épuisé', face: 'vide', rim: 'calm', cap: "J'en peux plus", hint: "Quand il en a marre, il s'étale en flaque, les yeux au ciel, et pousse un long soupir de temps en temps.",
    tick(b) { b.th = .46; const c = b.st % 4.2; if (c < .1 && !b.ex) { b.ex = 1; b.vh += 1.8; const m = b.world(52, 58); for (let i = 0; i < 4; i++) b.puff(m[0] + R() * 8 - 4, m[1] - 6, R() * 10 - 5, -16 - R() * 8, 2, 1.5) } if (c > .5) b.ex = 0 } },
  cafe: { label: 'Café', face: 'las', rim: 'warn', cap: 'Café d\'abord', hint: "Le matin il a sa tasse fumante. Il boit une gorgée, et la caféine fait son effet : les yeux s'ouvrent d'un coup.",
    tick(b, dt) {
      b.sa += dt; const c = b.st % 6, sip = b.el.dataset.sip !== undefined;
      if (b.sa > .35 && !sip) { b.sa = 0; const p = b.world(79, 61); b.puff(p[0], p[1], R() * 4 - 2, -15, .9, 1.2) }
      if (c > 3.4 && c < 4.4) { b.el.dataset.sip = ''; b.tl = -5; b.th = 1.03; b.ex = 0 }
      else { delete b.el.dataset.sip; b.tl = 0; b.th = 1;
        if (c >= 4.4 && c < 5.4) { if (!b.ex) { b.ex = 1; b.vh -= 3.5; setMood(b.el, 'surpris', b.el._rim, true) } }
        else if (b.ex) { b.ex = 0; back(b) } }
    } },
  casque: { label: 'Casque', face: 'heureux', rim: 'joy', cap: 'Il kiffe', hint: 'Quand la musique tourne, il met son casque et bat la mesure de tout son corps.',
    tick(b) { b.th = 1 + .055 * Math.sin(b.st * 12.6); b.tl = 5 * Math.sin(b.st * 6.3) } },
  soleil: { label: 'Lunettes', face: 'neutre', rim: 'done', cap: 'Trop facile', hint: 'Après une réussite, les lunettes de soleil tombent sur son nez. Il est content de lui.' },
  nuage: { label: 'Nuage', face: 'inquiet', rim: 'error', cap: 'Sale journée', th: .9, hint: "Quand quelque chose casse, un petit nuage de pluie s'installe au-dessus de sa tête." },
  siffle: { label: 'Sifflote', face: 'ailleurs', rim: 'calm', cap: 'La la la', hint: "Quand il attend ta réponse depuis un moment, il regarde ailleurs et sifflote, l'air de rien.",
    tick(b) { b.th = 1; b.tl = 4 * Math.sin(b.st * 2.2) } },
  dodo: { label: 'Dodo', face: 'sommeil', rim: 'calm', cap: 'Chut', hint: 'Sans rien à faire, il fond un peu, ronfle, et une bulle gonfle à son nez.' },
};
if (!calm) { let last = performance.now(); const tick = (now) => { const dt = Math.min(.033, (now - last) / 1000); last = now; for (const b of LIVE) b.step(dt, now); requestAnimationFrame(tick) }; requestAnimationFrame(tick) }
const POSE_MS = { saut: 900, etirer: 1300, ecraser: 1400, secouer: 1100, celebrer: 1600, salut: 1520, creux: 400, arrive: 600, pop: 400, boing: 700 };
function playPose(el, name) {
  if (!el) return;
  el.removeAttribute('data-pose'); void el.getBoundingClientRect(); el.dataset.pose = name;
  if (el._blob) el._blob.play(name);
  if (POSE_MS[name]) setTimeout(() => { if (el.dataset.pose === name) el.removeAttribute('data-pose') }, POSE_MS[name]);
}


/* Gaze follows the pointer */
let lastX = innerWidth / 2, lastY = innerHeight / 2;
function look(x, y) {
  lastX = x; lastY = y;
  document.querySelectorAll('.yumi:not([data-fixed])').forEach(el => {
    const r = el.getBoundingClientRect(); if (!r.width) return;
    const lx = Math.tanh((x - r.left - r.width / 2) / 220);
    el.style.setProperty('--lx', lx.toFixed(3)); if (el._blob) el._blob.gaze = lx * 2.5;
    el.style.setProperty('--ly', Math.tanh((y - r.top - r.height / 2) / 180).toFixed(3));
  });
}
addEventListener('pointermove', e => look(e.clientX, e.clientY), { passive: true });

