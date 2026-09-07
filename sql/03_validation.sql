-- NovaHealth PostgreSQL portfolio project
-- Data quality and integrity validation
--
-- Run after sql/02_seed.sql has completed successfully.

-- Summary queries should match the expected dataset counts.
-- Integrity queries should return zero invalid rows.


/* TABLE ROW COUNTS */

    -- all tables
	SELECT
		'customers' AS table_name,
		COUNT(*) AS row_count
	FROM customers

UNION ALL
	SELECT
		'plans' AS table_name,
		COUNT(*)
	FROM plans

UNION ALL
	SELECT
		'subscriptions' AS table_name,
		COUNT(*)
	FROM subscriptions

UNION ALL
	SELECT
		'intakes' AS table_name,
		COUNT(*)
	FROM intakes

UNION ALL
	SELECT
		'appointments' AS table_name,
		COUNT(*)
	FROM appointments

UNION ALL
	SELECT
		'payments' AS table_name,
		COUNT(*)
	FROM payments

UNION ALL
	SELECT
		'refunds' AS table_name,
		COUNT(*)
	FROM refunds

UNION ALL
	SELECT
		'subscription_events' AS table_name,
		COUNT(*)
	FROM subscription_events;


/* CUSTOMERS */

    -- customers summary
SELECT
	COUNT(*) AS total_customer_count,
	MIN(signup_date) AS earliest_signup_date,
	MAX(signup_date) AS latest_signup_date,
	COUNT(DISTINCT state_code) AS state_code_count,
	COUNT(DISTINCT acquisition_channel) AS acquisition_channel_count,
	COUNT(DISTINCT gender) AS gender_values_count
FROM customers;

    -- customers data integrity summary
SELECT
	*
FROM customers

WHERE
		(gender IS NULL
				OR gender NOT IN ('M', 'F'))
	OR
		(signup_date IS NULL
				OR signup_date > DATE '2026-09-01')
	OR
		(state_code IS NULL
				OR LENGTH(state_code) != 2)
	OR
		(acquisition_channel IS NULL
				OR acquisition_channel NOT IN ('organic', 'referral', 'google_ads', 'meta'));


/* PLANS */

    -- plans summary
SELECT
	plan_name,
	monthly_price,
	is_available
FROM plans
ORDER BY monthly_price;

    -- duplicates validation
SELECT
	plan_name,
	COUNT(*) AS plan_count
FROM plans
GROUP BY plan_name
HAVING COUNT(*) > 1;

/* SUBSCRIPTIONS */

    -- subscription status summary
SELECT
	subscription_status,
	COUNT(*) AS subscription_count
FROM subscriptions
GROUP BY subscription_status
ORDER BY subscription_status;

    -- subscription status integrity summary
SELECT
	subscription_id,
	subscription_status,
	selected_at,
	activated_at,
	ended_at
FROM subscriptions
WHERE
	   (subscription_status = 'pending'
			AND (activated_at IS NOT NULL
				OR ended_at IS NOT NULL)
            )
	OR (subscription_status = 'active'
			AND (activated_at IS NULL
				OR ended_at IS NOT NULL)
            )
	OR (subscription_status IN ('cancelled', 'completed')
			AND (activated_at IS NULL
				OR ended_at IS NULL)
            )
	OR (subscription_status = 'rejected'
			AND (activated_at IS NOT NULL
				OR ended_at IS NULL)
            );


/* INTAKES */

	-- activated subscriptions vs intakes check
SELECT
	s.subscription_id,
	s.subscription_status,
	s.activated_at,
	i.intake_id,
	i.intake_status,
	i.completed_at
FROM subscriptions s
LEFT JOIN intakes i
	ON s.subscription_id = i.subscription_id
WHERE s.activated_at IS NOT NULL
	AND
	(i.intake_id IS NULL
	OR i.intake_status IS DISTINCT FROM 'completed'
	OR i.completed_at IS NULL
	OR i.completed_at >= s.activated_at);


	-- intake status integrity validation
SELECT
	i.subscription_id,
    i.intake_status,
    s.selected_at,
    i.started_at,
    i.completed_at
FROM intakes i
JOIN subscriptions s
	ON i.subscription_id = s.subscription_id
WHERE
	(i.intake_status = 'completed'
		AND (i.started_at IS NULL
			OR i.completed_at IS NULL))
	OR (i.intake_status IN ('pending', 'expired')
		AND i.completed_at IS NOT NULL)
	OR (i.started_at IS NOT NULL
		AND i.started_at < s.selected_at);

    -- intake vs rejection validation
SELECT
    COUNT(*) FILTER (
        WHERE s.subscription_status = 'rejected'
          AND i.intake_status = 'completed'
          AND i.completed_at >= s.ended_at
    ) AS completed_intake_after_rejection,

    COUNT(*) FILTER (
        WHERE s.subscription_status = 'rejected'
          AND i.intake_status = 'expired'
          AND i.started_at >= s.ended_at
    ) AS expired_intake_started_after_rejection

