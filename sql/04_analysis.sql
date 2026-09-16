/* SUBSCRIPTION FUNNEL ANALYSIS */

/* CONVERSION RATES BETWEEN STAGES */

WITH sub_count AS (
	SELECT
		p.plan_id,
		p.plan_name,
		COUNT(DISTINCT s.subscription_id)
			FILTER (WHERE e.event_type = 'selected'
		) AS selected,
		COUNT(DISTINCT s.subscription_id)
			FILTER (WHERE e.event_type = 'activated'
		) AS activated,
		COUNT(DISTINCT s.subscription_id)
			FILTER (WHERE e.event_type = 'treatment_started'
		) AS treatment_started,
		COUNT(DISTINCT s.subscription_id)
			FILTER (WHERE e.event_type = 'treatment_completed'
		) AS treatment_completed,
		COUNT(DISTINCT s.subscription_id)
			FILTER (WHERE e.event_type = 'rejected'
		) AS rejected,
		COUNT(DISTINCT s.subscription_id)
			FILTER (WHERE e.event_type = 'cancelled'
		) AS cancelled
	FROM plans p
	LEFT JOIN subscriptions s
		ON p.plan_id = s.plan_id
	LEFT JOIN subscription_events e
		ON s.subscription_id = e.subscription_id
	GROUP BY p.plan_id, p.plan_name
	)

SELECT
	plan_id,
	plan_name,
	selected,
	activated,
	treatment_started,
	treatment_completed,
	rejected,
	cancelled,
	ROUND(
		100.0 * activated
		/
		NULLIF(selected, 0), 2
	) AS activation_rate,
	ROUND(
		100.0 * treatment_started
		/
		NULLIF(activated, 0), 2
	) AS treatment_start_rate,
	ROUND(
		100.0 * treatment_completed
		/
		NULLIF(treatment_started, 0), 2
	) AS treatment_completion_rate
FROM sub_count
ORDER BY plan_id;

-- The largest proportional decrease is from treatment started to treatment
-- completed across all plans. Completion rates so far range from 12.28% to 16.26%;
-- subscriptions still undergoing treatment may contribute to this gap.

-- Premium plan has the lowest completion rate so far (12.28%).
-- Basic plan has the highest activation rate (79.96%), while Plus plan has
-- the highest treatment start rate among activated subscriptions (99.63%).

/* CANCELLED AND REJECTED SUBSCRIPTIONS */

WITH reason_counts AS (
	SELECT
		event_type,
		event_reason,
		COUNT(DISTINCT subscription_id) AS subscription_count
	FROM subscription_events
	WHERE event_type IN ('rejected', 'cancelled')
	GROUP BY event_type, event_reason
	)

SELECT
	event_type,
	event_reason,
	subscription_count,
	SUM(subscription_count) OVER (
		PARTITION BY event_type
	) AS subscriptions_total,
	ROUND(
		100.0 * subscription_count
		/
		NULLIF(SUM(subscription_count) OVER (
			PARTITION BY event_type), 0), 2
	) AS reason_percentage
FROM reason_counts
ORDER BY event_type ASC, subscription_count DESC;

-- Leading reasons for rejected and cancelled subscriptions:
-- Patient requests account for 30% of cancellations.
-- Ineligibility accounts for 56.67% of rejections.


/* ACQUISITION ANALYSIS */

/* ACTIVATION BY ACQUISITION CHANNEL */

WITH sub_count_by_channel AS (
	SELECT
		c.acquisition_channel,
		COUNT(DISTINCT s.subscription_id) AS selected_subscriptions,
		COUNT(DISTINCT s.subscription_id)
			FILTER (WHERE s.activated_at IS NOT NULL
		) AS activated_subscriptions
	FROM subscriptions s
	JOIN customers c
		ON s.customer_id = c.customer_id
	GROUP BY c.acquisition_channel
	)

SELECT
	acquisition_channel,
	selected_subscriptions,
	activated_subscriptions,
	ROUND(
		100.0 * activated_subscriptions
		/
		NULLIF(selected_subscriptions, 0), 2
	) AS activation_rate
FROM sub_count_by_channel
ORDER BY activation_rate DESC, acquisition_channel;

-- Google Ads has the highest activation rate (82.66%), 5.28 percentage points
-- above Meta. Referral has the most selected subscriptions (254),
-- while Referral and Google Ads tie at 205 activations.

