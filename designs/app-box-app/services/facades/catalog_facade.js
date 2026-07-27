// CatalogFacade — kits, devices and ship targets. One facade because all
// three answer the same question: what is actually available to this project.
import * as kits from '../repositories/kit_repository.js';
import * as devices from '../repositories/device_repository.js';
import * as targets from '../repositories/target_repository.js';

// total/wired come from the seed, not from counting the rows on screen: this
// surface deliberately lists only the kits that are NOT fully wired, so
// counting them would report 5 of 5 and mislead exactly the buyer it exists
// to be honest with.
export const kitList = () => ({ kits: kits.kits(), total: kits.total(), wired: kits.wired() });
export const deviceList = () => ({ devices: devices.devices() });
export const targetList = () => ({ targets: targets.targets() });
