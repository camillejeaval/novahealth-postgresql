-- NovaHealth PostgreSQL portfolio project
-- Deterministic synthetic seed data
--
-- Prerequisites:
--   1. Run sql/01_schema.sql.
--   2. Import data/customers.csv into the customers table.
--
-- Data cutoff: 2026-09-01 23:59:59
-- Run this script once against a newly created and populated database.

-- INSERT PLANS
INSERT INTO plans (plan_name, monthly_price) VALUES
    ('Basic', 29.00),
    ('Plus', 59.00),
    ('Premium', 99.00);

-- SUBSCRIPTION STATUSES PREVIEW

WITH selected_customers AS (
	SELECT
	  customer_id,
	  signup_date,
	  ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_number
	FROM customers
	WHERE MOD(customer_id, 10) <> 0
	),

subscription_base AS (
  SELECT
    customer_id,
    signup_date,
    customer_number,

    CASE
      WHEN MOD(customer_number - 1, 20) BETWEEN 0 AND 9
        THEN 1
      WHEN MOD(customer_number - 1, 20) BETWEEN 10 AND 16
        THEN 2
      ELSE 3
    END AS plan_id,

    CASE
      WHEN MOD((customer_number - 1) * 37, 100) BETWEEN 0 AND 44
        THEN 'active'
      WHEN MOD((customer_number - 1) * 37, 100) BETWEEN 45 AND 64
        THEN 'cancelled'
      WHEN MOD((customer_number - 1) * 37, 100) BETWEEN 65 AND 79
        THEN 'completed'
      WHEN MOD((customer_number - 1) * 37, 100) BETWEEN 80 AND 89
        THEN 'rejected'
      ELSE 'pending'
    END AS subscription_status,

    signup_date::timestamp + INTERVAL '12 hours' AS selected_at

  FROM selected_customers
  ),

subscription_with_activation AS (
  SELECT
    *,

    CASE
      WHEN subscription_status IN (
        'active',
        'cancelled',
        'completed'
          )
        THEN selected_at
          + (1 + MOD(customer_number * 3, 7))
          * INTERVAL '1 day'
      ELSE NULL
    END AS activated_at

  FROM subscription_base
	),

subscription_preview AS (
  SELECT
    *,

    CASE
      WHEN subscription_status = 'rejected'
        THEN selected_at
          + (1 + MOD(customer_number * 5, 7)) * INTERVAL '1 day'
      WHEN subscription_status = 'cancelled'
        THEN activated_at
          + (30 + MOD(customer_number * 5, 151)) * INTERVAL '1 day'
      WHEN subscription_status = 'completed'
        THEN activated_at
          + (90 + MOD(customer_number * 5, 276)) * INTERVAL '1 day'
      ELSE NULL
    END AS ended_at

  FROM subscription_with_activation
  ),

subscription_final AS (
  SELECT
    customer_id,
    plan_id,

    CASE
      WHEN ended_at > TIMESTAMP '2026-09-01 23:59:59'
        THEN 'active'
      ELSE subscription_status
    END AS subscription_status,

    selected_at,
    activated_at,

    CASE
      WHEN ended_at > TIMESTAMP '2026-09-01 23:59:59'
        THEN NULL
      ELSE ended_at
    END AS ended_at

  FROM subscription_preview
  )

-- SUBSCRIPTIONS INSERT FROM PREVIEW

INSERT INTO subscriptions (
    customer_id,
    plan_id,
    subscription_status,
    selected_at,
    activated_at,
    ended_at
    )

SELECT
    customer_id,
    plan_id,
    subscription_status,
    selected_at,
    activated_at,
    ended_at

FROM subscription_final;

-- RETURNERS PREVIEW

WITH eligible_returners AS (
  SELECT
    subscription_id AS previous_subscription_id,
    customer_id,
    plan_id,
    subscription_status AS previous_status,
    ended_at,

    ROW_NUMBER() OVER (
      PARTITION BY subscription_status
      ORDER BY subscription_id
        ) AS return_number

  FROM subscriptions
  WHERE subscription_status IN ('cancelled', 'rejected')
    AND ended_at <= TIMESTAMP '2026-05-31 23:59:59'
	),

