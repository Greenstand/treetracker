# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Greenstand is a **Yarn 4 monorepo** containing a secure digital token management platform with the following structure:

```
greenstand/
├── treetracker-wallet-app/        # Primary: Web, mobile, and backend applications
├── treetracker-database/          # Database schemas and migrations
├── treetracker-infrastructure/    # Terraform AWS infrastructure
└── treetracker-admin-client/      # Legacy React admin panel
```

## Treetracker Wallet App (Primary Development Focus)

The main application is a **Yarn 4 monorepo** with web (Next.js), mobile (React Native/Expo), and NestJS backend.

### Quick Start

```bash
# Install dependencies (run from root of wallet-app)
yarn install

# Environment setup (first time only)
cp apps/user/.env.example apps/user/.dev.env
cp apps/web/.env.example apps/web/.env
cp packages/keycloak/.env.example packages/keycloak/.env
cp packages/wallet/.env.example packages/wallet/.env
```

### Development Commands

**Start Applications**:
```bash
yarn web:dev                    # Next.js web app (port 3000)
yarn user:dev                   # NestJS backend (port 3333)
yarn native:start               # React Native Expo app
```

**Testing**:
```bash
# E2E and component tests
yarn cypress-e2e-test           # Run Cypress E2E tests (interactive)
yarn cypress-e2e-headless-test  # Run headless E2E tests (CI)
yarn cypress-component-test     # Run component tests
yarn bdd:e2e                    # Run BDD (Cucumber) tests
yarn bdd:e2e:local              # Run BDD locally
yarn bdd:e2e:login              # Test login flow
yarn bdd:e2e:register           # Test registration flow
yarn bdd:e2e:wallet             # Test wallet functionality

# Backend unit and integration tests
yarn user:test:unit             # Unit tests
yarn user:test:unit:watch       # Unit tests with file watcher
yarn user:test:int              # Integration tests
yarn user:test:e2e              # E2E tests
yarn user:test:cov              # Coverage report
yarn user:test:debug            # Debug test run
```

**Code Quality**:
```bash
yarn lint:check                 # Check for linting issues
yarn lint:fix                   # Fix linting issues
yarn format                     # Format code with Prettier
yarn format:check               # Check formatting
yarn type-check                 # Run TypeScript type checking
```

**Build**:
```bash
yarn web:build                  # Build Next.js web
yarn web:prod                   # Start production web
yarn user:build                 # Build NestJS backend
yarn user:prod                  # Start production backend
```

### Project Structure

```
treetracker-wallet-app/
├── apps/
│   ├── web/                    # Next.js 14 web application
│   │   ├── src/
│   │   │   ├── app/           # Next.js app directory
│   │   │   ├── components/    # React components
│   │   │   └── lib/           # Utilities and helpers
│   │   └── cypress/           # E2E test specifications
│   ├── native/                # React Native Expo mobile app
│   ├── user/                  # NestJS backend API
│   │   └── src/
│   │       ├── auth/          # Keycloak authentication
│   │       ├── user/          # User management
│   │       ├── queue-listener/ # PostgreSQL event listeners
│   │       └── app.module.ts  # Main NestJS module
│   └── bdd/                   # Cucumber BDD tests
│
├── packages/
│   ├── core/                  # Shared business logic and types
│   ├── queue/                 # PostgreSQL LISTEN/NOTIFY utilities
│   ├── keycloak/              # Keycloak client and auth utilities
│   ├── wallet/                # Wallet business logic
│   ├── config/                # Shared configuration (Prettier, etc.)
│   └── common/                # Common utilities
│
├── package.json               # Root workspace configuration
├── tsconfig.json              # TypeScript configuration
├── eslint.config.cjs          # ESLint configuration
├── CONTRIBUTING.md            # Contributing guidelines
└── README.md                  # Project documentation
```

## Core Architecture Patterns

### Authentication (Keycloak OIDC/OAuth2)

The backend uses **Keycloak** for authentication:
- User registration → Creates user in Keycloak via admin API
- User login → Exchanges username/password for JWT access_token
- Frontend → jotai atoms (loginAtom, registerAtom) call POST /login and POST /register
- Service-to-service → Backend uses client_credentials grant for service account tokens