/* TIME FROM SELECTION TO ACTIVATION BY PLAN */

SELECT
	p.plan_id,
	p.plan_name,
	COUNT(DISTINCT s.subscription_id) AS activated_subscriptions,
	ROUND(AVG(
		EXTRACT(EPOCH FROM (activated_at - selected_at)) / 86400.0), 2
	) AS avg_days_to_activation,
	ROUND(MIN(
		EXTRACT(EPOCH FROM (activated_at - selected_at)) / 86400.0), 2
	) AS min_days_to_activation,
	ROUND(MAX(
		EXTRACT(EPOCH FROM (activated_at - selected_at)) / 86400.0), 2
	) AS max_days_to_activation
FROM plans p
JOIN subscriptions s
	ON p.plan_id = s.plan_id
	AND s.activated_at IS NOT NULL
GROUP BY p.plan_id, p.plan_name
ORDER BY avg_days_to_activation;

-- Among subscriptions that activated, Premium had the shortest average wait (3.84 days),
-- followed by Basic (3.95) and Plus (4.01). The gap between Premium and Plus is about
-- four hours, based on the rounded averages.
-- Wait time ranges from 1 to 7 days across all plans.

/* PAYMENT OUTCOMES */

WITH payment_totals AS (
	SELECT
		payment_type,
		payment_status,
		COUNT(*) AS payment_count
	FROM payments
	GROUP BY payment_type, payment_status
	)

SELECT
	payment_type,
	payment_status,
	payment_count,
	SUM(payment_count) OVER (
		PARTITION BY payment_type
	) AS total_payment_by_type,
	ROUND(
		100.0 * payment_count
		/
		NULLIF(SUM(payment_count) OVER (
			PARTITION BY payment_type), 0), 2
	) AS status_percentage
FROM payment_totals
ORDER BY payment_type ASC, payment_count DESC;

-- Among renewal payments, 90.95% were successful, 8.27% failed
-- and 0.78% of renewals are pending at the reporting cutoff.
-- All recorded initial payments were successful.

/* SUCCESSFUL PAYMENTS BY PLAN */

SELECT
	pns.plan_id,
	pns.plan_name,
	COUNT(pay.payment_id) AS successful_payment_count,
	SUM(pay.amount) FILTER (
		WHERE pay.payment_type = 'initial'
	) AS initial_payment_amount,
	SUM(pay.amount) FILTER (
		WHERE pay.payment_type = 'renewal'
	) AS renewal_payment_amount,
	SUM(pay.amount) AS total_payment_amount
FROM plans pns
JOIN subscriptions sub
	ON pns.plan_id = sub.plan_id
JOIN payments pay
	ON sub.subscription_id = pay.subscription_id
	AND pay.payment_status = 'successful'
GROUP BY pns.plan_id, pns.plan_name
ORDER BY total_payment_amount DESC;

-- Total successful payments amount to 592,032.00 before refunds.
-- Plus contributes the largest amount (257,830.00), while Basic has the most
-- successful payments (5,434).

/* REFUND OUTCOMES */

SELECT
	refund_status,
	COUNT(refund_id) AS refund_count,
	SUM(refund_amount) AS total_refund_amount
FROM refunds
GROUP BY refund_status
ORDER BY refund_count DESC;

/* PAYMENTS AFTER REFUNDS BY PLAN */

WITH net_payments AS (
	SELECT
		pns.plan_id,
		pns.plan_name,
		SUM(pay.amount) AS successful_payment_amount,
		COALESCE(SUM(rfn.refund_amount), 0) AS completed_refund_amount,
		(SUM(pay.amount)
			- COALESCE(SUM(rfn.refund_amount), 0)
		) AS net_payment_amount
	FROM plans pns
	JOIN subscriptions sub
		ON pns.plan_id = sub.plan_id
	JOIN payments pay
		ON sub.subscription_id = pay.subscription_id
		AND pay.payment_status = 'successful'
	LEFT JOIN refunds rfn
		ON pay.payment_id = rfn.payment_id
		AND rfn.refund_status = 'completed'
	GROUP BY pns.plan_id, pns.plan_name
	)

SELECT
	plan_id,
	plan_name,
	successful_payment_amount,
	completed_refund_amount,
	net_payment_amount,
	ROUND(
		completed_refund_amount
		/
		NULLIF(successful_payment_amount, 0)* 100.0, 2
	) AS refund_amount_percentage
