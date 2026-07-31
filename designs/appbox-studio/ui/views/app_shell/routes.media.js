// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Media-lab routes — one smoke screen per named island runtime.
import * as rive from './media/rive/rive_viewmodel.js';
import * as lottie from './media/lottie/lottie_viewmodel.js';
import * as dotlottie from './media/dotlottie/dotlottie_viewmodel.js';
import * as model3d from './media/model3d/model3d_viewmodel.js';
import * as scene3d from './media/scene3d/scene3d_viewmodel.js';
import * as game from './media/game/game_viewmodel.js';

export default [
  ['GET', '/media/rive', rive.page],
  ['GET', '/media/lottie', lottie.page],
  ['GET', '/media/dotlottie', dotlottie.page],
  ['GET', '/media/dotlottie/stage', dotlottie.stage],
  ['GET', '/media/model3d', model3d.page],
  ['GET', '/media/model3d/stage', model3d.stage],
  ['GET', '/media/scene3d', scene3d.page],
  ['GET', '/media/game', game.page],
];
