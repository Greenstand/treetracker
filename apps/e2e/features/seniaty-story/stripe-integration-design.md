# Stripe Integration Design — How org E gets paid

Design notes for the money/settlement side of the Seniaty Story: when a buyer
buys a token that belongs to an organization, that org must get paid (minus a
platform fee) and be able to withdraw to their bank. This document covers the
design only — not the code.

## The core choice: Stripe Connect (Express)

Greenstand acts as a **platform/marketplace**, and every org that sells tokens
becomes a **connected account** under that platform (the model Stripe built for
marketplaces like Etsy, Lyft). The critical property:

- **Stripe holds the org's money and pays it out to their bank.** Greenstand
  never touches bank details, never holds funds, and never becomes a money
  transmitter. This is the whole reason to use Connect instead of collecting bank
  info ourselves.

So "org E gets paid" = **money lands in org E's Stripe balance, and Stripe
automatically pays it out to org E's bank on a schedule.** Greenstand's only job
is to *route the split correctly at purchase time*.

## The two phases

### Phase 1 — Onboarding (org E becomes payable)

Org E goes through **Stripe-hosted onboarding** once. On that hosted page (not
ours) they enter:

- Business/identity info (KYC — Stripe's legal requirement)
- **Bank account** for payouts

Stripe verifies it and flips two flags on org E's connected account:

- `charges_enabled` → can receive money
- `payouts_enabled` → can withdraw to bank

Greenstand stores just one thing: org E's **`stripe_account_id`**. That is the
entire link between "org E in Greenstand" and "org E's money at Stripe."

### Phase 2 — The purchase (money splits and flows)

When buyer D buys org E's token, this is a **destination charge**:

```
Buyer D's card  ──$10──▶  Stripe (one PaymentIntent)
                            │
                 ┌──────────┴──────────┐
        application_fee              transfer_data.destination
        (e.g. $1 → Greenstand)      (e.g. $9 → org E's Stripe balance)
```

One card charge, **Stripe atomically splits it**: the platform fee goes to
Greenstand's account, the remainder lands in **org E's Stripe balance**. Then
Stripe, on its normal payout schedule, moves that balance to **org E's bank**.
Nobody at Greenstand initiates the payout — Stripe does it.

## The hard part: atomicity between two systems

The token lives in **Greenstand's wallet DB**; the money lives at **Stripe**.
There is no shared transaction across them, so we can't "swap token for money"
atomically. The design rule that solves this:

> **Charge first → deliver the token on the webhook → reconcile the gaps.**

Concretely:

1. **Buyer starts purchase** → Greenstand *reserves* org E's token (blocks anyone
   else buying it) and creates the Stripe PaymentIntent.
2. **Buyer's card succeeds** → Stripe sends a `payment_intent.succeeded`
   **webhook** to Greenstand.
3. **The webhook — and only the webhook — completes the token transfer** from org
   E's wallet to buyer D's wallet. (Not the buyer's "Accept" button — that is
   untrusted and can lie.)
4. **Failure handling:**
   - Payment fails/expires → release the reservation, token goes back on sale.
   - Charged but token delivery fails → **refund** the buyer (never keep money
     without delivering).
   - A periodic **reconciliation sweep** catches anything stuck in "paid but
     undelivered."

Idempotency is keyed on the PaymentIntent ID so a webhook retry never
double-delivers.

## Mapping back to the Seniaty story

- *"user E goes through ... providing bank info and Stripe integration steps"* =
  **Phase 1 onboarding** (Stripe-hosted; org E now has
  `charges_enabled`/`payouts_enabled`).
- *"admin user S ... clicks 'approve'"* = Greenstand's own gate — the admin
  confirms org E is a legit vendor **and** their Stripe account reports ready,
  before the token is allowed to list.
- *"user D buys the token via Stripe"* = **Phase 2 destination charge**; the split
  happens here.
- *"user E received the money in his bank account"* = **Stripe's automatic
  payout** of org E's balance — this is the payoff, and it happens entirely on
  Stripe's side.

## One design decision to flag

There is a subtle overlap: the story has **admin S "approve"** *and* Stripe's
onboarding. Decide what "approve" means:

- **Trust gate only (recommended):** Stripe owns "can they receive money?"; admin
  S owns "do we *want* this org selling?" Keep them separate.
- If admin approval is meant to *be* the readiness check, gate it on
  `charges_enabled` and the button just reads Stripe's status.

The clean separation is better — it keeps Greenstand out of the money-readiness
business entirely.
