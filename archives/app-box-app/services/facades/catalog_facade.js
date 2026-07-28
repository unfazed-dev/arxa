// CatalogFacade — kits, devices and ship targets. One facade because all
// three answer the same question: what is actually available to this project.
import * as kits from '../repositories/kit_repository.js';
import * as devices from '../repositories/device_repository.js';
import * as targets from '../repositories/target_repository.js';

// Phase counts and stub findings are two separate axes and neither is derived
// from the other: a kit can be phase `stable` and still ship a provider that
// throws (auth, deploy). Deriving one from the other produces a number that
// silently stops matching the rows.
export const kitList = () => ({ kits: kits.kits(), total: kits.total(), phases: kits.phases() });
export const deviceList = () => ({ devices: devices.devices() });
export const targetList = () => ({ targets: targets.targets() });