selected_returners AS (
	SELECT
		*,
		ROW_NUMBER() OVER (
        ORDER BY previous_subscription_id
        ) AS returning_customer_number

  FROM eligible_returners
  WHERE MOD(return_number, 5) = 0
	),

returning_subscription_base AS (
	SELECT
		customer_id,
		plan_id,

    CASE
			WHEN MOD(returning_customer_number - 1, 10) BETWEEN 0 AND 6
			  THEN 'active'
			ELSE 'pending'
		END AS subscription_status,

		ended_at
        + (30 + MOD(returning_customer_number * 7, 51))
        * INTERVAL '1 day'
		  AS selected_at,

			returning_customer_number

	FROM selected_returners
	),

returning_subscription_preview AS (
	SELECT
		*,

		CASE
			WHEN subscription_status = 'active'
			  THEN selected_at
				  + (1 + MOD(returning_customer_number * 3, 5))
				  * INTERVAL '1 day'
			ELSE NULL
		END AS activated_at,

    NULL::timestamp AS ended_at

	FROM returning_subscription_base
	)

-- SUBSCRIPTIONS INSERT FROM RETURNERS PREVIEW

INSERT INTO subscriptions (
    customer_id,
    plan_id,
    subscription_status,
    selected_at,
    activated_at,
    ended_at
    )

SELECT
    customer_id,
    plan_id,
    subscription_status,
    selected_at,
    activated_at,
    ended_at
FROM returning_subscription_preview;

-- INTAKE STATUSES PREVIEW

WITH subscription_intake_base AS (
  SELECT
    subscription_id,
    subscription_status,
    selected_at,

    ROW_NUMBER() OVER (
      PARTITION BY subscription_status
      ORDER BY subscription_id
    ) AS status_number

  FROM subscriptions
  ),

intake_status_preview AS (
	SELECT
		subscription_id,
		selected_at,
		status_number,
		subscription_status,

		CASE
			WHEN subscription_status = 'rejected'
				AND MOD(status_number, 4) = 0
			THEN 'expired'

			WHEN subscription_status = 'pending'
				AND MOD(status_number, 2) = 0
			THEN 'completed'

			WHEN subscription_status = 'pending'
			THEN 'pending'

			ELSE 'completed'
		END AS intake_status

	FROM subscription_intake_base
	),

intake_with_started_at AS (
	SELECT
		*,

		CASE
			WHEN intake_status = 'completed'
				OR MOD(subscription_id, 2) = 0
			THEN selected_at
					+ (1 + MOD(subscription_id * 5, 3)) * INTERVAL '1 day'
			ELSE NULL
		END AS started_at

	FROM intake_status_preview
	),

intake_preview AS (
	SELECT
		*,

		CASE
			WHEN intake_status = 'completed'
			THEN started_at
					+ (1 + MOD(subscription_id * 7, 5)) * INTERVAL '1 day'
			ELSE NULL
		END AS completed_at

	FROM intake_with_started_at
	),

intake_final AS (
	SELECT
		subscription_id,

		CASE
			WHEN completed_at > TIMESTAMP '2026-09-01 23:59:59'
				THEN 'pending'
			ELSE intake_status
		END AS intake_status,

		started_at,

		CASE
			WHEN completed_at > TIMESTAMP '2026-09-01 23:59:59'
				THEN NULL
			ELSE completed_at
		END AS completed_at
	FROM intake_preview
	)

-- INSERT INTO INTAKES FROM INTAKE_FINAL

INSERT INTO intakes (
    subscription_id,
    intake_status,
    started_at,
    completed_at
)

SELECT
    subscription_id,
    intake_status,
    started_at,
    completed_at
FROM intake_final;

-- INTAKES VS ACTIVATION UPDATE

UPDATE intakes AS i
SET
    started_at =
        s.selected_at
        + (
            2 + MOD(i.subscription_id * 3, 4)
          ) * INTERVAL '1 hour',

    completed_at =
        s.activated_at
        - (
            12 + MOD(i.subscription_id * 5, 7)
          ) * INTERVAL '1 hour',

    updated_at = CURRENT_TIMESTAMP

FROM subscriptions AS s
WHERE s.subscription_id = i.subscription_id
  AND s.activated_at IS NOT NULL;

-- INTAKE VS REJECTION UPDATE

