import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    'intro',
    'game',
    'rebuild',
    'monetize',
    {
      type: 'category',
      label: 'Assets',
      collapsed: false,
      items: [
        'assets/download-guide',
        'assets/third-party',
        'assets/manifest',
      ],
    },
  ],
};

export default sidebars;
