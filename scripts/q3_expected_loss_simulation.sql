/* =====================================================================
   Q3: Portfolio Expected Loss Simulation (PD x LGD x EAD)
   Segment the portfolio by grade, estimate PD, LGD, and EAD per
   segment, multiply, roll up to total expected portfolio loss.

   METHOD:
   - PD  = historical realized default rate per grade, computed ONLY on
     terminal loans (Charged Off/Default + Fully Paid). Active loans
     are excluded from PD's denominator — their outcome isn't known
     yet, so including them would bias PD downward (same censoring
     principle used in the Q2 vintage curve).
   - LGD = pooled/weighted loss rate per grade, computed ONLY on the
     defaulted subset. Pooled (sum of losses / sum of exposure) rather
     than an average of per-loan ratios, so large-exposure loans are
     weighted correctly instead of a few small/unusual loans skewing
     the segment number.
   - EAD = current outstanding principal on the LIVE book (Current /
     Grace Period / Late), NOT the historical EAD-at-default used
     inside the LGD calc. These are two different populations: LGD's
     EAD looks backward at loans that already defaulted; this EAD
     looks at what's still at risk today. Applying historical PD/LGD
     to today's live exposure is the standard way to project forward
     expected loss on a book that hasn't fully played out yet.
   - Expected Loss (segment) = PD x LGD x total EAD for that segment.
   - Portfolio EL = SUM(segment EL) across all grades.

   KEY ASSUMPTIONS:
   - Net recovery = recoveries - collection_recovery_fee, i.e. modeling
     recovery net of what the collection agency keeps (net-to-lender).
     If gross recovery is wanted instead, drop the fee subtraction.
   - EAD-at-default (used only inside LGD) = funded_amnt -
     total_rec_prncp: original loan amount minus principal already
     paid back before charge-off.
   - grade_key in this schema is keyed at SUB-GRADE level (A1-A5, etc).
     All three CTEs join to dim_grade and GROUP BY the letter grade
     explicitly — grouping by grade_key alone before joining would
     silently return 5 rows per letter grade instead of 1.
   ===================================================================== */

WITH pd_calc AS (
    -- PD per letter grade: defaults / (defaults + fully paid),
    -- terminal loans only.
    SELECT
        dg.grade,
        SUM(CASE WHEN f.loan_status IN (
            'Charged Off',
            'Default',
            'Does not meet the credit policy. Status:Charged Off'
        ) THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pd
    FROM lc.fact_loan f
    JOIN lc.dim_grade dg ON f.grade_key = dg.grade_key
    WHERE f.loan_status IN (
        'Charged Off',
        'Default',
        'Does not meet the credit policy. Status:Charged Off',
        'Fully Paid',
        'Does not meet the credit policy. Status:Fully Paid'
    )
    GROUP BY dg.grade
),

lgd_calc AS (
    -- LGD per letter grade: 1 - (pooled net recovery / pooled EAD),
    -- defaulted loans only.
    SELECT
        dg.grade,
        1.0 - SUM(f.recoveries - f.collection_recovery_fee) * 1.0
              / NULLIF(SUM(f.funded_amnt - f.total_rec_prncp), 0) AS lgd
    FROM lc.fact_loan f
    JOIN lc.dim_grade dg ON f.grade_key = dg.grade_key
    WHERE f.loan_status IN (
        'Charged Off',
        'Default',
        'Does not meet the credit policy. Status:Charged Off'
    )
    GROUP BY dg.grade
),

ead_calc AS (
    -- Current outstanding exposure per letter grade, live book only.
    SELECT
        dg.grade,
        SUM(f.out_prncp) AS total_ead,
        COUNT(*) AS active_loan_count
    FROM lc.fact_loan f
    JOIN lc.dim_grade dg ON f.grade_key = dg.grade_key
    WHERE f.loan_status IN (
        'Current',
        'In Grace Period',
        'Late (16-30 days)',
        'Late (31-120 days)'
    )
    GROUP BY dg.grade
),

segment_el AS (
    SELECT
        e.grade,
        p.pd,
        l.lgd,
        e.total_ead,
        e.active_loan_count,
        p.pd * l.lgd * e.total_ead AS segment_expected_loss
    FROM ead_calc e
    JOIN pd_calc p ON e.grade = p.grade
    JOIN lgd_calc l ON e.grade = l.grade
)

-- Segment-level output
SELECT
    grade,
    CAST(ROUND(pd, 4) AS DECIMAL(6,4)) AS pd,
    CAST(ROUND(lgd, 4) AS DECIMAL(6,4)) AS lgd,
    CAST(ROUND(total_ead, 2) AS DECIMAL(14,2)) AS total_ead,
    active_loan_count,
    CAST(ROUND(segment_expected_loss, 2) AS DECIMAL(14,2)) AS segment_expected_loss
FROM segment_el
ORDER BY grade;

-- Portfolio-level rollup (run separately, or UNION into a summary row)
-- SELECT
--     CAST(SUM(segment_expected_loss) AS DECIMAL(14,2)) AS total_portfolio_expected_loss,
--     CAST(SUM(total_ead) AS DECIMAL(14,2)) AS total_portfolio_ead,
--     CAST(SUM(segment_expected_loss) / SUM(total_ead) AS DECIMAL(6,4)) AS blended_el_rate
-- FROM segment_el;

/* =====================================================================
   FINDINGS

   - PD climbs steeply and monotonically by grade: 6.0% (A) up to
     49.7% (G) — the strongest, cleanest signal in this whole model.
     No sample-size caveat needed; even G-grade has 9,300+ terminal
     loans behind it.
   - LGD is nearly flat across grades (~90-92%), and actually runs
     slightly HIGHER for A-grade than for the riskiest grades. This is
     counterintuitive and needs a sentence of explanation, not a
     silent pass: worse-grade loans tend to default earlier (less
     principal amortized off before charge-off), so despite being
     "riskier" they aren't necessarily worse on loss-given-default —
     PD and LGD are answering different questions and don't have to
     move together.
   - EAD (live book) is heavily concentrated in B and C grades
     (~$2.7B and ~$2.85B outstanding respectively) — the middle of
     the credit spectrum, not the extremes. G-grade, despite the
     highest PD, carries only ~$40M of live exposure — a small
     fraction of the book.
   - Net effect on expected loss: C-grade contributes the single
     largest share of portfolio expected loss, not G — because EL is
     driven by PD x LGD x EXPOSURE, and C's sheer volume of
     outstanding balance outweighs G's much higher default rate on a
     tiny exposure base. This is the headline finding: the riskiest
     grade by PD is not the biggest driver of dollar losses; exposure
     concentration matters just as much as risk rate.
   - Blended portfolio-wide expected loss rate is ~17% of total live
     exposure — i.e. roughly 1 in 6 outstanding dollars on the book
     is expected to eventually be lost, under these PD/LGD assumptions.
   - Optional deeper cut: PD varies meaningfully even within a single
     letter grade at the sub-grade level (e.g. A-grade sub-grades
     range ~3%-8%) — letter grade alone loses resolution that
     sub-grade captures. Worth a one-line mention if presenting this
     to show awareness of the schema's full granularity.
   ===================================================================== */