UPDATE intakes AS i
SET
    started_at =
        CASE
            WHEN i.started_at IS NULL
                THEN NULL
            ELSE
                s.selected_at
                + (
                    2 + MOD(i.subscription_id * 3, 4)
                  ) * INTERVAL '1 hour'
        END,

    completed_at =
        CASE
            WHEN i.intake_status = 'completed'
                THEN
                    s.ended_at
                    - (
                        10 + MOD(i.subscription_id * 3, 5)
                      ) * INTERVAL '1 hour'
            ELSE NULL
        END,

    updated_at = CURRENT_TIMESTAMP

FROM subscriptions AS s
WHERE s.subscription_id = i.subscription_id
  AND s.subscription_status = 'rejected';


-- APPOINTMENTS TABLE
-- APPOINTMENT STATUS PREVIEW

WITH initial_appointment_base AS (
	SELECT
		s.subscription_id,
		s.subscription_status,
		s.activated_at,
		s.ended_at,
		i.completed_at AS intake_completed_at,

		ROW_NUMBER() OVER (
			PARTITION BY s.subscription_status
			ORDER BY s.subscription_id
		) AS status_number

	FROM subscriptions AS s
	JOIN intakes AS i
		ON i.subscription_id = s.subscription_id
	WHERE i.intake_status = 'completed'
	),

initial_appointment_status_preview AS (
	SELECT
		subscription_id,
		subscription_status,
		activated_at,
		ended_at,
		intake_completed_at,
		status_number,
		'initial_appt' AS appointment_type,

		CASE
		-- rejected + every fourth row = no_show
			WHEN subscription_status = 'rejected'
				AND MOD(status_number, 4) = 0
			THEN 'no_show'

		-- pending = scheduled
			WHEN subscription_status = 'pending'
			THEN 'scheduled'

		-- other rejected rows = completed
		-- everything else = completed
			ELSE 'completed'
		END AS appointment_status,

		CASE
		-- active/cancelled/completed subscriptions = eligible
			WHEN subscription_status IN ('active', 'cancelled', 'completed')
			THEN 'eligible'

		-- rejected appointments that are completed = not_eligible
			WHEN subscription_status = 'rejected'
				AND MOD(status_number, 4) <> 0
			THEN 'not_eligible'

		-- no-show and scheduled appointments = NULL
			ELSE NULL
	    END AS eligibility_result

	FROM initial_appointment_base
	),

initial_appointment_with_schedule AS (
	SELECT
		*,

		CASE
			WHEN activated_at IS NOT NULL
				THEN activated_at - INTERVAL '6 hours'

				WHEN subscription_status = 'rejected'
					THEN ended_at - INTERVAL '6 hours'

			ELSE
				intake_completed_at
				+ (1 + MOD(subscription_id * 3, 5)) * INTERVAL '1 day'
		END AS scheduled_at

	FROM initial_appointment_status_preview
	),

initial_appointment_preview AS (
	SELECT
		*,

		CASE
			WHEN appointment_status = 'completed'
				AND activated_at IS NOT NULL
			THEN activated_at - INTERVAL '1 hour'

			WHEN appointment_status = 'completed'
				AND subscription_status = 'rejected'
			THEN ended_at - INTERVAL '1 hour'

			ELSE NULL
		END AS completed_at

	FROM initial_appointment_with_schedule
	)

-- INSERT INTO APPOINTMENTS FROM INITIAL APPOINTMENT PREVIEW
INSERT INTO appointments (
  subscription_id,
  scheduled_at,
  appointment_type,
  appointment_status,
  eligibility_result,
  completed_at
)

SELECT
  subscription_id,
  scheduled_at,
  appointment_type,
  appointment_status,
  eligibility_result,
  completed_at
FROM initial_appointment_preview;


-- FOLLOW UP APPOINTMENTS

-- DETERMINISTIC SAMPLE FROM ELIGIBLE SUBSCRIPTIONS

WITH follow_up_eligible AS (
	SELECT
		subscription_id,
		subscription_status,
		activated_at,
		ended_at,

		ROW_NUMBER() OVER (
			PARTITION BY subscription_status
			ORDER BY subscription_id
		) AS follow_up_number

	FROM subscriptions
		WHERE activated_at IS NOT NULL
			AND COALESCE(
				ended_at,
				TIMESTAMP '2026-09-01 23:59:59'
				) >= activated_at + INTERVAL '30 days'
	),

