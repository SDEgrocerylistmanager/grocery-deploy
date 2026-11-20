[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE.md)

# grocery-deploy

| Path | Content |
|---|---|
| `docker-compose.yml` | The services started by `docker compose up` |
| `.env.example` | Template of the configuration (copy it to `.env`) |
| `database/init/01_schema.sql` | PostgreSQL schema, run automatically the first time the database starts |
| `databasequeries_reference.sql` | Reference SQL for the backend developers (not run automatically) |
| `authentik/blueprints/grocery-oidc.yaml` | Authentik blueprint: creates the OIDC provider and application |

## Services started today

| Service | Image | Port | Role |
|---|---|---|---|
| `postgres` | `postgres:16` | 5432 | Database of the application (schema from `database/init/`) |
| `authentik-db` | `postgres:16` | - | Database of Authentik only (not exposed) |
| `authentik-server` | `ghcr.io/goauthentik/server` | 9000, 9443 | SSO provider: login pages and OIDC endpoints |
| `authentik-worker` | `ghcr.io/goauthentik/server` | - | Authentik background tasks, applies the blueprint |

The application services (orchestrator, backend, categorizer, adapters, frontend and
`grocery-sso-service`) are added to the compose file as their images get published on
`ghcr.io/sdegrocerylistmanager/<service>:latest`. Each one has its own repository with its own CI.

## Quick start

Requirements: Docker with Docker Compose.

```
cp .env.example .env        # then edit the values, see below
docker compose up -d
docker compose ps           # wait until the containers are "healthy"
```

### Configuration (`.env`)

| Variable | Meaning |
|---|---|
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Application database |
| `AUTHENTIK_DB`, `AUTHENTIK_DB_USER`, `AUTHENTIK_DB_PASSWORD` | Authentik database |
| `AUTHENTIK_SECRET_KEY` | Secret used by Authentik to sign its own data. Generate it with `openssl rand -base64 60 \| tr -d "\n"` |
| `AUTHENTIK_OIDC_CLIENT_SECRET` | Secret of the OIDC client used by `grocery-sso-service`. Generate it with `openssl rand -hex 32` |
| `AUTHENTIK_TAG` | Authentik version (default `2025.10.0`) |

`.env` is ignored by git: never commit it. Compose refuses to start if a required secret is missing.

## Authentik (SSO)

1. Open <http://localhost:9000/if/flow/initial-setup/> and create the admin user (`akadmin`).
   This is done once per database and is stored only in the local Authentik database.
2. Nothing else to click: at startup Authentik applies the blueprint
   `authentik/blueprints/grocery-oidc.yaml`, which creates:
   - the OAuth2/OIDC provider `grocery-sso-provider` (client id `grocery-sso`, confidential client,
     scopes `openid profile email`, RS256 signatures);
   - the application `Grocery List Manager` (slug `grocery`);
   - the only allowed redirect URI: `http://localhost:8002/auth/callback`.
3. Check that it works: the discovery document must answer.

```
curl http://localhost:9000/application/o/grocery/.well-known/openid-configuration
```

Useful addresses for the services that use it:

| Purpose | URL |
|---|---|
| Issuer (the `iss` claim of the tokens) | `http://localhost:9000/application/o/grocery/` |
| Authorization (opened by the browser) | `http://localhost:9000/application/o/authorize/` |
| Token (called by services) | `http://localhost:9000/application/o/token/` |
| Public keys (JWKS) | `http://localhost:9000/application/o/grocery/jwks/` |

Inside the Compose network services reach Authentik as `http://authentik-server:9000`, while the
browser and the `iss` claim use `localhost:9000`. See the README of `grocery-sso-service` for how
this is handled.

## Common operations

```
docker compose logs -f authentik-server     # follow the logs of one service
docker compose stop                          # stop, keep the data
docker compose down                          # remove containers, keep the data
docker compose down -v                       # remove containers AND all data (databases, admin user)
```

If you change `AUTHENTIK_DB_PASSWORD` after the first start, the existing database keeps the old
password: run `docker compose down -v` to recreate it.

## Notes

- The default passwords in `.env.example` (`change-me`) are only for local development.
  Use real values before any demo on a shared machine.
- Ports 5432, 9000 and 9443 are published on the host for development. Internal services
  (categorizer, adapters) will not be exposed.

## Authors
- Palmieri Filippo @FilizZPalm
- Radice Lorenzo @radix54

## License
Copyright (C) 2026  Palmieri Filippo, Radice Lorenzo

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
