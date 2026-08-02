/* =====================================================================
   Q4: Geographic Concentration Risk
   Which states carry the highest loan exposure, and do those same
   states carry higher-than-average default rates?

   METHOD:
   - Exposure = current live book (out_prncp), same definition as Q3's
     EAD — answers "where is money at stake right now," not historical
     origination volume.
   - Default rate (PD) = terminal loans only (Charged Off/Default +
     Fully Paid), same censoring logic as Q3, grouped by state.
   - Overall portfolio PD computed via window function so each state's
     rate can be compared against the true blended average, not an
     unweighted average-of-state-rates (which would let tiny states
     distort the benchmark).
   - "Concentration risk" flag = state is in the top 10 by dollar
     exposure AND has an above-average default rate. Being large is
     not itself risk; being large AND worse-than-average is.

   ASSUMPTION: states with under ~2,000 terminal loans are flagged as
   statistically unreliable and excluded from the "riskiest states"
   narrative — a rate built on a few hundred loans swings on a handful
   of defaults and shouldn't be presented with the same confidence as
   CA's 196,853-loan sample.
   ===================================================================== */

WITH state_exposure AS (
    SELECT
        dg.addr_state,
        SUM(f.out_prncp) AS total_ead
    FROM lc.fact_loan f
    JOIN lc.dim_geography dg ON f.geo_key = dg.geo_key
    WHERE f.loan_status IN (
        'Current', 'In Grace Period',
        'Late (16-30 days)', 'Late (31-120 days)'
    )
    GROUP BY dg.addr_state
),

state_pd AS (
    SELECT
        dg.addr_state,
        COUNT(*) AS terminal_loan_count,
        SUM(CASE WHEN f.loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'
        ) THEN 1 ELSE 0 END) AS default_count,
        SUM(CASE WHEN f.loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'
        ) THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pd
    FROM lc.fact_loan f
    JOIN lc.dim_geography dg ON f.geo_key = dg.geo_key
    WHERE f.loan_status IN (
        'Charged Off', 'Default',
        'Does not meet the credit policy. Status:Charged Off',
        'Fully Paid', 'Does not meet the credit policy. Status:Fully Paid'
    )
    GROUP BY dg.addr_state
),

combined AS (
    SELECT
        e.addr_state,
        e.total_ead,
        RANK() OVER (ORDER BY e.total_ead DESC) AS exposure_rank,
        p.terminal_loan_count,
        p.default_count,
        p.pd,
        AVG(p.pd) OVER () AS unweighted_avg_pd,          -- reference only, see note
        SUM(p.default_count) OVER () * 1.0
            / SUM(p.terminal_loan_count) OVER () AS portfolio_weighted_pd
    FROM state_exposure e
    JOIN state_pd p ON e.addr_state = p.addr_state
)

SELECT
    addr_state,
    exposure_rank,
    terminal_loan_count,
    CAST(ROUND(total_ead, 2) AS DECIMAL(14,2)) AS total_ead,
    CAST(ROUND(pd * 100, 2) AS DECIMAL(5,2)) AS pd_pct,
    CAST(ROUND(portfolio_weighted_pd * 100, 2) AS DECIMAL(5,2)) AS portfolio_avg_pd_pct,
    CASE WHEN terminal_loan_count < 2000 THEN 'LOW SAMPLE - CAUTION' ELSE '' END AS sample_flag,
    CASE
        WHEN exposure_rank <= 10 AND pd > portfolio_weighted_pd
        THEN 'CONCENTRATION RISK'
        ELSE ''
    END AS risk_flag
FROM combined
ORDER BY exposure_rank;

/* =====================================================================
   FINDINGS

   - Portfolio-wide (weighted) default rate is ~20.0%. This is the
     correct benchmark to compare states against — not a simple
     average of the 50 state rates, which would let tiny states like
     IA (14 loans) pull the benchmark around meaninglessly.
   - The two largest exposure states, CA (#1, ~$1.26B) and TX (#2,
     ~$814M), both run BELOW the portfolio average default rate
     (19.63% and 19.84%). Being the biggest states in the book is not
     itself a red flag — their credit quality is in line with or
     slightly better than the portfolio overall.
   - NY (#3 exposure, ~$762M) and FL (#4 exposure, ~$672M) are the
     real concentration risk: both carry large dollar exposure AND
     above-average default rates (22.05% and 21.50% vs ~20.0% avg).
     These two states combine size and elevated risk — the clearest
     "concentration risk" finding in the dataset.
   - NJ (#6 exposure) also crosses into above-average default
     territory (21.12%), a secondary concentration flag behind NY/FL.
   - The states with the single highest default rates in the entire
     portfolio — MS (26.11%), NE (25.22%), AR (24.11%) — carry
     comparatively tiny dollar exposure (none in the top 20 by EAD).
     High risk rate there doesn't translate to large dollar risk for
     the portfolio; don't conflate "riskiest by rate" with "riskiest
     by dollars" in the write-up.
   - IA must be excluded from any state-level claim — 14 terminal
     loans is not a usable sample size at any grain.
   ===================================================================== */
