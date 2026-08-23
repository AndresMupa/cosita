-- =====================================================================
-- Arcade de los Dos — esquema de base de datos (PostgreSQL 15+)
-- Objetivo: llevar el juego de localStorage a web en producción (móvil + PC)
-- Principios: multi-dispositivo, privado por defecto, borrable a petición.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "citext";     -- email case-insensitive

-- ---------------------------------------------------------------------
-- 1. IDENTIDAD
-- ---------------------------------------------------------------------

CREATE TABLE app_user (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email           CITEXT UNIQUE,                 -- NULL si entra solo con código de pareja
  password_hash   TEXT,                          -- Argon2id; NULL si usa OAuth/magic link
  display_name    TEXT NOT NULL,
  locale          TEXT NOT NULL DEFAULT 'es',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at    TIMESTAMPTZ,
  -- confirmación de mayoría de edad: el contenido de premios es adulto
  adult_confirmed_at TIMESTAMPTZ,
  deleted_at      TIMESTAMPTZ                    -- borrado lógico -> purga a los 30 días
);
CREATE INDEX idx_user_active ON app_user (id) WHERE deleted_at IS NULL;

-- Sesión / dispositivo. Permite "cerrar sesión en todos los dispositivos".
CREATE TABLE user_session (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  refresh_hash    TEXT NOT NULL,                 -- hash del refresh token, nunca el token
  device_kind     TEXT NOT NULL CHECK (device_kind IN ('mobile','desktop','tablet','other')),
  user_agent      TEXT,
  ip_hash         TEXT,                          -- IP con hash+sal, no en claro
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ NOT NULL,
  revoked_at      TIMESTAMPTZ
);
CREATE INDEX idx_session_user ON user_session (user_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------
-- 2. PAREJA (el espacio privado compartido)
-- ---------------------------------------------------------------------

CREATE TABLE couple (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT,
  invite_code     TEXT UNIQUE,                   -- código corto de un solo uso
  invite_expires  TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);

-- Exactamente 2 miembros; el rol define qué avatar controla.
CREATE TABLE couple_member (
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('her','him')),
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (couple_id, user_id),
  UNIQUE (couple_id, role)
);
CREATE INDEX idx_member_user ON couple_member (user_id);

-- ---------------------------------------------------------------------
-- 3. AVATARES Y SKINS
-- ---------------------------------------------------------------------

-- Los binarios NO van en la base: van a almacenamiento de objetos (S3/R2)
-- y aquí queda la referencia. Evita hinchar la BD y permite CDN.
CREATE TABLE media_asset (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  uploaded_by     UUID REFERENCES app_user(id) ON DELETE SET NULL,
  storage_key     TEXT NOT NULL,                 -- p.ej. couples/<id>/skins/<uuid>.png
  mime_type       TEXT NOT NULL,
  width_px        INT, height_px INT,
  bytes           INT NOT NULL,
  sha256          TEXT NOT NULL,                 -- deduplicación
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (couple_id, sha256)
);
CREATE INDEX idx_asset_couple ON media_asset (couple_id);

CREATE TABLE skin (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('her','him')),
  name            TEXT NOT NULL,
  asset_id        UUID REFERENCES media_asset(id) ON DELETE SET NULL,  -- NULL = sprite base
  hue             INT  NOT NULL DEFAULT 0   CHECK (hue BETWEEN 0 AND 360),
  saturation      INT  NOT NULL DEFAULT 100 CHECK (saturation BETWEEN 0 AND 240),
  brightness      INT  NOT NULL DEFAULT 100 CHECK (brightness BETWEEN 40 AND 180),
  glow_hue        INT           CHECK (glow_hue BETWEEN 0 AND 360),    -- NULL = sin aura
  is_active       BOOLEAN NOT NULL DEFAULT false,
  sort_order      INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Un solo skin activo por rol y pareja
CREATE UNIQUE INDEX uq_skin_active ON skin (couple_id, role) WHERE is_active;
CREATE INDEX idx_skin_couple ON skin (couple_id, role, sort_order);

-- ---------------------------------------------------------------------
-- 4. CATÁLOGO DE JUEGOS (datos de referencia, versionados)
-- ---------------------------------------------------------------------

