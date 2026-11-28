import React, { useEffect, useRef, useState } from 'react';
import {
  Activity,
  AppWindow,
  Download,
  FolderGit2,
  GitBranch,
  GitCommitHorizontal,
  HardDrive,
  Image as ImageIcon,
  Layers,
  Play,
  Plus,
  ShieldCheck,
  Sparkles,
  TerminalSquare,
  X,
} from 'lucide-react';
import fizzDeckLogo from '../assets/fizzdeck-logo-light.svg';
import studioDisplay from '../assets/studio-display.webp';
import workbenchShot from '../assets/native-090-workbench.webp';
import progressShot from '../assets/native-090-progress.webp';
import versionShot from '../assets/native-090-version.webp';
import doctorShot from '../assets/native-090-doctor.webp';
import { COPY, DMG_URL, REPO_URL } from './i18n.js';
import './landing.css';

const screenshots = { workbench: progressShot, git: versionShot, services: doctorShot };
const STORAGE_KEY = 'fizzdeck.landing.lang';

function resolveInitialLang() {
  if (typeof window === 'undefined') return 'zh';
  const param = new URLSearchParams(window.location.search).get('lang');
  if (param === 'en' || param === 'zh') return param;
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored === 'en' || stored === 'zh') return stored;
  } catch {
    // ignore storage errors
  }
  return 'zh';
}

function useLang() {
  const [lang, setLang] = useState(resolveInitialLang);

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEY, lang);
    } catch {
      // ignore storage errors
    }
    const dict = COPY[lang];
    document.documentElement.lang = lang === 'en' ? 'en' : 'zh-CN';
    document.title = dict.meta.title;
    for (const tag of document.querySelectorAll('meta[name="description"], meta[property="og:description"], meta[name="twitter:description"]')) {
      tag.content = dict.meta.description;
    }
    for (const tag of document.querySelectorAll('meta[property="og:title"], meta[name="twitter:title"]')) {
      tag.content = dict.meta.title;
    }
  }, [lang]);

  const toggleLang = () => {
    const next = lang === 'zh' ? 'en' : 'zh';
    const url = new URL(window.location.href);
    url.searchParams.set('lang', next);
    window.history.replaceState(window.history.state, '', url);
    setLang(next);
  };
  return { toggleLang, t: COPY[lang] };
}

function AppleMark({ size = 14 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M16.36 12.7c0-2.16 1.76-3.2 1.84-3.25-1-1.46-2.56-1.66-3.11-1.68-1.31-.14-2.58.78-3.25.78-.68 0-1.71-.77-2.82-.75-1.43.02-2.77.85-3.51 2.13-1.52 2.63-.39 6.5 1.07 8.63.73 1.04 1.58 2.2 2.7 2.16 1.09-.04 1.5-.7 2.82-.7 1.31 0 1.69.7 2.82.68 1.17-.02 1.91-1.05 2.61-2.1.85-1.22 1.19-2.42 1.21-2.48-.03-.01-2.38-.91-2.38-3.42ZM14.23 6.38c.59-.73.99-1.72.88-2.73-.85.04-1.91.57-2.52 1.29-.54.63-1.03 1.65-.9 2.62.95.07 1.94-.46 2.54-1.18Z" />
    </svg>
  );
}

const FEATURE_ICONS = {
  folder: FolderGit2,
  sparkles: Sparkles,
  terminal: TerminalSquare,
  'git-commit': GitCommitHorizontal,
  'git-branch': GitBranch,
  shield: ShieldCheck,
  play: Play,
  activity: Activity,
  image: ImageIcon,
  menubar: AppWindow,
  'hard-drive': HardDrive,
  layers: Layers,
};

function FloatingPillNav({ t, onToggleLang }) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const onScroll = () => setVisible(window.scrollY > 150);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <div className="pill-nav-wrap" data-visible={visible ? 'true' : 'false'}>
      <header className="pill-nav">
        <a className="brand-link" href="#top">
          <img src={fizzDeckLogo} alt="" />
          <span>FizzDeck</span>
        </a>
        <nav className="pill-links" aria-label={t.nav.label}>
          <a href="#views">{t.nav.views}</a>
          <a href="#features">{t.nav.features}</a>
          <a href="#shortcut">{t.nav.shortcut}</a>
          <a href="#faq">{t.nav.faq}</a>
        </nav>
        <div className="pill-actions">
          <button
            type="button"
            className="lang-pill"
            onClick={onToggleLang}
            aria-label={t.nav.langAria}
          >
            {t.nav.langSwitch}
          </button>
          <a className="pill-cta" href={DMG_URL} target="_blank" rel="noreferrer" aria-label={t.nav.download}>
            <Download size={13} strokeWidth={2} aria-hidden="true" />
            <span>{t.nav.download}</span>
          </a>
        </div>
      </header>
    </div>
  );
}

