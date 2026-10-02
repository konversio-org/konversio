# Docker Compose deployment files

The root `docker-compose.yaml` is the default local development setup. Alternate modes live under `config/compose/`:

- Production image: `docker compose --project-directory . -f config/compose/production.yaml up -d`
- Build from source in production mode: `docker compose --project-directory . -f config/compose/test.yaml up -d`

Run these from the repository root. `--project-directory .` keeps the `.env`, build context, and Dockerfile paths anchored at the repository root.
