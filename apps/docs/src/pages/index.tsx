import React from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import useBaseUrl from '@docusaurus/useBaseUrl';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import {APP_STORE_URL, PLAY_STORE_URL} from '../storeLinks';

const GODOT_MIN_URL = 'https://godotengine.org/download/archive/4.7.1-stable/';
const GODOT_REC_URL = 'https://godotengine.org/download/archive/4.7.2-stable/';

const SPECS = [
  'GDScript',
  '808 × 360 landscape',
  'Compatibility renderer',
  'Android · itch.io',
];

const CARDS = [
  {
    title: 'Every lesson is a store screenshot',
    body: 'Gameplay, art, sound, and UI go in together in the same lesson. We do not start with gray rectangles and paint graphics on at the end.',
  },
  {
    title: 'The official tutorial order, intact',
    body: 'Nodes and scenes → instances → scripts → input → signals. We keep the Godot intro course order, but we do not clone the sample. We build a game with a different goal.',
  },
  {
    title: 'Real assets, real licenses',
    body: 'CC0 art and audio plus an attributed commercial font, drawn from the same selections the shipped game uses. You practice checking licenses and keeping originals separate from the files the game actually uses.',
  },
  {
    title: 'Runnable checkpoints, every lesson',
    body: 'One command generates a lesson’s complete end state beside your own project to compare against — never to overwrite it. Each lesson still ends with a modification you make and verify yourself.',
  },
];

const PATH_GROUPS = [
  {
    title: 'Lessons 1–4 · Shape the game',
    body: 'Project setup, nodes and scenes, instances, your first script. You can set up a 2D project, split a screen into reusable scenes, and drive state from code.',
  },
  {
    title: 'Lessons 5–8 · Bring it alive',
    body: 'Sprite animation, touch input, signals, enemies. You can animate a character, read a thumb, decouple nodes with signals, and sort collisions with layers.',
  },
  {
    title: 'Lessons 9–12 · Finish a run',
    body: 'Run state, HUD, pause, dash. You can open and end a run, show its state on screen, pause cleanly, and add a second thumb of input.',
  },
  {
    title: 'Lessons 13–16 · Ship it',
    body: 'Data-driven enemies, saves, localization, release. You can grow content from data files, persist records, translate a game, and export a signed debug build of your own.',
  },
];

export default function Home(): React.ReactElement {
  const {siteConfig} = useDocusaurusContext();
  const heroSrc = useBaseUrl('img/home-hero.jpg');

  return (
    <Layout title="Moonlit Beacon" description={siteConfig.tagline}>
      <header className="mb-hero">
        <div className="container mb-hero__grid">
          <div>
            <h1 className="mb-hero__title">Build a mobile game. Master Godot’s 2D workflow.</h1>
            <p className="mb-hero__subtitle">
              Sixteen lessons build a 90-second dodge game from a blank Godot
              project — scenes, scripts, touch input, enemies, saves, and
              release. Every lesson runs one loop: build it, explain it,
              modify it, verify it. Runnable reference checkpoints cover all
              sixteen, so you never have to guess what done looks like.
            </p>
            <div className="mb-hero__buttons">
              <Link
                className="button button--primary button--lg"
                to="/course/practice-foundation">
                Start the practice path
              </Link>
              <Link className="button button--secondary button--lg" to="/course">
                View the course
              </Link>
              <a
                className="button button--secondary button--lg"
                href="#play-the-current-game">
                Play the current game
              </a>
            </div>
            <p className="mb-versions">
              Godot <a href={GODOT_MIN_URL}>4.7.1 minimum</a>
              {' · '}
              <a href={GODOT_REC_URL}>4.7.2 recommended (Oct 13, 2026)</a>
              {' · '}matching export templates
              {' · '}all 16 reference checkpoints pass on both (desktop runs)
            </p>
            <div className="mb-specs">
              {SPECS.map((s) => (
                <span key={s}>{s}</span>
              ))}
            </div>
          </div>
          <figure className="mb-hero__shot">
            <img
              src={heroSrc}
              alt="Moonlit Beacon title screen: a lit beacon in a night forest clearing"
              width={1616}
              height={720}
            />
            <figcaption>
              Early survivor reference (v2.1.0) — not the current store
              build or the practice output.
            </figcaption>
          </figure>
        </div>
      </header>

      <main className="mb-section">
        <div className="container">
          <div className="mb-cards">
            {CARDS.map((c) => (
              <div className="mb-card" key={c.title}>
                <h3>{c.title}</h3>
                <p>{c.body}</p>
              </div>
            ))}
          </div>
        </div>
      </main>

      <section className="mb-section mb-learn" aria-labelledby="learn-path">
        <div className="container">
          <h2 id="learn-path">Learn Godot 2D by building it</h2>
          <p className="mb-learn__promise">
            Every lesson follows one loop: <strong>build</strong> the feature
            in your own blank project, <strong>explain</strong> why it works
            that way, <strong>modify</strong> it in the exercises until it
            breaks, and <strong>verify</strong> it against the completion
            checklist. What you keep is the 2D workflow — scenes, scripts,
            input, and release — practiced on a game you can hold.
          </p>
          <div className="mb-cards">
            {PATH_GROUPS.map((g) => (
              <div className="mb-card" key={g.title}>
                <h3>{g.title}</h3>
                <p>{g.body}</p>
              </div>
            ))}
          </div>
          <p className="mb-learn__scope">
            This is a 2D workflow course: top-down sprites, touch controls,
            and a phone export, practiced on a game you can hold. Finish with
            the capstone: add a fourth beacon, a new enemy type of your own,
            and one rule change, then verify all of it on your phone.
          </p>
          <p>
            <Link to="/course#your-learning-path">
              Read the full learning path and capstone →
            </Link>
          </p>
        </div>
      </section>

      <section
        className="mb-section mb-play"
        id="play-the-current-game"
        aria-labelledby="play-heading">
        <div className="container mb-play__grid">
          <div>
            <h2 id="play-heading">Play the current game</h2>
            <p>
              The stores carry the expanded survivor the course grew into:
              six places, weapon paths, relics, guardians, and deeper
              cycles. The sixteen lessons build the original 90-second dodge
              game it started from — three beacons, three enemy kinds plus a
              guardian, and one moonlight gate. Public listings show version
              4.0.1 (October 8, 2026) on both stores. Play the current game
              to see where the foundation leads.
            </p>
            <p className="mb-play__links">
              <a
                className="button button--primary button--lg"
                href={PLAY_STORE_URL}>
                Get it on Google Play
              </a>
              <a
                className="button button--secondary button--lg"
                href={APP_STORE_URL}>
                Download on the App Store
              </a>
            </p>
          </div>
          <div className="mb-card">
            <h3>Never played? Join a first-play session</h3>
            <p>
              Up to five course readers who have never played are invited to
              a short volunteer first-play session. No purchase or review
              needed; guest entry is available and sign-in is optional — and
              nothing is recorded without your separate consent.
            </p>
            <p>
              <Link to="/first-play">Read the invitation →</Link>
            </p>
          </div>
        </div>
      </section>
    </Layout>
  );
}