**Key Files**:
- `apps/user/src/auth/` - Keycloak authentication implementation
- `packages/keycloak/src/` - Keycloak client utilities

### Event-Driven Architecture (PostgreSQL LISTEN/NOTIFY)

The system uses **PostgreSQL pub/sub** for async, non-blocking event handling:

**Publishing an event**:
```typescript
// In NestJS service
await this.eventEmitterService.emit('channel.name', { data });
// Inserts event into queue.message table
```

**Listening to events**:
```typescript
// In queue listener
subscribe({
  pgClient,
  channel: 'channel.name',
  clientID: 'listener-id'
})
.on('message', async (payload) => {
  // Handle event
  // Update ack column when processed
});
```

**Common Events**:
- `user.registered` - New user created, triggers welcome email and token transfer
- `token.received` - User received tokens
- `wallet.created` - New wallet created
- `token.sent` - Token sent to another user

**Key Files**:
- `packages/queue/` - PostgreSQL pub/sub client (publish.js, subscribe.js)
- `apps/user/src/events/event-emitter.service.ts` - NestJS event wrapper
- `apps/user/src/queue-listener/` - Event handler implementations

### Testing Strategy

1. **Unit Tests** (`*.spec.ts`):
   - Test individual services and functions
   - Run with `yarn user:test:unit`
   - Fast, isolated, mocked dependencies

2. **Integration Tests** (`*.spec.int.ts`):
   - Test module-level functionality
   - Test database interactions
   - Run with `yarn user:test:int`
   - Slower, use test database

3. **E2E Tests** (Cypress):
   - Test user workflows across web and mobile
   - Component tests: `yarn cypress-component-test`
   - Full stack tests: `yarn cypress-e2e-test`
   - Headless CI: `yarn cypress-e2e-headless-test`

4. **BDD Tests** (Cucumber):
   - Behavior-driven specifications
   - Run with `yarn bdd:e2e`
   - Feature files define test scenarios
   - Better for stakeholder communication

## Development Workflows

### Adding a New API Endpoint

1. Create DTO (Data Transfer Object) for request/response validation
2. Create controller method with proper decorators
3. Implement service method with business logic
4. Emit events if action impacts system state
5. Add unit tests (`.spec.ts`) and integration tests (`.spec.int.ts`)
6. Run `yarn user:test:int` to verify
7. Test via `yarn user:dev` and Cypress tests

### Implementing Transactional Emails

1. Emit event after action: `EventEmitterService.emit('user.registered', {userId, email, ...})`
2. Create listener in `apps/user/src/queue-listener/`
3. Use `EmailService` to send email asynchronously
4. Register handler in `QueueListenerModule.onModuleInit()`
5. Test: Check `queue.message` table for events and verify email sent
6. Monitor via BDD tests: `yarn bdd:e2e`

### Implementing Bulk Email Campaigns

1. Store campaign definition in `campaigns` table
2. Use **BullMQ** + worker for batch processing (1000 emails at a time)
3. Rate limit to respect email provider quotas
4. Track delivery status in `campaign_recipients` table
5. Monitor with observability tools

## Code Quality Standards

### Commit Messages

All repositories use **Conventional Commits** (enforced via commitlint):

```bash
feat: add new feature
fix: resolve bug
docs: update documentation
refactor: restructure code
test: add tests
chore: maintenance tasks
```

Run commitlint hook automatically on `git commit` via Husky.

### Linting and Formatting

- **ESLint**: Static analysis for code quality
  - Config: `eslint.config.cjs` (supports JS and TypeScript)
  - Shared config for all workspace packages
- **Prettier**: Consistent code formatting
  - Config: `packages/config/prettier.config.json`
  - Applied to all files

**Before committing**:
```bash
yarn lint:fix && yarn format
```

Husky pre-commit hooks will enforce these automatically.

### TypeScript

- **Strict mode enabled** for type safety
- `yarn type-check` validates entire monorepo
- All new code must be TypeScript

## Workspace Reference

Each app/package in the monorepo can be worked on independently:

