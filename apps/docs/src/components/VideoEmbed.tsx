import React, {useEffect, useRef} from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';

/**
 * Fetch and play only after the clip enters the viewport.
 *
 * We used to put `autoPlay` + `preload="auto"` on silent clips.
 * Opening the Lesson 1 page then transferred **2.9MB** — four clips
 * still off-screen were downloaded in full. That is a real cost for
 * anyone reading on a phone plan.
 *
 * Keep `preload="none"` and play only when IntersectionObserver says
 * the clip is visible. The poster shows first, so the slot is never empty
 * while the file loads.
 */
function useAutoplayWhenVisible(enabled: boolean) {
  const ref = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!enabled || !el) return;

    // Browsers can refuse autoplay (especially when the tab is hidden).
    // Fail quietly. The user can still press play on the controls.
    const tryPlay = () => el.play().catch(() => {});

    // If this API is missing, just play. Better than never showing the clip.
    if (typeof IntersectionObserver === 'undefined') {
      tryPlay();
      return;
    }

    const io = new IntersectionObserver(
      ([entry]) => (entry.isIntersecting ? tryPlay() : el.pause()),
      {threshold: 0.25},
    );
    io.observe(el);

    // If the tab opened hidden, the callback above never fires. Check again
    // when the tab becomes visible.
    const onVisible = () => {
      if (document.visibilityState !== 'visible') return;
      const r = el.getBoundingClientRect();
      const vh = window.innerHeight || document.documentElement.clientHeight;
      if (r.top < vh && r.bottom > 0) tryPlay();
    };
    document.addEventListener('visibilitychange', onVisible);

    return () => {
      io.disconnect();
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [enabled]);

  return ref;
}

type Props = {
  /** YouTube video ID. Leave empty if it has not been recorded yet. */
  youtube?: string;
  /** Path to a local clip under static/. Example: 'video/chapter-01-title.mp4' */
  src?: string;
  /** Path to a poster image under static/. Used only with local clips. */
  poster?: string;
  /** Clip title */
  title: string;
  /** Target length. Example: '90s' */
  duration?: string;
  /** One line on what this clip shows. Doubles as a shooting brief. */
  shows?: string;
  /** True for a short silent picture-only clip (autoplay + loop) */
  silent?: boolean;
  /**
   * Frame aspect ratio. Default is the game view (`1212 / 540`).
   *
   * Clips cropped from the editor have mixed ratios. A mismatch does not
   * crop the video; it leaves empty bands above/below (or left/right).
   * Pass something like `'1212 / 120'`.
   */
  ratio?: string;
};

/**
 * Course clip.
 *
 * Do not upload a whole lesson as one video. Cut **only the stretch you
 * need to see to understand**, and put it under the section.
 * Skip a clip when the writing is enough.
 *
 * If both youtube and src are empty, a one-line "recording planned" card
 * is shown. It does not eat the page, so the lesson notes stay readable
 * without video.
 */
export default function VideoEmbed({
  youtube,
  src,
  poster,
  title,
  duration,
  shows,
  silent,
  ratio,
}: Props): React.ReactElement {
  const frameStyle = ratio ? ({'--mb-clip-ratio': ratio} as React.CSSProperties) : undefined;
  const localSrc = useBaseUrl(src ?? '');
  const posterUrl = useBaseUrl(poster ?? '');
  const videoRef = useAutoplayWhenVisible(Boolean(src && silent));

  if (youtube) {
    return (
      <figure className="mb-clip">
        <div className="mb-clip__frame" style={{'--mb-clip-ratio': '16 / 9'} as React.CSSProperties}>
          <iframe
            src={`https://www.youtube-nocookie.com/embed/${youtube}`}
            title={title}
            loading="lazy"
            allow="accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowFullScreen
          />
        </div>
        <figcaption className="mb-clip__caption">{title}</figcaption>
      </figure>
    );
  }

  if (src) {
    return (
      <figure className="mb-clip">
        <div className="mb-clip__frame" style={frameStyle}>
          <video
            ref={videoRef}
            src={localSrc}
            poster={poster ? posterUrl : undefined}
            title={title}
            controls
            playsInline
            muted={silent}
            loop={silent}
            // Do not set the autoPlay attribute. useAutoplayWhenVisible
            // calls play() only after the clip enters the viewport.
            // preload="none" means only the poster is fetched until then.
            preload="none"
          />
        </div>
        <figcaption className="mb-clip__caption">{title}</figcaption>
      </figure>
    );
  }

  return (
    <div className="mb-clip mb-clip--pending" role="note">
      <span className="mb-clip__badge" aria-hidden="true">
        ▶
      </span>
      <span className="mb-clip__meta">
        <strong>{title}</strong>
        <span className="mb-clip__sub">
          Recording planned{duration ? ` · ~${duration}` : ''}
          {shows ? ` · ${shows}` : ''}
        </span>
      </span>
    </div>
  );
}
