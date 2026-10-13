import React from 'react';
import Layout from '@theme/Layout';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import {APP_STORE_URL, FIRST_PLAY_MAILTO, PLAY_STORE_URL, SUPPORT_PRIVACY_URL} from '../storeLinks';

export default function FirstPlay(): React.ReactElement {
  const {siteConfig} = useDocusaurusContext();

  return (
    <Layout
      title="First-play sessions"
      description="Volunteer for a short first-play session of Moonlit Beacon. Five readers who have never played.">
      <main className="container mb-section">
        <h1>First-play sessions</h1>
        <p>
          We are inviting <strong>up to five course readers who have never
          played Moonlit Beacon</strong> to a short volunteer first-play
          session: install the current game below, but wait to open it until
          the agreed session, so your first minutes stay fresh. Then play the
          opening minutes and tell us where you got stuck. Your confusion is
          the data — there are no wrong answers.
        </p>

        <h2>Get the game</h2>
        <p className="mb-play__links">
          <a className="button button--primary button--lg" href={PLAY_STORE_URL}>
            Get it on Google Play
          </a>
          <a className="button button--secondary button--lg" href={APP_STORE_URL}>
            Download on the App Store
          </a>
        </p>

        <h2>Volunteer (optional)</h2>
        <p>
          If you want a session, write to us. The button below only opens a
          draft in your own mail app — it does not send or register anything,
          and an enquiry is not consent to be observed.
        </p>
        <p>
          <a className="button button--secondary" href={FIRST_PLAY_MAILTO}>
            Volunteer by email
          </a>
        </p>
        <p>
          A session is arranged separately, only with your consent before any
          observation. You can stop at any time. No purchase or review is
          required, and we never ask for your account, player ID, password,
          receipts, or screenshots. There is no automatic screen recording,
          and anything you say is quoted only with your permission.
          Email is processed under the existing support privacy policy
          (<a href={SUPPORT_PRIVACY_URL}>support requests</a>).
        </p>

        <h2>Before you write</h2>
        <ul>
          <li>You have read at least part of the course and installed the game above — but have not opened it yet.</li>
          <li>You have never played Moonlit Beacon before on any device.</li>
          <li>Know your device model and OS version; we record the app version together at your first open.</li>
          <li>No account is needed to play: guest entry works, and social login is optional.</li>
          <li>Expect about 20 minutes: a few minutes of play, then short questions.</li>
          <li>Only five sessions are planned and a reply may take a few days; bookings are confirmed separately, so a late reply does not mean the seats are full.</li>
        </ul>
        <p>{siteConfig.title} first-play invitation. This page adds no tracking scripts of its own.</p>
      </main>
    </Layout>
  );
}
