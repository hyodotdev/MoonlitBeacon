const FORBIDDEN_PHASE_TERM = /\bphase\b/i;

export function containsForbiddenPhaseTerm(line) {
  return FORBIDDEN_PHASE_TERM.test(line);
}
