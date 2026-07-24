// The ELO ladder fed to Maia-3 as a batch dimension: one inference over the
// whole ladder returns a per-rung policy + WDL, which is what the
// moves-by-rating chart plots. 600..2600 step 100 (21 rungs) matches
// maiachess.com's displayed range. The behaviorally-validated band (per our
// calibration spike + flawchess's 151-01 sweep) is 1100..2000; the extremes
// are extrapolation the model still produces, so we surface them rather than
// truncate the axis.

const MAIA_ELO_LADDER_MIN = 600;
const MAIA_ELO_LADDER_MAX = 2600;
const MAIA_ELO_LADDER_STEP = 100;

export const MAIA_ELO_LADDER: readonly number[] = Array.from(
	{ length: (MAIA_ELO_LADDER_MAX - MAIA_ELO_LADDER_MIN) / MAIA_ELO_LADDER_STEP + 1 },
	(_, i) => MAIA_ELO_LADDER_MIN + i * MAIA_ELO_LADDER_STEP,
);
