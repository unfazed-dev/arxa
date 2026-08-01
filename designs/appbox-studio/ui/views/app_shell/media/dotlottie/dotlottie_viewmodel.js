// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.mediadotlottie';

const VIEW = 'ui/views/app_shell/media/dotlottie/dotlottie_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'app', playing: true });

// Play/pause the hypermedia way: re-render the stage fragment with the
// autoplay attribute flipped (named-fragment render, VIEW#stage).
export const stage = (c, h) =>
  h.render(c, `${VIEW}#stage`, { playing: c.req.query('play') !== '0' });