function Hero({ t, onToggleLang }) {
  const zoomRef = useRef(null);

  useEffect(() => {
    const el = zoomRef.current;
    if (!el) return undefined;

    const reducedQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    let rafId = 0;
    let current = 1;
    let target = 1;
    let initialized = false;

    const computeTarget = () => {
      if (reducedQuery.matches) return 1;
      const mobile = window.innerWidth <= 640;
      const minScale = mobile ? 0.90 : 0.77;
      const distance = mobile ? 260 : 475;
      const progress = Math.max(0, Math.min(1, window.scrollY / distance));
      return minScale + (1 - minScale) * progress;
    };

    const applyTransform = (scale) => {
      el.style.transform = scale >= 0.9995 ? 'none' : `scale(${scale.toFixed(4)})`;
    };

    const tick = () => {
      rafId = 0;
      const diff = target - current;
      if (Math.abs(diff) < 0.0004) {
        current = target;
        applyTransform(current);
        return;
      }
      current += diff * 0.18;
      applyTransform(current);
      rafId = window.requestAnimationFrame(tick);
    };

    const sync = (immediate = false) => {
      target = computeTarget();
      if (immediate || reducedQuery.matches) {
        if (rafId) {
          window.cancelAnimationFrame(rafId);
          rafId = 0;
        }
        current = target;
        applyTransform(current);
        return;
      }
      if (!rafId) {
        rafId = window.requestAnimationFrame(tick);
      }
    };

    const onScroll = () => sync(false);
    const onResize = () => sync(true);
    const onMotionChange = () => sync(true);

    if (!initialized) {
      initialized = true;
      sync(true);
    }

    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onResize, { passive: true });
    if (reducedQuery.addEventListener) {
      reducedQuery.addEventListener('change', onMotionChange);
    } else {
      reducedQuery.addListener(onMotionChange);
    }

    return () => {
      if (rafId) window.cancelAnimationFrame(rafId);
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onResize);
      if (reducedQuery.removeEventListener) {
        reducedQuery.removeEventListener('change', onMotionChange);
      } else {
        reducedQuery.removeListener(onMotionChange);
      }
    };
  }, []);

  return (
    <section className="hero container" id="top">
      <div className="hero-brand-bar">
        <a className="brand-link" href="#top">
          <img src={fizzDeckLogo} alt="" />
          <span>FizzDeck</span>
        </a>
        <button
          type="button"
          className="lang-quiet"
          onClick={onToggleLang}
          aria-label={t.nav.langAria}
        >
          {t.nav.langSwitch}
        </button>
      </div>

      <div className="hero-editorial">
        <h1 className="two-tone-h1">
          <span className="ink-strong">{t.hero.lead}</span>{' '}
          <span className="ink-faint">{t.hero.rest}</span>
        </h1>

        <div className="hero-ctas">
          <a className="btn-solid" href={DMG_URL} target="_blank" rel="noreferrer">
            <AppleMark size={15} />
            <span>{t.hero.primaryCta}</span>
          </a>
          <a className="btn-soft" href={REPO_URL} target="_blank" rel="noreferrer">
            <span>{t.hero.secondaryCta}</span>
          </a>
        </div>

        <p className="hero-spec">{t.hero.note}</p>
      </div>

      <div className="hero-gallery-well">
        <div className="hero-zoom-inner" ref={zoomRef}>
          <figure className="hero-figure" aria-label={t.hero.stageCaption}>
            <img src={studioDisplay} alt="" width="2400" height="1610" fetchPriority="high" decoding="async" />
            <img className="studio-window" src={workbenchShot} alt={t.hero.heroAlt} width="1600" height="1042" fetchPriority="high" decoding="async" />
          </figure>
        </div>
      </div>
    </section>
  );
}

function Showcase({ t }) {
  return (
    <section className="section container" id="views">
      <h2 className="two-tone-h2">
        <span className="ink-strong">{t.showcase.lead}</span>{' '}
        <span className="ink-faint">{t.showcase.rest}</span>
      </h2>

      <div className="showcase-grid" role="group" aria-label={t.showcase.hint}>
        {t.showcase.tiles.map((tile) => (
          <article className="showcase-col" key={tile.id}>
            <div className="showcase-media">
              <img src={screenshots[tile.id]} alt={tile.alt} width="1056" height="688" loading="lazy" decoding="async" />
            </div>
            <p className="tile-copy">
              <strong className="ink-strong">{tile.lead}</strong>{' '}
              <span className="ink-muted">{tile.rest}</span>
            </p>
          </article>
        ))}
      </div>
    </section>
  );
}

