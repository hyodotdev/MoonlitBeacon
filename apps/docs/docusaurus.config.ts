import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import {themes as prismThemes} from 'prism-react-renderer';

const ORG = 'hyodotdev';
const REPO = 'MoonlitBeacon';
const EDIT_BASE = `https://github.com/${ORG}/${REPO}/tree/main/apps/docs/`;

const config: Config = {
  title: 'Moonlit Beacon',
  tagline: 'Your first 2D game in Godot 4 — from design to an itch.io release',
  favicon: 'img/favicon.png',

  url: `https://${ORG}.github.io`,
  baseUrl: `/${REPO}/`,
  organizationName: ORG,
  projectName: REPO,
  trailingSlash: false,

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  markdown: {
    // Parse .md as CommonMark and only .mdx as MDX.
    // Stops handwritten docs from breaking the build on `<` or `{`.
    format: 'detect',
    // Top-level onBrokenMarkdownLinks is deprecated as of 3.10 and will be removed in v4.
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  presets: [
    [
      'classic',
      {
        docs: {
          path: 'docs',
          routeBasePath: 'docs',
          sidebarPath: './sidebars.ts',
          editUrl: EDIT_BASE,
          showLastUpdateTime: true,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'course',
        path: 'course',
        routeBasePath: 'course',
        sidebarPath: './sidebarsCourse.ts',
        editUrl: EDIT_BASE,
        showLastUpdateTime: true,
      },
    ],
  ],

  themeConfig: {
    // og:image must be raster. KakaoTalk, Twitter, Slack, and Discord
      // will not render an SVG preview, so the card would be text-only.
      image: 'img/social-card.jpg',
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Moonlit Beacon',
      logo: {alt: 'Moonlit Beacon', src: 'img/logo.png'},
      items: [
        {
          type: 'docSidebar',
          docsPluginId: 'course',
          sidebarId: 'courseSidebar',
          position: 'left',
          label: 'Course',
        },
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          href: `https://github.com/${ORG}/${REPO}`,
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Course',
          items: [
            {label: 'Course guide', to: '/course'},
            {label: 'Lesson 1 · Project setup and title screen', to: '/course/chapter-01'},
          ],
        },
        {
          title: 'Docs',
          items: [
            {label: 'Getting started', to: '/docs/intro'},
            {label: 'The game we are making', to: '/docs/game'},
            {label: 'Download the assets', to: '/docs/assets/download-guide'},
          ],
        },
        {
          title: 'More',
          items: [
            {label: 'GitHub', href: `https://github.com/${ORG}/${REPO}`},
            {label: 'Godot Engine', href: 'https://godotengine.org'},
          ],
        },
      ],
      copyright: `Moonlit Beacon — see the credits document for asset licenses.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['gdscript', 'ini', 'bash'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