CREATE TABLE game (
  code            TEXT PRIMARY KEY,              -- climb, inv, maze, cross, brick, pong
  name            TEXT NOT NULL,
  icon            TEXT,
  description     TEXT,
  sort_order      INT NOT NULL,
  unlocks_after   TEXT REFERENCES game(code),    -- cadena de desbloqueo
  is_enabled      BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE difficulty (
  level           SMALLINT PRIMARY KEY CHECK (level BETWEEN 0 AND 2),
  code            TEXT UNIQUE NOT NULL,          -- easy, hard, insane
  name            TEXT NOT NULL                  -- FÁCIL, DIFÍCIL, SUPER DIFÍCIL
);

INSERT INTO difficulty (level, code, name) VALUES
  (0,'easy','FÁCIL'), (1,'hard','DIFÍCIL'), (2,'insane','SUPER DIFÍCIL')
ON CONFLICT DO NOTHING;

-- Parámetros por juego+dificultad: permite balancear sin desplegar código.
CREATE TABLE game_tuning (
  game_code       TEXT NOT NULL REFERENCES game(code) ON DELETE CASCADE,
  level           SMALLINT NOT NULL REFERENCES difficulty(level),
  params          JSONB NOT NULL,                -- {"speed":2.2,"spawnEvery":70,...}
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (game_code, level)
);

-- ---------------------------------------------------------------------
-- 5. PARTIDAS Y PROGRESO
-- ---------------------------------------------------------------------

CREATE TABLE game_run (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  played_by       UUID REFERENCES app_user(id) ON DELETE SET NULL,
  game_code       TEXT NOT NULL REFERENCES game(code),
  level           SMALLINT NOT NULL REFERENCES difficulty(level),
  outcome         TEXT NOT NULL CHECK (outcome IN ('won','lost','abandoned')),
  score           INT NOT NULL DEFAULT 0,
  lives_left      SMALLINT NOT NULL DEFAULT 0,
  duration_ms     INT,
  device_kind     TEXT CHECK (device_kind IN ('mobile','desktop','tablet','other')),
  client_version  TEXT,
  started_at      TIMESTAMPTZ NOT NULL,
  ended_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- idempotencia: el cliente offline reenvía la misma partida sin duplicarla
  client_run_id   TEXT NOT NULL,
  UNIQUE (couple_id, client_run_id)
);
CREATE INDEX idx_run_couple_time ON game_run (couple_id, ended_at DESC);
CREATE INDEX idx_run_game ON game_run (game_code, level, outcome);

-- Progreso consolidado (proyección; se recalcula desde game_run si hiciera falta)
CREATE TABLE progress (
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  game_code       TEXT NOT NULL REFERENCES game(code),
  level           SMALLINT NOT NULL REFERENCES difficulty(level),
  cleared         BOOLEAN NOT NULL DEFAULT false,
  best_score      INT NOT NULL DEFAULT 0,
  attempts        INT NOT NULL DEFAULT 0,
  first_cleared_at TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (couple_id, game_code, level)
);

-- ---------------------------------------------------------------------
-- 6. PREMIOS Y PENITENCIAS
-- ---------------------------------------------------------------------

-- Mazos editables por la pareja. 'kind' distingue premio (ella) de penitencia.
CREATE TABLE reward_deck (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL CHECK (kind IN ('prize','penalty')),
  name            TEXT NOT NULL,
  is_default      BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_deck_default ON reward_deck (couple_id, kind) WHERE is_default;

CREATE TABLE reward_card (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deck_id         UUID NOT NULL REFERENCES reward_deck(id) ON DELETE CASCADE,
  body            TEXT NOT NULL,
  intensity       SMALLINT NOT NULL DEFAULT 1 CHECK (intensity BETWEEN 1 AND 3), -- suave/medio/intenso
  is_enabled      BOOLEAN NOT NULL DEFAULT true,
  sort_order      INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_card_deck ON reward_card (deck_id) WHERE is_enabled;

-- Premio concedido al completar los 3 niveles de un juego.
CREATE TABLE prize_award (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  game_code       TEXT NOT NULL REFERENCES game(code),
  card_id         UUID REFERENCES reward_card(id) ON DELETE SET NULL,
  card_snapshot   TEXT NOT NULL,                 -- texto congelado por si editan la carta
  awarded_to      TEXT NOT NULL CHECK (awarded_to IN ('her','him')),
  awarded_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  redeemed_at     TIMESTAMPTZ,                   -- se marca al cumplirlo
  -- un premio por juego y pareja
  UNIQUE (couple_id, game_code)
);
CREATE INDEX idx_award_couple ON prize_award (couple_id, awarded_at DESC);

-- Penitencia entregada al perder una vida.
CREATE TABLE penalty_award (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  run_id          UUID REFERENCES game_run(id) ON DELETE SET NULL,
  card_id         UUID REFERENCES reward_card(id) ON DELETE SET NULL,
  card_snapshot   TEXT NOT NULL,
  awarded_to      TEXT NOT NULL CHECK (awarded_to IN ('her','him')),
  awarded_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  redeemed_at     TIMESTAMPTZ
);
CREATE INDEX idx_penalty_couple ON penalty_award (couple_id, awarded_at DESC);

-- ---------------------------------------------------------------------
-- 7. AJUSTES Y CONSENTIMIENTO
-- ---------------------------------------------------------------------

CREATE TABLE couple_settings (
  couple_id       UUID PRIMARY KEY REFERENCES couple(id) ON DELETE CASCADE,
  sound_enabled   BOOLEAN NOT NULL DEFAULT true,
  max_intensity   SMALLINT NOT NULL DEFAULT 3 CHECK (max_intensity BETWEEN 1 AND 3),
  safe_word       TEXT,                          -- cifrada en la aplicación
  limits_note     TEXT,                          -- límites acordados, cifrada
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Registro de consentimiento: ambos aceptan las reglas antes de habilitar premios.
CREATE TABLE consent_record (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  version         TEXT NOT NULL,                 -- versión del texto aceptado
  accepted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (couple_id, user_id, version)
);

-- ---------------------------------------------------------------------
-- 8. SINCRONIZACIÓN OFFLINE
-- ---------------------------------------------------------------------

-- Cola de cambios que el cliente envía al reconectar (idempotente por op_id).
CREATE TABLE sync_operation (
  op_id           TEXT PRIMARY KEY,              -- uuid generado en el cliente
  couple_id       UUID NOT NULL REFERENCES couple(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES app_user(id) ON DELETE SET NULL,
  entity          TEXT NOT NULL,                 -- run | progress | skin | card | settings
  payload         JSONB NOT NULL,
  applied_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sync_couple ON sync_operation (couple_id, applied_at DESC);

-- ---------------------------------------------------------------------
-- 9. VISTAS PARA EL INFORME
-- ---------------------------------------------------------------------

-- Resumen por pareja y juego: intentos, victorias, mejor puntaje, si está completo.
CREATE OR REPLACE VIEW v_game_summary AS
SELECT
  p.couple_id,
  p.game_code,
  COUNT(*) FILTER (WHERE p.cleared)                    AS levels_cleared,
  BOOL_AND(p.cleared)                                  AS game_complete,
  MAX(p.best_score)                                    AS best_score,
  SUM(p.attempts)                                      AS attempts,
  MIN(p.first_cleared_at)                              AS first_clear
FROM progress p
GROUP BY p.couple_id, p.game_code;

-- Marcador: premios frente a penitencias.
CREATE OR REPLACE VIEW v_scoreboard AS
SELECT c.id AS couple_id,
  (SELECT COUNT(*) FROM prize_award   a WHERE a.couple_id = c.id) AS prizes,
  (SELECT COUNT(*) FROM penalty_award a WHERE a.couple_id = c.id) AS penalties,
  (SELECT COUNT(*) FROM prize_award   a WHERE a.couple_id = c.id AND a.redeemed_at IS NOT NULL) AS prizes_redeemed
FROM couple c
WHERE c.deleted_at IS NULL;

-- Uso por dispositivo: sirve para decidir dónde invertir en UX (móvil vs PC).
CREATE OR REPLACE VIEW v_device_usage AS
SELECT couple_id, device_kind,
       COUNT(*) AS runs,
       ROUND(AVG(duration_ms)/1000.0, 1) AS avg_seconds,
       ROUND(100.0 * COUNT(*) FILTER (WHERE outcome='won') / NULLIF(COUNT(*),0), 1) AS win_rate_pct
FROM game_run
GROUP BY couple_id, device_kind;

-- Curva de dificultad: si una dificultad tiene win_rate muy bajo, hay que rebalancear.
CREATE OR REPLACE VIEW v_difficulty_balance AS
SELECT g.game_code, g.level, d.name AS level_name,
       COUNT(*) AS attempts,
       ROUND(100.0 * COUNT(*) FILTER (WHERE g.outcome='won') / NULLIF(COUNT(*),0), 1) AS win_rate_pct,
       ROUND(AVG(g.duration_ms)/1000.0, 1) AS avg_seconds
FROM game_run g
JOIN difficulty d ON d.level = g.level
GROUP BY g.game_code, g.level, d.name;

-- ---------------------------------------------------------------------
-- 10. DATOS SEMILLA DEL CATÁLOGO
-- ---------------------------------------------------------------------

INSERT INTO game (code, name, icon, description, sort_order, unlocks_after) VALUES
  ('climb','ESCALADA','🪜','Trepa esquivando sus orbes',            1, NULL),
  ('inv',  'INVASORES','👾','Derriba drones y al jefe',             2, 'climb'),
  ('maze', 'LABERINTO','🌀','Come runas mientras él te caza',        3, 'inv'),
  ('cross','CRUCE','🚦','Cruza los carriles hasta él',              4, 'maze'),
  ('brick','ROMPEMUROS','🧱','Rompe el muro que lo protege',        5, 'cross'),
  ('pong', 'DUELO','🏓','Gánale el duelo 5 a 0',                    6, 'brick')
ON CONFLICT (code) DO NOTHING;