FROM net_payments
ORDER BY net_payment_amount DESC;

-- Net payment amount totals 587,764.00 after completed refunds.
-- Premium plan has the highest refund amount percentage (1.01%),
-- followed by Basic (0.79%) and Plus (0.48%).

/* EXTREME MONTH-OVER-MONTH SUCCESSFUL PAYMENT CHANGES */

WITH payments_monthly AS (
	SELECT
		DATE_TRUNC('month', payment_date) AS payment_month,
		COUNT(payment_id) AS successful_payment_count,
		SUM(amount) AS successful_payment_amount
	FROM payments
	WHERE payment_status = 'successful'
	GROUP BY payment_month
	),

payments_monthly_change AS (
	SELECT
		payment_month,
		successful_payment_count,
		successful_payment_amount,
		LAG(successful_payment_amount)
			OVER (ORDER BY payment_month
		) AS previous_month_amount
	FROM payments_monthly
	),

mom_payments_change AS (
	SELECT
		payment_month,
		successful_payment_count,
		successful_payment_amount,
		previous_month_amount,
		(
			(successful_payment_amount - previous_month_amount)
			/
			NULLIF(previous_month_amount, 0) * 100.0
		) AS mom_prc_change
	FROM payments_monthly_change
	)

SELECT
	payment_month,
	successful_payment_amount,
	previous_month_amount,
	ROUND(
		mom_prc_change, 2
	) AS mom_percentage_change
FROM mom_payments_change
WHERE mom_prc_change = (
		SELECT MIN(mom_prc_change)
		FROM mom_payments_change
		)
	OR mom_prc_change = (
		SELECT MAX(mom_prc_change)
		FROM mom_payments_change
		)
ORDER BY payment_month;

-- The largest month-over-month increase in successful payment amount was recorded
-- in September 2022: payments rose from 870.00 to 2,089.00,
-- with an increase of 140.11% compared with August 2022, the first observed month,
-- while in August 2026 payments fell from 21,661.00 to 18,129.00, which is the
-- largest month-over-month decrease of 16.31% across all months.

/* JULY AND AUGUST 2026 COMPARISON BY PAYMENT TYPE */

SELECT
	DATE_TRUNC('month', payment_date) AS payment_month,
	payment_type,
	COUNT(payment_id) AS successful_payment_count,
	SUM(amount) AS successful_payment_amount
FROM payments
WHERE payment_status = 'successful'
	AND payment_date >= '2026-07-01'
	AND payment_date < '2026-09-01'
GROUP BY payment_month, payment_type
ORDER BY payment_month, payment_type;

-- Successful renewal counts fell from 411 to 343, while initial counts stayed at 18.
-- The increase in initial payment amounts partially offset the renewal decline,
-- with a 3,532.00 decrease between July and August 2026.

/* JULY AND AUGUST 2026 RENEWAL PAYMENT STATUS */

WITH payment_status_count AS (
	SELECT
		DATE_TRUNC('month', payment_date) AS payment_month,
		payment_status,
		COUNT(payment_id) AS payment_count,
		SUM(amount) AS payment_amount
	FROM payments
	WHERE payment_type = 'renewal'
		AND payment_date >= '2026-07-01'
		AND payment_date < '2026-09-01'
	GROUP BY payment_month, payment_status
	)

SELECT
	payment_month,
	payment_status,
	payment_count,
	ROUND(
		100.0 * payment_count
		/
		NULLIF(SUM(payment_count) OVER (
			PARTITION BY payment_month), 0), 2
	) AS status_percentage,
	payment_amount
FROM payment_status_count
ORDER BY payment_month, payment_status;

-- The successful renewal-payment share fell from 91.74% (20,939.00) in July to
-- 74.73% (17,177.00) in August, which is a decrease of 17.01 percentage points,
-- while 18.30% (4,336.00) of August renewals remained pending.

/* APPOINTMENTS */

/* APPOINTMENT OUTCOMES BY APPOINTMENT TYPE */

WITH appt_counts AS (
	SELECT
		appointment_type,
		appointment_status,
		COUNT(appointment_id) AS appointment_count
	FROM appointments
	GROUP BY appointment_type, appointment_status
	)

SELECT
	appointment_type,
	appointment_status,
	appointment_count,
	SUM(appointment_count) OVER (
		PARTITION BY appointment_type
	) AS appt_count_by_type,
	ROUND(
		100.0 * appointment_count
		/
		NULLIF(SUM(appointment_count) OVER (
				PARTITION BY appointment_type), 0), 2
	) AS status_percentage
