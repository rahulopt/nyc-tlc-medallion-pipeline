-- =============================================================
-- NYC TLC Medallion Pipeline — Athena Gold Layer Queries
-- Database: nyc-tlc_dev_db
-- =============================================================


-- =============================================================
-- SETUP — Run this first to set the database context
-- =============================================================

-- NOTE: In Athena console, select "nyc-tlc_dev_db" from
-- the database dropdown before running queries below.


-- =============================================================
-- TABLE 1: daily_trip_summary
-- =============================================================

-- Q1. Total trips and revenue per day (Jan 2024)
SELECT
    pickup_date,
    total_trips,
    total_revenue,
    avg_fare,
    avg_tip,
    avg_distance,
    avg_duration_minutes
FROM daily_trip_summary
WHERE pickup_year = 2024
  AND pickup_month = 1
ORDER BY pickup_date;


-- Q2. Top 5 highest revenue days
SELECT
    pickup_date,
    total_trips,
    total_revenue
FROM daily_trip_summary
ORDER BY total_revenue DESC
LIMIT 5;


-- Q3. Monthly revenue summary
SELECT
    pickup_year,
    pickup_month,
    SUM(total_trips)    AS total_trips,
    ROUND(SUM(total_revenue), 2) AS total_revenue,
    ROUND(AVG(avg_fare), 2)      AS avg_daily_fare
FROM daily_trip_summary
GROUP BY pickup_year, pickup_month
ORDER BY pickup_year, pickup_month;


-- =============================================================
-- TABLE 2: hourly_trip_summary
-- =============================================================

-- Q4. Busiest hours of the day (peak hour analysis)
SELECT
    pickup_hour,
    SUM(total_trips)              AS total_trips,
    ROUND(AVG(avg_fare), 2)       AS avg_fare,
    ROUND(AVG(avg_duration_minutes), 2) AS avg_duration_mins
FROM hourly_trip_summary
WHERE pickup_year = 2024
  AND pickup_month = 1
GROUP BY pickup_hour
ORDER BY total_trips DESC;


-- Q5. Morning vs Evening rush comparison
SELECT
    CASE
        WHEN pickup_hour BETWEEN 7  AND 9  THEN 'Morning Rush (7-9am)'
        WHEN pickup_hour BETWEEN 17 AND 19 THEN 'Evening Rush (5-7pm)'
        WHEN pickup_hour BETWEEN 0  AND 5  THEN 'Late Night (12-5am)'
        ELSE 'Other Hours'
    END AS time_slot,
    SUM(total_trips)        AS total_trips,
    ROUND(AVG(avg_fare), 2) AS avg_fare
FROM hourly_trip_summary
GROUP BY
    CASE
        WHEN pickup_hour BETWEEN 7  AND 9  THEN 'Morning Rush (7-9am)'
        WHEN pickup_hour BETWEEN 17 AND 19 THEN 'Evening Rush (5-7pm)'
        WHEN pickup_hour BETWEEN 0  AND 5  THEN 'Late Night (12-5am)'
        ELSE 'Other Hours'
    END
ORDER BY total_trips DESC;


-- =============================================================
-- TABLE 3: location_trip_summary
-- =============================================================

-- Q6. Top 10 busiest pickup locations
SELECT
    "pulocationid",
    total_trips,
    avg_fare,
    avg_distance,
    avg_tip,
    total_revenue
FROM location_trip_summary
ORDER BY total_trips DESC
LIMIT 10;


-- Q7. Top 10 highest revenue locations
SELECT
    "pulocationid",
    total_trips,
    total_revenue,
    avg_fare
FROM location_trip_summary
ORDER BY total_revenue DESC
LIMIT 10;


-- Q8. Long distance hotspots (avg distance > 5 miles)
SELECT
    "pulocationid",
    total_trips,
    avg_distance,
    avg_fare,
    avg_duration_minutes
FROM location_trip_summary
WHERE avg_distance > 5.0
ORDER BY avg_distance DESC
LIMIT 10;


-- =============================================================
-- TABLE 4: payment_type_summary
-- =============================================================

-- Q9. Payment type breakdown
-- payment_type: 1=Credit Card, 2=Cash, 3=No Charge, 4=Dispute
SELECT
    CASE payment_type
        WHEN 1 THEN 'Credit Card'
        WHEN 2 THEN 'Cash'
        WHEN 3 THEN 'No Charge'
        WHEN 4 THEN 'Dispute'
        ELSE 'Unknown'
    END AS payment_method,
    total_trips,
    avg_fare,
    avg_tip,
    total_revenue,
    ROUND(
        CAST(total_trips AS DOUBLE) * 100.0 /
        SUM(total_trips) OVER (), 2
    ) AS trip_percentage
FROM payment_type_summary
ORDER BY total_trips DESC;


-- Q10. Credit card vs Cash tip comparison
SELECT
    CASE payment_type
        WHEN 1 THEN 'Credit Card'
        WHEN 2 THEN 'Cash'
        ELSE 'Other'
    END AS payment_method,
    avg_tip,
    avg_fare,
    ROUND(avg_tip / NULLIF(avg_fare, 0) * 100, 2) AS tip_percentage
FROM payment_type_summary
WHERE payment_type IN (1, 2)
ORDER BY payment_type;


-- =============================================================
-- BONUS — Cross-table analysis
-- =============================================================

-- Q11. Overall pipeline stats (sanity check)
SELECT
    'daily_trip_summary'    AS gold_table,
    COUNT(*)                AS row_count
FROM daily_trip_summary

UNION ALL

SELECT
    'hourly_trip_summary',
    COUNT(*)
FROM hourly_trip_summary

UNION ALL

SELECT
    'location_trip_summary',
    COUNT(*)
FROM location_trip_summary

UNION ALL

SELECT
    'payment_type_summary',
    COUNT(*)
FROM payment_type_summary;
