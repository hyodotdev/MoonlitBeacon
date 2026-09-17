import MDXComponents from '@theme-original/MDXComponents';
import VideoEmbed from '@site/src/components/VideoEmbed';

// Let .mdx pages use <Video /> without an import.
export default {
  ...MDXComponents,
  Video: VideoEmbed,
};
