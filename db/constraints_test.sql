-- Verifica que las reglas de negocio estén protegidas por la base de datos.
-- Cada bloque DEBE fallar; si alguno pasa, el esquema tiene un hueco.

\set ON_ERROR_STOP off
\echo '1) Dos skins activos para el mismo rol -> debe fallar'
INSERT INTO skin (couple_id, role, name, is_active)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','her','Otra activa', true);

\echo '2) Tercer miembro en la pareja con rol repetido -> debe fallar'
INSERT INTO couple_member (couple_id, user_id, role)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','him');

\echo '3) Dos premios para el mismo juego -> debe fallar'
INSERT INTO prize_award (couple_id, game_code, card_snapshot, awarded_to)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','climb','Duplicado','her');

\echo '4) Partida repetida con el mismo client_run_id -> debe fallar (idempotencia)'
INSERT INTO game_run (couple_id, game_code, level, outcome, started_at, client_run_id)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','climb',0,'won', now(),'r1');

\echo '5) Dificultad fuera de rango -> debe fallar'
INSERT INTO game_run (couple_id, game_code, level, outcome, started_at, client_run_id)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','climb',7,'won', now(),'rX');

\echo '6) Rol inventado -> debe fallar'
INSERT INTO skin (couple_id, role, name) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','otro','X');

\echo '7) Intensidad fuera de rango -> debe fallar'
INSERT INTO reward_card (deck_id, body, intensity)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddd01','Prueba', 9);

\set ON_ERROR_STOP on
\echo '--- Borrado en cascada: al borrar la pareja no debe quedar rastro ---'
DELETE FROM couple WHERE id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT
  (SELECT COUNT(*) FROM skin)          AS skins,
  (SELECT COUNT(*) FROM game_run)      AS runs,
  (SELECT COUNT(*) FROM progress)      AS progreso,
  (SELECT COUNT(*) FROM prize_award)   AS premios,
  (SELECT COUNT(*) FROM penalty_award) AS penitencias,
  (SELECT COUNT(*) FROM reward_card)   AS cartas;
