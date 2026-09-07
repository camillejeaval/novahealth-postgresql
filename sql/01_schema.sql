-- NovaHealth PostgreSQL portfolio project
-- Complete database schema
--
-- Run this file before loading customer data or executing the seed script.
-- Tables are ordered according to their foreign-key dependencies.

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    gender CHAR(1) NOT NULL,
    signup_date DATE,
    state_code CHAR(2) NOT NULL,
    acquisition_channel VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP CHECK (updated_at > created_at)
);

CREATE TABLE plans (
    plan_id SERIAL PRIMARY KEY,
    plan_name VARCHAR(30) NOT NULL,
    monthly_price NUMERIC(10,2) NOT NULL,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP CHECK (updated_at > created_at)
);

CREATE TABLE subscriptions (
    subscription_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
    plan_id INTEGER NOT NULL REFERENCES plans(plan_id),
    subscription_status VARCHAR(20) NOT NULL,
    selected_at TIMESTAMP NOT NULL,
    activated_at TIMESTAMP,
    ended_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,

    CHECK (activated_at IS NULL OR activated_at >= selected_at),
    CHECK (ended_at IS NULL OR ended_at > selected_at),
    CHECK (updated_at IS NULL OR updated_at > created_at),
    CHECK (
        subscription_status IN (
            'pending',
            'active',
            'cancelled',
            'rejected',
            'completed'
        )
    )
);

CREATE TABLE intakes (
    intake_id SERIAL PRIMARY KEY,
    subscription_id INTEGER NOT NULL UNIQUE
        REFERENCES subscriptions(subscription_id),
    intake_status VARCHAR(20) NOT NULL,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,

    CHECK (
        completed_at IS NULL
        OR started_at IS NOT NULL
        AND completed_at > started_at
    ),
    CHECK (
        updated_at IS NULL
        OR updated_at > created_at
    ),
    CHECK (
        intake_status IN (
            'completed',
            'pending',
            'expired'
        )
    )
);

CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY,
    subscription_id INTEGER NOT NULL
        REFERENCES subscriptions(subscription_id),
    scheduled_at TIMESTAMP NOT NULL,
    appointment_type VARCHAR(30) NOT NULL,
    appointment_status VARCHAR(20) NOT NULL,
    eligibility_result VARCHAR(20),
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,

    CHECK (
        completed_at IS NULL
        OR completed_at >= scheduled_at
    ),
    CHECK (
        appointment_type IN (
            'initial_appt',
            'follow_up'
        )
    ),
    CHECK (
        updated_at IS NULL
        OR updated_at > created_at
    ),
    CHECK (
        appointment_status IN (
            'completed',
            'no_show',
            'rescheduled',
            'scheduled',
            'cancelled'
        )
    ),
    CHECK (
        eligibility_result IS NULL
        OR eligibility_result IN (
            'eligible',
            'not_eligible'
        )
    )
);

CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    subscription_id INTEGER NOT NULL
        REFERENCES subscriptions(subscription_id),
    payment_date TIMESTAMP,
    payment_status VARCHAR(20) NOT NULL,
    payment_type VARCHAR(15) NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,

    CHECK (
        updated_at IS NULL
        OR updated_at > created_at
    ),
    CHECK (
        payment_status IN (
            'successful',
            'failed',
            'pending'
        )
    ),
    CHECK (
        payment_type IN (
            'initial',
            'renewal'
        )
    ),
    CHECK (amount > 0)
);

CREATE TABLE refunds (
    refund_id SERIAL PRIMARY KEY,
    payment_id INTEGER NOT NULL UNIQUE
        REFERENCES payments(payment_id),
    processed_at TIMESTAMP NOT NULL,
    refund_amount NUMERIC(10,2) NOT NULL,
    refund_reason VARCHAR(50) NOT NULL,
    refund_status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,

    CHECK (
      updated_at IS NULL
      OR updated_at > created_at
      ),
    CHECK (
      processed_at >= created_at
      ),
    CHECK (
      refund_reason IN (
        'treatment_rejection',
        'duplicate_charge',
        'plan_change',
        'subscription_cancelled'
        )
      ),
    CHECK (
      refund_status IN (
        'completed',
        'declined'
        )
      ),
    CHECK (refund_amount > 0)
);

CREATE TABLE subscription_events (
    event_id SERIAL PRIMARY KEY,
    subscription_id INTEGER NOT NULL
      REFERENCES subscriptions(subscription_id),
    event_type VARCHAR(30) NOT NULL,
    event_reason VARCHAR(50),
    event_timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  CHECK (
    event_type IN (
      'selected',
      'activated',
      'rejected',
      'plan_changed',
      'cancelled',
      'treatment_started',
      'treatment_completed'
      )
    ),
  CHECK (
    event_reason IS NULL
    OR event_reason IN (
      'intake_expired',
      'not_eligible',
      'appointment_no_show',
      'payment_failed',
      'patient_request',
      'side_effects',
      'not_satisfied',
      'no_longer_needed',
      'other'
      )
    )
);