FROM subscriptions AS s
JOIN intakes AS i
    ON i.subscription_id = s.subscription_id;


/* APPOINTMENTS */

    -- appointment status integrity validation
SELECT
	appointment_id,
	subscription_id,
	appointment_type,
	appointment_status,
	eligibility_result,
	scheduled_at,
	completed_at
FROM appointments
WHERE
	(appointment_status = 'completed'
		AND completed_at IS NULL)
	OR
	(appointment_status <> 'completed'
		AND completed_at IS NOT NULL)
	OR
	(appointment_status = 'completed'
		AND appointment_type = 'initial_appt'
			AND eligibility_result IS NULL)
	OR
	(appointment_status <> 'completed'
		AND appointment_type = 'initial_appt'
			AND eligibility_result IS NOT NULL)
	OR (appointment_type = 'follow_up'
			AND eligibility_result IS NOT NULL);

    -- appointments status summary
SELECT
    appointment_status,
    eligibility_result,
    COUNT(*)
FROM appointments
GROUP BY
    appointment_status,
    eligibility_result
ORDER BY
    appointment_status,
    eligibility_result;

    -- follow-up eligibility summary
SELECT
    subscription_status,
    COUNT(*) AS eligible_for_follow_up
FROM subscriptions
WHERE activated_at IS NOT NULL
  AND COALESCE(
        ended_at,
        TIMESTAMP '2026-09-01 23:59:59'
      ) >= activated_at + INTERVAL '30 days'
GROUP BY subscription_status
ORDER BY subscription_status;

	-- appointments timeline validation

SELECT
	a.subscription_id,
	a.appointment_id,
	a.appointment_type,
	a.appointment_status,
	a.completed_at AS appointment_completed_ts,
	a.scheduled_at,
	s.activated_at,
	s.ended_at,
	i.intake_id,
	i.intake_status,
	i.completed_at AS intake_completed_ts
FROM subscriptions s
JOIN appointments a
	ON s.subscription_id = a.subscription_id
LEFT JOIN intakes i
	ON a.subscription_id = i.subscription_id
WHERE (a.appointment_type = 'initial_appt'
	AND (i.intake_id IS NULL
		OR i.intake_status IS DISTINCT FROM 'completed'))
	OR (a.appointment_type = 'initial_appt' AND a.appointment_status = 'completed'
		AND a.completed_at <= i.completed_at)
	OR (a.appointment_type = 'follow_up' AND s.activated_at IS NULL)
	OR (a.appointment_type = 'follow_up' AND a.scheduled_at < s.activated_at + INTERVAL '30 days')
	OR (a.scheduled_at > (COALESCE(s.ended_at, TIMESTAMP '2026-09-01 23:59:59')));


/* PAYMENTS */

    -- payments integrity summary
SELECT
	pmt.payment_id,
	sub.subscription_id,
	pmt.payment_status,
	pmt.payment_type,
	pmt.payment_date,
	pmt.amount,
	pns.monthly_price,
	sub.selected_at,
	sub.ended_at
FROM payments pmt
JOIN subscriptions sub
	ON pmt.subscription_id = sub.subscription_id
JOIN plans pns
	ON sub.plan_id = pns.plan_id
WHERE
		pmt.payment_date IS NULL
	OR
		pmt.amount IS DISTINCT FROM pns.monthly_price
	OR
		pmt.payment_date < sub.selected_at
	OR
		pmt.payment_date > COALESCE(sub.ended_at, TIMESTAMP '2026-09-01 23:59:59')
	OR
		(pmt.payment_type = 'initial' AND pmt.payment_status <> 'successful');

    -- initial appointments vs payments validation
SELECT
	a.subscription_id,
	COUNT(DISTINCT p.payment_id) AS initial_payment_count
FROM appointments a
LEFT JOIN payments p
	ON a.subscription_id = p.subscription_id
	AND p.payment_type = 'initial'
WHERE a.appointment_type = 'initial_appt'
GROUP BY a.subscription_id
HAVING COUNT(DISTINCT p.payment_id) <> 1;

    -- renewal payments consistency

WITH initial_payments AS (
	SELECT
		subscription_id,
		MIN(payment_date) AS initial_date
	FROM payments
	WHERE payment_type = 'initial'
	GROUP BY subscription_id
	)

SELECT
	rp.subscription_id,
	rp.payment_id,
	ip.initial_date,
	rp.payment_date AS renewal_date
FROM payments rp
LEFT JOIN initial_payments ip
	ON rp.subscription_id = ip.subscription_id
WHERE rp.payment_type = 'renewal'
	AND (ip.initial_date IS NULL
		OR rp.payment_date <= ip.initial_date
		);

    -- payments status summary
SELECT
    payment_type,
    payment_status,
    COUNT(*),
    SUM(amount) AS total_amount
FROM payments
GROUP BY payment_type, payment_status;

/* REFUNDS */

	-- refunds integrity validation