```bash
# Run commands in specific workspace
yarn workspace web run dev          # Run commands in web app
yarn workspace user run test:unit   # Run commands in user backend
yarn workspace native run start     # Run commands in native app

# Or from the workspace directory
cd apps/web && yarn dev
cd apps/user && yarn test:unit
```

## Other Repositories

### treetracker-database

Database migrations and schemas for PostgreSQL:
- Uses **db-migrate** for versioned migrations
- Located in `main/` directory
- SQS integration for queue processing

```bash
# In treetracker-database/
npm install
# Review migrations in main/migrations/
```

### treetracker-admin-client

Legacy React admin panel for managing platform:
- **Technology**: React 18, Create React App, Material-UI v4, Redux, TanStack Query
- **Authentication**: Custom token-based (legacy, being migrated)

```bash
yarn start:dev           # Start dev server (port 3001) with .env.development
yarn test                # Run Jest tests
yarn build               # Production build
```

### treetracker-infrastructure

AWS infrastructure as code using Terraform:
- VPC, EC2, RDS, networking configurations
- Multiple AWS services (Airflow, API Gateway, Keycloak, CKAN)

```bash
# Format check with pre-commit
pre-commit install && pre-commit run --all-files
```

## Common Development Tasks

### Debugging Backend

```bash
yarn user:debug         # Start NestJS with debugger
# Open chrome://inspect in Chrome DevTools
```

### Testing a Single Test File

```bash
cd apps/user
yarn test:unit -- path/to/file.spec.ts
yarn test:int -- path/to/file.spec.int.ts
```

### Checking What Changed

```bash
git diff                 # Unstaged changes
git diff --staged        # Staged changes
git status              # Overview
```

### Updating Dependencies

```bash
yarn upgrade-interactive   # Update individual dependencies
yarn install              # Reinstall after changes
yarn type-check           # Verify types still work
```

### Running SQL Queries on Production Database

The production database is accessed via SSH tunnel. To query it securely, store credentials in `.env` and run queries via SSH.

**Setup (one-time)**:

1. Create `.env` file in the root directory:
```bash
cat > .env << 'EOF'
# Production Database Credentials
DB_USER=readonlyuser
DB_PASSWORD=your_actual_password_here
DB_HOST=treetracker-cluster-read-only-37982-do-user-8540031-0.b.db.ondigitalocean.com
DB_PORT=25060
DB_NAME=treetracker

# SSH Server
SSH_HOST=204.48.16.148
SSH_USER=root
EOF
```

2. **Never commit `.env`** - add to `.gitignore` if not already there:
```bash
echo ".env" >> .gitignore
```

**Run SQL queries**:

```bash
# execute query
ssh ${SSH_USER}@${SSH_HOST} "psql \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require\" -c \"SELECT count(*) FROM planter;\""
```
The db env var is in file:
For development: `.env.database.development`
For production: `.env.database.production`

**Examples**:

```bash
# Get planter count
source .env && ssh ${SSH_USER}@${SSH_HOST} "psql \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require\" -c \"SELECT count(*) FROM planter;\""

# Get recent trees planted
source .env && ssh ${SSH_USER}@${SSH_HOST} "psql \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require\" -c \"SELECT * FROM tree LIMIT 10;\""

# Get wallet statistics
source .env && ssh ${SSH_USER}@${SSH_HOST} "psql \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require\" -c \"SELECT COUNT(*) as wallet_count FROM wallet;\""
```

**Multi-line SQL queries**:

```bash
source .env && ssh ${SSH_USER}@${SSH_HOST} << 'SQL'
psql "postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require" -c "
SELECT
  p.id,
  p.email,
  COUNT(t.id) as tree_count
FROM planter p
LEFT JOIN tree t ON p.id = t.planter_id
GROUP BY p.id, p.email
ORDER BY tree_count DESC
LIMIT 20;
"
SQL
```

**Quick alias** (optional - add to your shell config):

```bash
alias db-query='source .env && ssh ${SSH_USER}@${SSH_HOST} "psql \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require\" -c"'

# Usage:
db-query "SELECT count(*) FROM planter;"
```

