// PipelineFacade — build run, findings and the release triple.
import * as pipeline from '../repositories/pipeline_repository.js';

export const run      = () => ({ log: pipeline.log() });
export const findings = () => ({ findings: pipeline.findings(), finding: pipeline.findings()[0] });
export const release  = () => ({ release: pipeline.release() });
