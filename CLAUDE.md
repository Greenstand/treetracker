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
# Load variables and execute query
source .env && ssh ${SSH_USER}@${SSH_HOST} "psql \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require\" -c \"SELECT count(*) FROM planter;\""
```

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

## Important Notes

- **Always run tests before creating a PR** - use `yarn cypress-e2e-headless-test` for quick validation
- **Use the `main` branch for PRs** - the root repository is on `master`, but wallet-app uses `main`
- **PostgreSQL required** - backend development needs a running PostgreSQL instance
- **Docker helpful** - for Keycloak and database setup, consider using Docker Compose
- **BDD tests are valuable** - they document system behavior and catch integration issues
- **Check CONTRIBUTING.md** - in treetracker-wallet-app for additional guidelines on PRs and issues