selected_follow_ups AS (
	SELECT
		*,
		ROW_NUMBER() OVER (
			ORDER BY subscription_id
		) AS appointment_number

	FROM follow_up_eligible
		WHERE MOD(follow_up_number - 1, 5) BETWEEN 0 AND 2
	),

follow_up_status_preview AS (
	SELECT
	    subscription_id,
		ended_at,
	    'follow_up' AS appointment_type,

	    CASE
	      WHEN MOD(appointment_number - 1, 20) BETWEEN 0 AND 16
	        THEN 'completed'
	      WHEN MOD(appointment_number - 1, 20) BETWEEN 17 AND 18
	        THEN 'no_show'
	      ELSE 'cancelled'

	    END AS appointment_status,

	    NULL::varchar AS eligibility_result,

	    activated_at + INTERVAL '30 days' AS scheduled_at,

	    appointment_number

	FROM selected_follow_ups
	),

follow_up_preview AS (
    SELECT
        *,

        CASE
            WHEN appointment_status = 'completed'
                THEN scheduled_at + INTERVAL '1 hour'
            ELSE NULL
        END AS completed_at

    FROM follow_up_status_preview
)

-- FOLLOW UP INSERT INTO APPOINTMENTS

INSERT INTO appointments (
  subscription_id,
  scheduled_at,
  appointment_type,
  appointment_status,
  eligibility_result,
  completed_at
)

SELECT
  subscription_id,
  scheduled_at,
  appointment_type,
  appointment_status,
  eligibility_result,
  completed_at
FROM follow_up_preview;

-- PAYMENTS TABLE
-- INITIAL PAYMENT INSERT

WITH initial_payment_preview AS (
  SELECT
      s.subscription_id,
      i.completed_at + INTERVAL '1 hour' AS payment_date,
      'successful' AS payment_status,
      'initial' AS payment_type,
      p.monthly_price AS amount,
      a.scheduled_at AS appointment_scheduled_at,
	    i.completed_at AS i_completed_at

  FROM subscriptions AS s
  JOIN plans AS p
      ON p.plan_id = s.plan_id
  JOIN intakes AS i
      ON i.subscription_id = s.subscription_id
  JOIN appointments AS a
      ON a.subscription_id = s.subscription_id
    AND a.appointment_type = 'initial_appt'

  WHERE i.intake_status = 'completed'
  )

INSERT INTO payments (
    subscription_id,
    payment_date,
    payment_status,
    payment_type,
    amount
)

SELECT
    subscription_id,
    payment_date,
    payment_status,
    payment_type,
    amount
FROM initial_payment_preview;

-- RENEWAL PAYMENTS INSERT

WITH renewal_schedule AS (
    SELECT
        s.subscription_id,
        s.subscription_status,
        p.monthly_price AS amount,
        renewal.payment_date

    FROM subscriptions AS s
    JOIN plans AS p
        ON p.plan_id = s.plan_id
    JOIN payments AS initial_payment
        ON initial_payment.subscription_id = s.subscription_id
       AND initial_payment.payment_type = 'initial'
       AND initial_payment.payment_status = 'successful'

    CROSS JOIN LATERAL generate_series(
        initial_payment.payment_date + INTERVAL '1 month',
        COALESCE(
            s.ended_at,
            TIMESTAMP '2026-09-01 23:59:59'
        ),
        INTERVAL '1 month'
    ) AS renewal(payment_date)

    WHERE s.activated_at IS NOT NULL
	),

renewal_numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY payment_date, subscription_id
        ) AS renewal_number
    FROM renewal_schedule
	),

renewal_preview AS (
    SELECT
        subscription_id,
        payment_date,

        CASE
            WHEN subscription_status = 'active'
                 AND payment_date
                     >= TIMESTAMP '2026-09-01 23:59:59'
                        - INTERVAL '7 days'
                THEN 'pending'

            WHEN MOD(renewal_number, 12) = 0
                THEN 'failed'

            ELSE 'successful'
        END AS payment_status,

        'renewal' AS payment_type,
        amount

    FROM renewal_numbered
	)