function FeatureGrid({ t }) {
  return (
    <section className="section container" id="features">
      <h2 className="two-tone-h2">
        <span className="ink-strong">{t.grid.lead}</span>{' '}
        <span className="ink-faint">{t.grid.rest}</span>
      </h2>

      <div className="bento-features">
        {t.grid.items.map((item) => {
          const Icon = FEATURE_ICONS[item.icon] || FolderGit2;
          return (
            <div className="feature-cell" key={item.lead}>
              <div className="feature-icon-row">
                <Icon className="feature-icon" size={20} strokeWidth={1.65} aria-hidden="true" />
                {item.badge && <span className="spot-badge">{item.badge}</span>}
              </div>
              <p className="feature-copy">
                <strong className="ink-strong">{item.lead}</strong>{' '}
                <span className="ink-muted">{item.rest}</span>
              </p>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function ShortcutCallout({ t }) {
  return (
    <section className="section container" id="shortcut">
      <div className="shortcut-block">
        <div className="keycaps" aria-hidden="true">
          <kbd className="keycap">⌘</kbd>
          <kbd className="keycap">K</kbd>
        </div>
        <h2 className="two-tone-h3">
          <span className="ink-strong">{t.shortcut.lead}</span>{' '}
          <span className="ink-faint">{t.shortcut.rest}</span>
        </h2>
        <p className="boundary-caption">{t.shortcut.boundary}</p>
      </div>
    </section>
  );
}

function FAQ({ t }) {
  const [openIndex, setOpenIndex] = useState(0);

  return (
    <section className="section container faq-section" id="faq">
      <div className="faq-column">
        <h2 className="faq-heading">{t.faq.title}</h2>
        <p className="faq-subheading">{t.faq.subtitle}</p>

        <div className="faq-list">
          {t.faq.items.map((item, index) => {
            const isOpen = openIndex === index;
            return (
              <div className="faq-item" key={item.q} data-open={isOpen ? 'true' : 'false'}>
                <button
                  type="button"
                  className="faq-trigger"
                  aria-expanded={isOpen}
                  onClick={() => setOpenIndex(isOpen ? -1 : index)}
                >
                  <span className="faq-plus" aria-hidden="true">
                    {isOpen ? <X size={16} strokeWidth={1.75} /> : <Plus size={16} strokeWidth={1.75} />}
                  </span>
                  <span className="faq-question">{item.q}</span>
                </button>
                {isOpen && (
                  <div className="faq-answer">
                    <span className="ink-strong">{item.aLead}</span>{' '}
                    <span className="ink-muted">{item.aRest}</span>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

function Footer({ t, onToggleLang }) {
  return (
    <footer className="site-footer container">
      <div className="footer-grid">
        <div className="footer-brand-col">
          <a className="brand-link" href="#top">
            <img src={fizzDeckLogo} alt="" />
            <span>FizzDeck</span>
          </a>
          <p className="footer-made">
            <AppleMark size={12} />
            <span>{t.footer.madeForMac}</span>
          </p>
          <p className="footer-copy">{t.footer.copyright}</p>
        </div>

        <div className="footer-links-col">
          <h3>{t.footer.colProduct}</h3>
          <ul>
            {t.footer.linksProduct.map((link) => (
              <li key={link.label}>
                <a href={link.href} target="_blank" rel="noreferrer">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </div>

        <div className="footer-links-col">
          <h3>{t.footer.colInfo}</h3>
          <ul>
            {t.footer.linksInfo.map((link) => (
              <li key={link.label}>
                <a
                  href={link.href}
                  target={link.external ? '_blank' : undefined}
                  rel={link.external ? 'noreferrer' : undefined}
                >
                  {link.label}
                </a>
              </li>
            ))}
            <li>
              <button type="button" className="footer-lang-btn" onClick={onToggleLang}>
                {t.nav.langAria}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </footer>
  );
}

export function Landing() {
  const { t, toggleLang } = useLang();

  return (
    <div className="landing-page">
      <a className="skip-link" href="#main">
        {t.nav.skip}
      </a>
      <FloatingPillNav t={t} onToggleLang={toggleLang} />
      <main id="main" tabIndex={-1}>
        <Hero t={t} onToggleLang={toggleLang} />
        <Showcase t={t} />
        <FeatureGrid t={t} />
        <ShortcutCallout t={t} />
        <FAQ t={t} />
      </main>
      <Footer t={t} onToggleLang={toggleLang} />
    </div>
  );
}
