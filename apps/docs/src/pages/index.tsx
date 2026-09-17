import React from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';

const SPECS = [
  'Godot 4.7.1',
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
    title: 'CC0 free assets only',
    body: 'Ninja Adventure (CC0), Kenney (CC0), Galmuri (OFL). You practice checking licenses and keeping originals separate from the files the game actually uses.',
  },
  {
    title: 'A survival loop that continues on the phone',
    body: 'Pixel 10 is the reference device. A floating move stick, a dash, and auto-attack carry you through the forest, field, and camp raids as you push into the next cycle.',
  },
];

export default function Home(): React.ReactElement {
  const {siteConfig} = useDocusaurusContext();

  return (
    <Layout title="Moonlit Beacon" description={siteConfig.tagline}>
      <header className="mb-hero">
        <h1 className="mb-hero__title">Moonlit Beacon</h1>
        <p className="mb-hero__subtitle">
          Light the beacons in the forest, field, and camp. Grow three weapon
          paths with spirit embers and relics, then take on guardians and
          harder cycles. The sixteen-lesson first complete build is the
          starting point; this site also records the version that grew from
          actually playing it.
        </p>
        <div className="mb-hero__buttons">
          <Link className="button button--primary button--lg" to="/course">
            View the course
          </Link>
          <Link
            className="button button--secondary button--lg"
            to="/docs/intro">
            Read the docs
          </Link>
        </div>
        <div className="mb-specs">
          {SPECS.map((s) => (
            <span key={s}>{s}</span>
          ))}
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
    </Layout>
  );
}