INSERT INTO payments (
  subscription_id,
  payment_date,
  payment_status,
  payment_type,
  amount
)

SELECT
  subscription_id,
  payment_date,
  payment_status,
  payment_type,
  amount
FROM renewal_preview;

-- REFUNDS TABLE
-- INSERTING TREATMENT REJECTION REFUNDS

WITH treatment_rejection_refund_preview AS (
    SELECT
        p.payment_id,
        a.completed_at + INTERVAL '30 minutes' AS processed_at,
        p.amount AS refund_amount,
        'treatment_rejection' AS refund_reason,
        'completed' AS refund_status,
        a.completed_at AS created_at

    FROM payments AS p
    JOIN appointments AS a
        ON a.subscription_id = p.subscription_id
       AND a.appointment_type = 'initial_appt'

    WHERE p.payment_type = 'initial'
      AND p.payment_status = 'successful'
      AND a.appointment_status = 'completed'
      AND a.eligibility_result = 'not_eligible'
)
INSERT INTO refunds (
    payment_id,
    processed_at,
    refund_amount,
    refund_reason,
    refund_status,
    created_at
)

SELECT
    payment_id,
    processed_at,
    refund_amount,
    refund_reason,
    refund_status,
    created_at
FROM treatment_rejection_refund_preview;

-- INSERTING CANCELLATION RELATED REFUNDS

WITH cancellation_refund_candidates AS (
    SELECT
        p.payment_id,
        p.amount,
        p.payment_date,
        s.subscription_id,
        s.ended_at,

        ROW_NUMBER() OVER (
            PARTITION BY s.subscription_id
            ORDER BY p.payment_date DESC, p.payment_id DESC
        ) AS payment_rank

    FROM subscriptions AS s
    JOIN payments AS p
        ON p.subscription_id = s.subscription_id

    WHERE s.subscription_status = 'cancelled'
      AND p.payment_status = 'successful'
      AND p.payment_date BETWEEN
            s.ended_at - INTERVAL '7 days'
            AND s.ended_at
),
selected_cancellation_refunds AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY ended_at, payment_id
        ) AS request_number

    FROM cancellation_refund_candidates
    WHERE payment_rank = 1
      AND ended_at + INTERVAL '30 minutes'
            <= TIMESTAMP '2026-09-01 23:59:59'
),
cancellation_refund_preview AS (
    SELECT
        payment_id,
        ended_at + INTERVAL '30 minutes' AS processed_at,
        amount AS refund_amount,
        'subscription_cancelled' AS refund_reason,

        CASE
            WHEN MOD(request_number, 5) = 0
                THEN 'declined'
            ELSE 'completed'
        END AS refund_status,

        ended_at AS created_at

    FROM selected_cancellation_refunds
)

INSERT INTO refunds (
    payment_id,
    processed_at,
    refund_amount,
    refund_reason,
    refund_status,
    created_at
)

SELECT
    payment_id,
    processed_at,
    refund_amount,
    refund_reason,
    refund_status,
    created_at
FROM cancellation_refund_preview;

-- SUBSCRIPTION EVENTS TABLE
-- SELECTED EVENTS INSERT

WITH selected_event_preview AS (
    SELECT
        subscription_id,
        'selected' AS event_type,
        NULL::varchar AS event_reason,
        selected_at AS event_timestamp

    FROM subscriptions
)

INSERT INTO subscription_events (
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
)

SELECT
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
FROM selected_event_preview;

-- ACTIVATED SUBSCRIPTIONS EVENTS

WITH activated_event_preview AS (
    SELECT
        subscription_id,
        'activated' AS event_type,
        NULL::varchar AS event_reason,
        activated_at AS event_timestamp

    FROM subscriptions
	WHERE activated_at IS NOT NULL
)

INSERT INTO subscription_events (
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
)

SELECT
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
FROM activated_event_preview;

-- REJECTED SUBSCRIPTIONS EVENTS