SELECT
	r.refund_id,
	r.refund_status,
	r.refund_reason,
	r.refund_amount,
	r.processed_at,
	p.payment_id,
	p.payment_status,
	p.amount,
	p.payment_date
FROM refunds r
LEFT JOIN payments p
	ON r.payment_id = p.payment_id
WHERE p.payment_id IS NULL
	OR r.refund_amount > p.amount
	OR r.processed_at < p.payment_date
	OR (r.refund_status = 'completed'
		AND p.payment_status IS DISTINCT FROM 'successful');

	-- refunds summary
SELECT
	refund_reason,
	refund_status,
	COUNT(*) AS refund_count,
	SUM(refund_amount) AS total_refund_amount
FROM refunds
GROUP BY refund_reason, refund_status
ORDER BY refund_reason, refund_status;

/* SUBSCRIPTION EVENTS */

	-- event reason integrity
SELECT
	event_id,
	subscription_id,
	event_type,
	event_reason,
	event_timestamp
FROM subscription_events
WHERE 	(event_type IN ('selected',
						'activated',
						'treatment_started',
						'treatment_completed')
			AND event_reason IS NOT NULL)

		OR (event_type = 'rejected'
			AND (event_reason IS NULL
				OR event_reason NOT IN ('intake_expired',
										'appointment_no_show',
										'not_eligible')))
		OR (event_type = 'cancelled'
			AND (event_reason IS NULL
				OR event_reason NOT IN ('patient_request',
										'side_effects',
										'not_satisfied',
										'no_longer_needed',
										'other')));

    -- subscription lifecycle summary
SELECT
	s.subscription_status,
	COUNT(DISTINCT s.subscription_id) AS total_count,
	COUNT(DISTINCT s.subscription_id) FILTER (
		WHERE e.event_type = 'selected'
	) AS selected_events,
	COUNT(DISTINCT s.subscription_id) FILTER(
		WHERE e.event_type = 'activated'
	) AS activated_events,
	COUNT(DISTINCT s.subscription_id) FILTER (
		WHERE e.event_type = 'treatment_started'
	) AS treatment_started_events,
	COUNT(DISTINCT s.subscription_id) FILTER (
		WHERE e.event_type = 'rejected'
	) AS rejected_events,
	COUNT(DISTINCT s.subscription_id) FILTER (
		WHERE e.event_type = 'cancelled'
	) AS cancelled_events,
	COUNT(DISTINCT s.subscription_id) FILTER (
		WHERE e.event_type = 'treatment_completed'
	) AS treatment_completed_events
FROM subscriptions s
LEFT JOIN subscription_events e
	ON s.subscription_id = e.subscription_id
GROUP BY subscription_status;

    -- duplicates validation
SELECT
	subscription_id,
	event_type,
	COUNT(*) AS event_count
FROM subscription_events
GROUP BY subscription_id, event_type
HAVING COUNT(*) > 1;

    -- chronology validation
WITH event_timeline AS (
	SELECT
		s.subscription_id,
		MAX(e.event_timestamp) FILTER(
			WHERE e.event_type = 'selected'
		) AS selected_at,
		MAX(e.event_timestamp) FILTER(
			WHERE e.event_type = 'activated'
		) AS activated_at,
		MAX(e.event_timestamp) FILTER(
			WHERE e.event_type = 'treatment_started'
		) AS treatment_started_at,
		MAX(e.event_timestamp) FILTER(
			WHERE e.event_type = 'rejected'
		) AS rejected_at,
		MAX(e.event_timestamp) FILTER(
			WHERE e.event_type = 'cancelled'
		) AS cancelled_at,
		MAX(e.event_timestamp) FILTER(
			WHERE e.event_type = 'treatment_completed'
		) AS treatment_completed_at
	FROM subscriptions s
	LEFT JOIN subscription_events e
		ON e.subscription_id = s.subscription_id
	GROUP BY s.subscription_id
	)

SELECT
	*
FROM event_timeline
WHERE
	activated_at <= selected_at OR
	rejected_at <= selected_at OR
	treatment_started_at <= activated_at OR
	cancelled_at <= treatment_started_at OR
	treatment_completed_at <= treatment_started_at;

    -- source timestamp consistency
  SELECT
	e.subscription_id,
	e.event_type,
	e.event_timestamp,
	s.selected_at,
	s.activated_at,
	s.ended_at
FROM subscription_events e
LEFT JOIN subscriptions s
	ON e.subscription_id = s.subscription_id
WHERE
	(e.event_type = 'selected' AND e.event_timestamp IS DISTINCT FROM s.selected_at) OR
	(e.event_type = 'activated' AND e.event_timestamp IS DISTINCT FROM s.activated_at) OR
	(e.event_type = 'rejected' AND e.event_timestamp IS DISTINCT FROM s.ended_at) OR
	(e.event_type = 'cancelled' AND e.event_timestamp IS DISTINCT FROM s.ended_at) OR
	(e.event_type = 'treatment_completed' AND e.event_timestamp IS DISTINCT FROM s.ended_at);
