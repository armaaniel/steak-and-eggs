# Run Rails and the ingester as separate Fargate services

Status: accepted. Written down 2026-10-31.

## Context

1. **Rails runs 2 copies during every deploy.** ECS starts the new task before stopping the old one, so Rails keeps no state of its own: auth is a JWT, the cache and ActionCable's pub/sub live in Valkey, and nightly jobs run as their own tasks.
2. **The ingester can never run 2 copies.** Polygon allows one WebSocket per API key, so it deploys stop-first and loses 63–80 s of prices each time. It can't share a deploy unit with Rails.
3. **I want the option to run Rails on more than one machine** without a redesign.
4. **I don't want to manage servers:** OS updates, disks, placing containers.
5. **Cost matters.** About $83/month as built.

## Options

| | One Fargate task, 3 containers | One EC2 box (Kamal) | Several EC2 boxes | Separate Fargate services |
|---|---|---|---|---|
| Ingester deploys on its own (2) | ❌ every Rails deploy restarts it, and the overlap opens a second Polygon socket | ✅ | ✅ | ✅ |
| Separate fates | ❌ | ❌ one box, one zone | ✅ | ✅ |
| Rails can scale out (3) | ❌ scaling copies the ingester | ❌ needs Valkey moved out and a load balancer | ✅ | ✅ `desired_count` |
| Server upkeep (4) | none | one box | several | none |
| Cost (5), rough | less than now | ~$40–55/month | in between | ~$83/month |

## Decision

Separate Fargate services: Rails behind the ALB, and the ingester on its own with stop-first deploys. Valkey on ElastiCache, Postgres on RDS. It's the only option that meets 2, 3 and 4 together. It loses on 5.

## Consequences

- About $30–45/month more than one box, and 42 Terraform resources.
- The scale-out option is unused: Rails runs `desired_count = 1`.
- Every deploy pulls the full ~292 MB image, because Fargate keeps no image cache.
- Compute spans two zones, but Postgres (1c) and Valkey (1a) don't, so a zone outage still takes the app down.
- If Rails scales out, the next limit is Postgres connections on a `db.t4g.micro`.

## Revisit when

- Traffic stays at canary levels and cost matters more than running a distributed deploy: move to one EC2 box with Kamal, and measure the difference.
- Real traffic arrives: raise `desired_count`, then add RDS Multi-AZ and a Valkey replica (about $30/month) to survive a zone outage.