# About data pipeline

Tree capture and session upload to s3 and trigger a queue in the AWS and dump the upload info to a table, then run service to handle the uploaded file. 

Here is example of the upload file:

```
data_pipeline=> select * from bulk_tree_upload where created_at > '2026-01-01' limit 1;
created_at            | 2026-01-31 05:17:51.581232
queue_record          | {"s3": {"bucket": {"arn": "arn:aws:s3:::treetracker-production-batch-uploads", "na
me": "treetracker-production-batch-uploads", "ownerIdentity": {"principalId": "A1N1UIC6HWZ5VY"}}, "object"
: {"key": "2026-01-31-08-16-59_31eb5602-dd64-48f3-a684-17d3c17987c9_68dcf5862654c62c3ca22f741078be6d_sessi
ons.json", "eTag": "68dcf5862654c62c3ca22f741078be6d", "size": 224, "sequencer": "00697D907E3A74BC7B"}, "c
onfigurationId": "TreeBundleUploaded", "s3SchemaVersion": "1.0"}, "awsRegion": "eu-central-1", "eventName"
: "ObjectCreated:Put", "eventTime": "2026-01-31T05:17:50.269Z", "eventSource": "aws:s3", "eventVersion": "
2.1", "userIdentity": {"principalId": "AWS:AROAQYWVSSHAJ6KGOGWNR:CognitoIdentityCredentials"}, "responseEl
ements": {"x-amz-id-2": "eL/2aE/1mxrx2XRqn5e+wCgt45c1BmP7DIG7vVtuuqqR21YFlWeZBi0lWEPbptaR1WpOj4FeI5f8bbw+s
0tpzTrfmoyDe499", "x-amz-request-id": "4PYBB59E8FVFACBF"}, "requestParameters": {"sourceIPAddress": "41.21
0.146.79"}}
event_time            | 2026-01-31 05:17:50.269
bucket_arn            | arn:aws:s3:::treetracker-production-batch-uploads
key                   | 2026-01-31-08-16-59_31eb5602-dd64-48f3-a684-17d3c17987c9_68dcf5862654c62c3ca22f741
078be6d_sessions.json
processed             | t
processed_at          | 2026-01-31 05:22:18.032447
deleted_from_queue    | f
deleted_from_queue_at | 
bulk_data             | {"trees": null, "tracks": null, "devices": null, "captures": null, "messages": nul
l, "sessions": [], "device_id": "29fb51ac12ccc9ad", "registrations": null, "pack_format_version": "2", "wa
llet_registrations": null, "device_configurations": null}
```

For every capture upload, it is uploaded to file/key like: `2026-03-09-12-33-43_291f36b6-546e-4aaf-a2c8-73ee09a74935_dae8fcd3835fc3417410a9147591e029_captures.json`, and the content of every upload capture file is an json format like below:

