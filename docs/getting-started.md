# Getting Started

The easiest way to run Konversio locally is with Docker Compose, which starts PostgreSQL, Redis, Mailhog, the Rails backend, and the Vite frontend in one shot.

## 1. Copy environment template

```bash
cp .env.example .env
```

## 2. Boot the containers

```bash
docker compose up -d
```

*(Wait for the `postgres` and `redis` healthchecks to pass.)*

## 3. Initialize the database

```bash
docker compose exec rails bundle exec rails db:chatwoot_prepare
```

## 4. Access the app

| Service | URL |
| --- | --- |
| Frontend Dashboard | <http://localhost:3000> |
| Vite Dev Server (HMR) | <http://localhost:3036> |
| Mailhog Web Interface | <http://localhost:8025> |

### Default development credentials

| Field | Value |
| --- | --- |
| Email | `john@acme.inc` |
| Password | `Password1!` |