FROM appt_counts
ORDER BY appointment_type ASC, appointment_count DESC;

-- Initial appointments have a 92.33% completion share, compared with 85.17% for follow-ups.
-- Follow-ups have a higher no-show share: 9.89%, compared with 1.83% for initial appointments.
-- The 5.84% scheduled initial appointments remain unresolved,
-- so the completed share is not a final success rate.

/* ELIGIBILITY OUTCOMES BY PLAN */

WITH eligibility_outcomes AS (
	SELECT
		p.plan_id,
		p.plan_name,
		COUNT(a.appointment_id) AS completed_initial_appointments,
		COUNT(a.appointment_id) FILTER (
			WHERE a.eligibility_result = 'eligible'
		) AS eligible,
		COUNT(a.appointment_id) FILTER (
			WHERE a.eligibility_result = 'not_eligible'
		) AS not_eligible
	FROM plans p
	JOIN subscriptions s
		ON p.plan_id = s.plan_id
	JOIN appointments a
		ON s.subscription_id = a.subscription_id
		AND a.appointment_type = 'initial_appt'
		AND a.appointment_status = 'completed'
	GROUP BY p.plan_id, p.plan_name
	)

SELECT
	plan_id,
	plan_name,
	completed_initial_appointments,
	eligible,
	not_eligible,
	ROUND(
		100.0 * eligible
		/
		NULLIF(completed_initial_appointments, 0), 2
	) AS eligibility_percentage,
	ROUND(
		100.0 * not_eligible
		/
		NULLIF(completed_initial_appointments, 0), 2
	) AS not_eligible_percentage
FROM eligibility_outcomes
ORDER BY eligibility_percentage DESC;

-- Plus has the highest eligibility percentage (96.04%),
-- while Premium has the lowest (90.00%) and the highest not-eligible percentage (10.00%).

/* TREATMENT DURATION BY PLAN */

WITH ts_by_plan AS (
	SELECT
		p.plan_id,
		p.plan_name,
		se.subscription_id,
		MIN(se.event_timestamp) FILTER (
			WHERE se.event_type = 'treatment_started'
		) AS started_ts,
		MAX(se.event_timestamp) FILTER (
			WHERE se.event_type = 'treatment_completed'
		) AS completed_ts
	FROM subscriptions s
	JOIN subscription_events se
		ON s.subscription_id = se.subscription_id
	JOIN plans p
		ON s.plan_id = p.plan_id
	GROUP BY p.plan_id, p.plan_name, se.subscription_id
	)

SELECT
	plan_id,
	plan_name,
	COUNT(*) AS completed_treatments,
	ROUND(AVG(
		EXTRACT(EPOCH FROM (completed_ts - started_ts)) / 86400.0), 2
	) AS avg_treatment_days,
	ROUND(MIN(
		EXTRACT(EPOCH FROM (completed_ts - started_ts)) / 86400.0), 2
	) AS min_treatment_days,
	ROUND(MAX(
		EXTRACT(EPOCH FROM (completed_ts - started_ts)) / 86400.0), 2
	) AS max_treatment_days
FROM ts_by_plan
WHERE completed_ts IS NOT NULL
	AND started_ts IS NOT NULL
GROUP BY plan_id, plan_name
ORDER BY avg_treatment_days;

-- Premium has the shortest average completed-treatment duration at 190.50 days,
-- followed by Plus at 204.93 and Basic at 210.62. Premium has only 14 completed treatments,
-- so its average is based on a much smaller group compared with the Basic plan.

/* TIME TO CANCELLATION BY PLAN */

WITH cancelled_subs AS (
	SELECT
		p.plan_id,
		p.plan_name,
		s.subscription_id,
		s.activated_at,
		s.ended_at
	FROM subscriptions s
	JOIN plans p
		ON s.plan_id = p.plan_id
	WHERE subscription_status = 'cancelled'
	)

SELECT
	plan_id,
	plan_name,
	COUNT(*) AS cancelled_subscriptions,
	ROUND(AVG(
		EXTRACT(EPOCH FROM (ended_at - activated_at)) / 86400.0), 2
	) AS avg_days_to_cancellation,
	ROUND(MIN(
		EXTRACT(EPOCH FROM (ended_at - activated_at)) / 86400.0), 2
	) AS min_days_to_cancellation,
	ROUND(MAX(
		EXTRACT(EPOCH FROM (ended_at - activated_at)) / 86400.0), 2
	) AS max_days_to_cancellation