```

{"device_configurations":null,"device_id":"16aae2ad4a3755cc","devices":null,"messages":null,"registrations":null,"sessions":null,"tracks":null,"captures":[{"captured_at":"2026-03-09T08:02:07Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5385000000000001_33.15922833333333_6953a85f-8511-490f-b236-1e02b4d48d76_IMG_20260309_110151_6384571112025666321.jpg","lat":0.5385000000000001,"lon":33.15922833333333,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"027699f3-23c7-41db-b416-1e7d76629d06","abs_step_count":null,"id":"73130d2c-b5c9-4c11-8dd5-6480fd02be80"},{"captured_at":"2026-03-09T08:02:41Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.538501_33.15926266666666_f8db273b-df7e-4704-b947-e5a80ec1b5bc_IMG_20260309_110228_1632213207212354036.jpg","lat":0.538501,"lon":33.15926266666666,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"027699f3-23c7-41db-b416-1e7d76629d06","abs_step_count":null,"id":"0fe38296-ab38-4c59-a880-02c9f3e9dbb4"},{"captured_at":"2026-03-09T08:04:18Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384290000000003_33.15918533333332_a628d84e-63c1-411e-a798-b2ff0d0e60a6_IMG_20260309_110402_2159827751116765401.jpg","lat":0.5384290000000003,"lon":33.15918533333332,"note":" Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"13705d00-a0a6-4935-b3d2-16e0578f8616"},{"captured_at":"2026-03-09T08:04:49Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384350000000004_33.15924499999995_6b2fa7b3-071c-4439-9039-8315fdd1e0ea_IMG_20260309_110440_8765146514080062305.jpg","lat":0.5384350000000004,"lon":33.15924499999995,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"bbb37d76-8f42-46dd-a4ce-6e447732095c"},{"captured_at":"2026-03-09T08:05:27Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384466666666672_33.15926833333326_70b5e652-f37b-4bf8-8a31-913f49177ac3_IMG_20260309_110510_7915150404104846120.jpg","lat":0.5384466666666672,"lon":33.15926833333326,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"8b770b7f-4782-4e95-8299-30c76f9f6155"},{"captured_at":"2026-03-09T08:06:17Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5383976666666669_33.15934133333328_b08284aa-d59c-4b9f-8b23-fdb60fbfa716_IMG_20260309_110603_4719242128092101186.jpg","lat":0.5383976666666669,"lon":33.15934133333328,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"ce648715-3a6d-4edf-8272-e921d550099e"},{"captured_at":"2026-03-09T08:06:50Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5383746666666667_33.159329666666586_ec2c98cd-13c8-496b-b4ed-0414b777b93b_IMG_20260309_110640_3710939403009411537.jpg","lat":0.5383746666666667,"lon":33.159329666666586,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"fcc4de2e-9f7c-4864-86dd-37baaad66093"},{"captured_at":"2026-03-09T08:07:25Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384050000000001_33.159341666666606_37380e1f-67d9-423e-9916-129f4282c6ba_IMG_20260309_110714_4892240232361254582.jpg","lat":0.5384050000000001,"lon":33.159341666666606,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"d0941216-7dc1-4dd7-ab15-c8709777cfe7"},{"captured_at":"2026-03-09T08:07:58Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384166666666669_33.159341666666606_041809be-7570-4e88-9d4f-16a102ad511f_IMG_20260309_110746_8159121400069532020.jpg","lat":0.5384166666666669,"lon":33.159341666666606,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"85282d89-6aa0-4135-a7bc-aaf4e9a99528"},{"captured_at":"2026-03-09T08:08:35Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384516666666666_33.159374999999926_b3664a33-f215-4142-bba6-355b5a673c40_IMG_20260309_110822_7238455638058700154.jpg","lat":0.5384516666666666,"lon":33.159374999999926,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"fd373bc0-420d-4c88-899b-10d74f0338e5"},{"captured_at":"2026-03-09T08:09:26Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384566666666669_33.15933666666658_0769987b-d2fe-4593-86ee-06e26c1a828e_IMG_20260309_110856_333917252600001978.jpg","lat":0.5384566666666669,"lon":33.15933666666658,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"658a6039-5aed-4f9a-9792-c37a321e1383"},{"captured_at":"2026-03-09T08:10:21Z","delta_step_count":null,"extra_attributes":null,"image_url":"https://treetracker-production-images.s3.eu-central-1.amazonaws.com/2026.03.09.12.33.41_0.5384483333333333_33.15938333333328_04158aea-648c-4cf2-bf0b-dc01294696ee_IMG_20260309_111003_2548130708399289959.jpg","lat":0.5384483333333333,"lon":33.15938333333328,"note":"Buwagi primary school papaya ","rotation_matrix":null,"session_id":"6eb7b057-ec2e-449d-8e11-be4a236d2bc2","abs_step_count":null,"id":"9442ee7b-ad77-40d8-804c-c87e742dc5c7"}],"trees":null,"pack_format_version":"2","wallet_registrations":null}

```
To download the file:

```bash
aws s3 cp s3://treetracker-production-batch-uploads/2026-03-09-12-33-43_291f36b6-546e-4aaf-a2c8-73ee09a74935_dae8fcd3835fc3417410a9147591e029_captures.json ~/temp/capture.json
```


## Local Test Environment (`local`) — Android e2e against local k3s

