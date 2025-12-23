-- ============================================================================
-- DATA COMPLETENESS ANALYSIS
-- ============================================================================
-- PURPOSE: Evaluate how well our three core data systems (Claims, HIE, and 
--          Authorizations) are capturing inpatient events. Data gaps mean
--          missed revenue, blind spots in care coordination, and compliance risk.
--
-- BUSINESS CONTEXT: Healthcare orgs pull data from multiple systems that don't
--          always talk to each other. This analysis helps identify which offices
--          have integration problems and where we're losing visibility.
--
-- OUTPUT: Capture rates by office and match type, showing where data exists
--         in one system but not others.
-- ============================================================================

-- STEP 1: BUILD BASE EVENT LIST
-- Start with all inpatient events and try to match them to their corresponding
-- records in other systems. We use LEFT JOINs because we want to KEEP events
-- even if they're missing from Claims, HIE, or Auth - those gaps are exactly
-- what we're trying to find!

WITH base_events AS (
    SELECT 
        ie.event_id,
        ie.patient_id,
        
        -- Assign office from census data; 'UNASSIGNED' flags data quality issues
        -- (patients without office attribution need investigation)
        COALESCE(census.office_name, 'UNASSIGNED') AS office_name,
        
        -- These IDs will be NULL if the event wasn't captured in that system
        -- That's intentional - we'll use NULL checks to categorize match types
        ie.claim_id,
        ie.hie_encounter_id,
        auth.authorization_id
        
    FROM clinical.inpatient_events ie
    
    -- Match to census using patient + month (patients can transfer between offices)
    LEFT JOIN patient_census census
        ON ie.patient_id = census.patient_id
        AND DATE_FORMAT(ie.admit_date, 'yyyy-MM') = census.month_year
    
    -- Authorization matching uses date overlap logic:
    -- The auth window (admission_date to discharge_date) must overlap with
    -- the actual event dates. This catches auths that span multiple days.
    LEFT JOIN authorization_data auth
        ON ie.patient_id = auth.patient_id
        AND ie.admit_date <= COALESCE(auth.discharge_date, auth.admission_date)
        AND auth.admission_date <= ie.discharge_date
        
    -- Filter to recent data (adjust date as needed for your analysis window)
    WHERE ie.admit_date >= '2025-01-01'
),

-- STEP 2: CATEGORIZE EACH EVENT BY WHICH SYSTEMS CAPTURED IT
-- This is the heart of the analysis - we label each event based on where
-- data exists. 'full-match' is ideal; 'auth-only' is noise (auth exists
-- but no actual event occurred).

categorized AS (
    SELECT *,
        -- Classify match type based on which system IDs are present
        -- Order matters here - check most complete matches first
        CASE 
            WHEN claim_id IS NOT NULL AND hie_encounter_id IS NOT NULL 
                 AND authorization_id IS NOT NULL THEN 'full-match'      -- Best case: all 3 systems
            WHEN claim_id IS NOT NULL AND authorization_id IS NOT NULL THEN 'claims-auth'  -- Missing HIE
            WHEN hie_encounter_id IS NOT NULL AND authorization_id IS NOT NULL THEN 'hie-auth'  -- Missing Claims (revenue risk!)
            WHEN claim_id IS NOT NULL THEN 'claims-only'                 -- Claims but no auth
            WHEN hie_encounter_id IS NOT NULL THEN 'hie-only'            -- HIE but no auth
            WHEN authorization_id IS NOT NULL THEN 'auth-only'           -- Likely noise/cancelled
            ELSE 'no-match'                                              -- Orphan event (investigate)
        END AS match_type,
        
        -- Binary flags for easy aggregation (1 = captured, 0 = missing)
        -- These let us calculate capture percentages with simple SUM/COUNT
        CASE WHEN claim_id IS NOT NULL THEN 1 ELSE 0 END AS has_claims,
        CASE WHEN hie_encounter_id IS NOT NULL THEN 1 ELSE 0 END AS has_hie,
        CASE WHEN authorization_id IS NOT NULL THEN 1 ELSE 0 END AS has_auth
    FROM base_events
)

-- STEP 3: AGGREGATE AND CALCULATE CAPTURE RATES
-- Final output shows capture percentages at multiple levels:
-- - By office + match type (detailed drill-down)
-- - By office (office-level summary)
-- - Overall totals (executive summary)

SELECT 
    office_name,
    match_type,
    COUNT(*) AS event_count,
    
    -- Capture rates as percentages (what % of events have data in each system?)
    ROUND(SUM(has_claims) * 100.0 / COUNT(*), 1) AS claims_capture_pct,
    ROUND(SUM(has_hie) * 100.0 / COUNT(*), 1) AS hie_capture_pct,
    ROUND(SUM(has_auth) * 100.0 / COUNT(*), 1) AS auth_capture_pct
    
FROM categorized

-- GROUPING SETS creates multiple aggregation levels in one query:
-- This is more efficient than running 3 separate queries and UNIONing them
GROUP BY GROUPING SETS (
    (office_name, match_type),  -- Detail: each office's breakdown by match type
    (office_name),               -- Subtotal: each office's overall numbers
    ()                           -- Grand total: org-wide capture rates
)

-- Sort with grand totals last (NULL office_name) for clean reporting
ORDER BY office_name NULLS LAST, match_type;

-- ============================================================================
-- HOW TO READ THE RESULTS:
-- 
-- Look for:
-- 1. Low claims_capture_pct = Revenue leakage (events not being billed)
-- 2. Low hie_capture_pct = Care coordination blind spots
-- 3. High 'auth-only' counts = Noise in authorization data
-- 4. 'UNASSIGNED' office = Patient attribution problems
--
-- Red flags to investigate:
-- - Any office below 80% in claims or HIE capture
-- - Large variance between offices (process inconsistency)
-- - Increasing 'no-match' trends over time
-- ============================================================================