FROM cancelled_subs
WHERE activated_at IS NOT NULL
	AND ended_at IS NOT NULL
GROUP BY plan_id, plan_name
ORDER BY avg_days_to_cancellation DESC;

-- Premium has the longest average time to cancellation at 107.68 days,
-- while Plus has the shortest at 102.66 days.
-- Basic has the most cancelled subscriptions at 84.

/* SUBSCRIPTION FREQUENCY AMONG CUSTOMERS WITH PLAN SELECTED */

WITH subs_by_customer AS (
	SELECT
		customer_id,
		COUNT(subscription_id) AS subscriptions_per_customer
	FROM subscriptions
	GROUP BY customer_id
	),

sub_count_by_customer_count AS (
	SELECT
		subscriptions_per_customer,
		COUNT(customer_id) AS customer_count,
		(subscriptions_per_customer
			* COUNT(customer_id)
		) AS subscriptions_represented
	FROM subs_by_customer
	GROUP BY subscriptions_per_customer
	)

SELECT
	subscriptions_per_customer,
	customer_count,
	SUM(customer_count) OVER () AS total_customers,
	subscriptions_represented,
	ROUND(
		100.0 * customer_count
		/
		NULLIF(SUM(customer_count) OVER (), 0), 2
	) AS customer_percentage
FROM sub_count_by_customer_count
ORDER BY subscriptions_per_customer;

-- 5.22% of customers with at least one subscription returned for a second subscription.

WITH returning_customers AS (
	SELECT
		s.customer_id,
		s.subscription_id,
		COUNT(s.subscription_id) OVER (
			PARTITION BY s.customer_id
		) AS subs_count,
		p.plan_id,
		p.plan_name,
		s.selected_at
	FROM subscriptions s
	JOIN plans p
		ON s.plan_id = p.plan_id
	),

sub_order AS (
	SELECT
		customer_id,
		plan_id,
		plan_name,
		selected_at,
		ROW_NUMBER() OVER (
			PARTITION BY customer_id
			ORDER BY selected_at, subscription_id
		) AS sub_order
	FROM returning_customers
	WHERE subs_count > 1
	),

customer_plans AS (
	SELECT
		customer_id,
		MIN(plan_id) FILTER (
			WHERE sub_order = 1
		) AS first_plan_id,
		MIN(plan_name) FILTER (
			WHERE sub_order = 1
		) AS first_plan_name,
		MIN(plan_id) FILTER (
			WHERE sub_order = 2
		) AS second_plan_id,
		MIN(plan_name) FILTER (
			WHERE sub_order = 2
		) AS second_plan_name
	FROM sub_order
	GROUP BY customer_id
	)

SELECT
	first_plan_id,
	first_plan_name,
	second_plan_id,
	second_plan_name,
	COUNT(customer_id) AS returning_customer_count
FROM customer_plans
GROUP BY first_plan_id, first_plan_name, second_plan_id, second_plan_name
ORDER BY returning_customer_count DESC;

-- All 47 selected the same plan for their second subscription.
-- Plus-to-Plus is the most common pair, with 19 customers.
-- This shows repeat plan selection; it doesn’t indicate continuous
-- subscription retention.

/* INTAKE OUTCOMES */

WITH intake_count_by_status AS (
	SELECT
		intake_status,
		COUNT(intake_id) AS intake_count
	FROM intakes
	GROUP BY intake_status
	)

SELECT
	intake_status,
	intake_count,
	SUM(intake_count) OVER () AS total_intakes,
	ROUND(
		100.0 * intake_count
		/
		NULLIF(SUM(intake_count) OVER (), 0), 2
	) AS status_percentage
FROM intake_count_by_status
ORDER BY intake_count DESC;

-- Among all intakes 92.19% were completed, 2.43% expired,
-- and 5.39% are still pending.

/* INTAKE COMPLETION TIME BY PLAN */