WITH rejected_event_preview AS (
	SELECT
		s.subscription_id,
		a.appointment_type,
		i.intake_status,
		a.eligibility_result,
		a.appointment_status,
		'rejected' AS event_type,

		CASE
			WHEN i.intake_status = 'expired'
				THEN 'intake_expired'
			WHEN a.appointment_status = 'no_show'
				THEN 'appointment_no_show'
			ELSE 'not_eligible'
		END AS event_reason,

		s.ended_at AS event_timestamp

	FROM subscriptions s
	JOIN intakes i ON s.subscription_id = i.subscription_id
	LEFT JOIN appointments a ON i.subscription_id = a.subscription_id
		AND a.appointment_type = 'initial_appt'
	WHERE s.subscription_status = 'rejected'
	)

INSERT INTO subscription_events (
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
)

SELECT
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
FROM rejected_event_preview;

-- CANCELLED SUBSCRIPTIONS EVENTS

WITH cancelled_event_base AS (
	SELECT
		subscription_id,
		ended_at,
		ROW_NUMBER () OVER (ORDER BY subscription_id) AS event_number
	FROM subscriptions
	WHERE subscription_status = 'cancelled'
	),

cancelled_event_preview AS (
	SELECT
		subscription_id,
		'cancelled' AS event_type,

		CASE
			WHEN MOD((event_number - 1) * 37, 170) BETWEEN 0 AND 50
				THEN 'patient_request'
			WHEN MOD((event_number - 1) * 37, 170) BETWEEN 51 AND 84
				THEN 'side_effects'
			WHEN MOD((event_number - 1) * 37, 170) BETWEEN 85 AND 118
				THEN 'not_satisfied'
			WHEN MOD((event_number - 1) * 37, 170) BETWEEN 119 AND 152
				THEN 'no_longer_needed'
			ELSE 'other'
		END AS event_reason,

		ended_at AS event_timestamp
	FROM cancelled_event_base
	)

INSERT INTO subscription_events (
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
)

SELECT
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
FROM cancelled_event_preview;

-- TREATMENT START EVENTS

WITH treatment_start_base AS (
	SELECT
		subscription_id,
		subscription_status,
		ROW_NUMBER() OVER(
			PARTITION BY subscription_status
			ORDER BY subscription_id
		) AS event_number,
		activated_at,
		ended_at
	FROM subscriptions
	WHERE activated_at IS NOT NULL
	),

started_treatments_preview AS (
	SELECT
		subscription_id,
		activated_at,
		subscription_status,

		(activated_at
			+ (7 + MOD(event_number * 5, 8))
			* INTERVAL '1 day'
			) AS event_timestamp,

		ended_at
	FROM treatment_start_base
	),

treatment_start_events AS (
	SELECT
		subscription_id,
		subscription_status,
		'treatment_started' AS event_type,
		NULL::varchar AS event_reason,
		activated_at,
		event_timestamp,
		ended_at
	FROM started_treatments_preview
	),

treatment_events_final AS (
	SELECT
		subscription_id,
		subscription_status,
		event_type,
		event_reason,
		activated_at,
		event_timestamp,
		ended_at
	FROM treatment_start_events
	WHERE event_timestamp > activated_at
		AND event_timestamp <=
			COALESCE(
			ended_at,
			TIMESTAMP '2026-09-01 23:59:59'
			)
	)

INSERT INTO subscription_events (
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
)

SELECT
    subscription_id,
    event_type,
    event_reason,
    event_timestamp
FROM treatment_events_final;

-- COMPLETED TREATMENT EVENTS

WITH completed_treatment_base AS (
	SELECT
		subscription_id,
		subscription_status,
		ended_at
	FROM subscriptions
	WHERE subscription_status = 'completed'
	),

started_treatment_base AS(
	SELECT
		subscription_id,
		event_timestamp AS started_at
	FROM subscription_events
	WHERE event_type = 'treatment_started'
),

final_preview AS (
  SELECT
    c.subscription_id,
    c.subscription_status,
    'treatment_completed' AS event_type,
    NULL::varchar AS event_reason,
    c.ended_at AS event_timestamp,
    s.started_at
  FROM completed_treatment_base c
  JOIN started_treatment_base s ON c.subscription_id = s.subscription_id
  WHERE c.ended_at > s.started_at
  )

INSERT INTO subscription_events (
  subscription_id,
  event_type,
  event_reason,
  event_timestamp
)

SELECT
  subscription_id,
  event_type,
  event_reason,
  event_timestamp
FROM final_preview;