Goal: run the whole backend in **local k3s (k3d)** and pass the relocated Android e2e suite
(`apps/e2e`, moved from `treetracker-android/e2e`) against it. **Keycloak + PostgreSQL are required**
for the backend (no mocks); the Android signup itself is local/offline and is **not** modified.

### AWS `local` environment (real AWS, not LocalStack)

The `local` env uses **real AWS** so the Android app's Cognito-based S3 upload works with full fidelity.
Account `053061259712`, region `eu-central-1`, local AWS CLI profile **`greenstand`** (creds in
`~/.aws`, never committed). Provisioned resources (`treetracker-local-*`):

| Resource | Identifier |
|---|---|
| Batch-uploads bucket | `treetracker-local-batch-uploads` (capture/session JSON) |
| Images bucket | `treetracker-local-images` |
| SQS queue | `treetracker-local-queue` (`arn:aws:sqs:eu-central-1:053061259712:treetracker-local-queue`) |
| S3→SQS notification | `s3:ObjectCreated:*` on the batch-uploads bucket → the queue |
| Cognito identity pool | `treetracker_local` — `eu-central-1:a9ae848f-b57a-411c-97f8-68127119fc2c` (unauth enabled) |
| IAM unauth role | `treetracker-local-cognito-unauth` (inline `s3:PutObject` on both buckets) |

Verified end-to-end: unauthenticated Cognito creds → S3 `PutObject` → SQS `ObjectCreated` fires.

**Android `local` build** (`treetracker-android/app/build.gradle`, new build type) wires:
`OBJECT_STORAGE_BUCKET_BATCH_UPLOADS=treetracker-local-batch-uploads`,
`OBJECT_STORAGE_BUCKET_IMAGES=treetracker-local-images`,
`OBJECT_STORAGE_IDENTITY_POOL_ID=eu-central-1:a9ae848f-b57a-411c-97f8-68127119fc2c`,
region/endpoint `eu-central-1`, `USE_AWS_S3=true`, `API_GATEWAY`→local k3s ingress.

**Building the `local` APK** (toolchain on this machine):
- Android SDK: `/opt/homebrew/share/android-commandlinetools` (Homebrew `android-commandlinetools`). Set `sdk.dir` in `treetracker-android/local.properties` (gitignored) or export `ANDROID_HOME`. An AVD named `greenstand_test` already exists.
- Use **JDK 21** (`/Library/Java/JavaVirtualMachines/temurin-21.jdk`); Gradle 8.13 rejects JDK 26.
- `app/google-services.json` has a `.local` client (cloned from `.dev`) so the Firebase plugin accepts the new package.
- Build: `cd treetracker-android && JAVA_HOME=<jdk21> ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ./gradlew :app:assembleLocal` → `app/build/outputs/apk/local/app-local.apk` (package `org.greenstand.android.TreeTracker.local`). The e2e config (`apps/e2e/.env`, wdio caps) must use this `appPackage` + APK path.

The data pipeline (consumer in `treetracker-data-pipeline`) reads from `treetracker-local-queue` and the
buckets; the bundle is transformed (`bulk-pack-transformer`/`-v2`, by `pack_format_version`) then loaded
by `bulk-pack-processor` into PostgreSQL, surfaced via `treetracker-admin-api` → admin-client `/verify`.

### Capture-pipeline submodules

Added to the monorepo (the real S3-upload→DB handling): `treetracker-data-pipeline`,
`bulk-pack-transformer`, `bulk-pack-transformer-v2`, `bulk-pack-processor`, plus `treetracker-query-api`
(web-map backend). `treetracker-admin-api` is the admin `/verify` backend (Keycloak-protected).

## Important Notes

- **Always run tests before creating a PR** - use `yarn cypress-e2e-headless-test` for quick validation
- **Use the `main` branch for PRs** - the root repository is on `master`, but wallet-app uses `main`
- **PostgreSQL required** - backend development needs a running PostgreSQL instance
- **Docker helpful** - for Keycloak and database setup, consider using Docker Compose
- **BDD tests are valuable** - they document system behavior and catch integration issues
- **Check CONTRIBUTING.md** - in treetracker-wallet-app for additional guidelines on PRs and issues