SELECT
	p.plan_id,
	p.plan_name,
	COUNT(i.intake_id) AS completed_intakes,
	ROUND(AVG(
		EXTRACT(EPOCH FROM (i.completed_at - i.started_at)) / 3600.0), 2
	) AS avg_hours_to_complete,
	ROUND(MIN(
		EXTRACT(EPOCH FROM (i.completed_at - i.started_at)) / 3600.0), 2
	) AS min_hours_to_complete,
	ROUND(MAX(
		EXTRACT(EPOCH FROM (i.completed_at - i.started_at)) / 3600.0), 2
	) AS max_hours_to_complete
FROM intakes i
JOIN subscriptions s
	ON i.subscription_id = s.subscription_id
JOIN plans p
	ON s.plan_id = p.plan_id
WHERE i.intake_status = 'completed'
	AND i.started_at IS NOT NULL
	AND i.completed_at IS NOT NULL
GROUP BY p.plan_id, p.plan_name
ORDER BY avg_hours_to_complete;

-- Basic has the shortest average completion time (75.32 hours),
-- followed by Premium (76.55) and Plus (77.83). The averages are close:
-- only 2.51 hours separate Basic and Plus — despite the wide ranges.

/* INTAKE STATUS VS SUBSCRIPTION STATUS */

SELECT
	i.intake_status,
	s.subscription_status,
	COUNT(s.subscription_id) AS subscription_count
FROM intakes i
JOIN subscriptions s
	ON i.subscription_id = s.subscription_id
GROUP BY i.intake_status, s.subscription_status
ORDER BY i.intake_status ASC, subscription_count DESC;

-- All 23 expired intakes belong to rejected subscriptions.
-- Completing an intake doesn’t guarantee activation:
-- 67 subscriptions were rejected and 51 remain pending
-- despite completed intakes.

/* CANCELLATION PERCENTAGE BY PLAN */

WITH subscriptions_by_plan AS (
	SELECT
		p.plan_id,
		p.plan_name,
		s.subscription_status,
		COUNT(s.subscription_id) AS subscription_count
	FROM plans p
	JOIN subscriptions s
		ON p.plan_id = s.plan_id
		AND s.activated_at IS NOT NULL
	GROUP BY p.plan_id, p.plan_name, s.subscription_status
	),

subscriptions_by_status AS (
	SELECT
		plan_id,
		plan_name,
		SUM(subscription_count) AS activated_subscriptions,
		SUM(subscription_count) FILTER (
			WHERE subscription_status = 'cancelled'
		) AS cancelled_subscriptions
	FROM subscriptions_by_plan
	GROUP BY plan_id, plan_name
	)

SELECT
	plan_id,
	plan_name,
	activated_subscriptions,
	cancelled_subscriptions,
	ROUND(
		100.0 * cancelled_subscriptions
		/
		NULLIF(activated_subscriptions, 0), 2
	) AS cancellation_percentage
FROM subscriptions_by_status
ORDER BY cancellation_percentage DESC;

-- Plus has the highest cancellation percentage (22.85%) and
-- Premium has the lowest (21.37%), a gap of 1.48 percentage points.

/* CANCELLATION REASONS BY PLAN */

WITH cancelled_by_reason AS (
	SELECT
		p.plan_id,
		p.plan_name,
		se.event_reason,
		COUNT(DISTINCT s.subscription_id) AS cancelled_subscriptions
	FROM subscription_events se
	JOIN subscriptions s
		ON se.subscription_id = s.subscription_id
	JOIN plans p
		ON s.plan_id = p.plan_id
	WHERE se.event_type = 'cancelled'
	GROUP BY p.plan_id, p.plan_name, se.event_reason
	),

cancelled_by_plan AS (
	SELECT
		plan_id,
		plan_name,
		event_reason,
		cancelled_subscriptions,
		SUM(cancelled_subscriptions) OVER (
			PARTITION BY plan_id
		) AS total_cancelled_by_plan
	FROM cancelled_by_reason
	)

SELECT
	plan_id,
	plan_name,
	event_reason,
	cancelled_subscriptions,
	total_cancelled_by_plan,
	ROUND(
		100.0 * cancelled_subscriptions
		/
		NULLIF(total_cancelled_by_plan, 0), 2
	) AS reason_percentage
FROM cancelled_by_plan
ORDER BY plan_id ASC, cancelled_subscriptions DESC;

-- Basic: patient request is the leading reason at 34.52%.
-- Plus: patient request and side effects are tied at 29.51% each.
-- Premium: not satisfied leads at 40.00%, though this is based on
-- only 25 cancellations, so each case has a larger effect on the percentage.