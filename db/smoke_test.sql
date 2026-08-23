-- Prueba de humo del esquema: crea una pareja, juega, gana premio y consulta informes.
BEGIN;

-- Usuarios y pareja
INSERT INTO app_user (id, display_name, email, adult_confirmed_at) VALUES
  ('11111111-1111-1111-1111-111111111111','Ella','ella@test.local', now()),
  ('22222222-2222-2222-2222-222222222222','El','el@test.local', now());

INSERT INTO couple (id, name, invite_code) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Los Dos','ABC123');

INSERT INTO couple_member (couple_id, user_id, role) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','her'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','him');

-- Skins: solo uno activo por rol
INSERT INTO skin (couple_id, role, name, is_active, hue, glow_hue) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','her','Original', true, 0, NULL),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','her','Dorada',  false, 38, 45),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','him','Sombra',  true, 220, 265);

-- Mazos y cartas
INSERT INTO reward_deck (id, couple_id, kind, name, is_default) VALUES
  ('dddddddd-dddd-dddd-dddd-dddddddddd01','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','prize','Premios de ella', true),
  ('dddddddd-dddd-dddd-dddd-dddddddddd02','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','penalty','Penitencias', true);

INSERT INTO reward_card (id, deck_id, body, intensity) VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccc01','dddddddd-dddd-dddd-dddd-dddddddddd01','Ella elige el plan de la noche',1),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02','dddddddd-dddd-dddd-dddd-dddddddddd02','El elige la peli',1);

-- Partidas: gana los 3 niveles de ESCALADA y pierde una en INVASORES
INSERT INTO game_run (couple_id, played_by, game_code, level, outcome, score, device_kind, started_at, client_run_id) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','climb',0,'won', 120,'mobile', now(),'r1'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','climb',1,'won', 180,'mobile', now(),'r2'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','climb',2,'won', 240,'desktop',now(),'r3'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','inv',  0,'lost', 40,'mobile', now(),'r4');

INSERT INTO progress (couple_id, game_code, level, cleared, best_score, attempts, first_cleared_at) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','climb',0,true,120,1,now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','climb',1,true,180,1,now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','climb',2,true,240,1,now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','inv',  0,false, 40,1,NULL);

-- Premio al completar los 3 niveles; penitencia al perder
INSERT INTO prize_award (couple_id, game_code, card_id, card_snapshot, awarded_to) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','climb','cccccccc-cccc-cccc-cccc-cccccccccc01','Ella elige el plan de la noche','her');

INSERT INTO penalty_award (couple_id, card_id, card_snapshot, awarded_to) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','cccccccc-cccc-cccc-cccc-cccccccccc02','El elige la peli','her');

COMMIT;

\echo '--- INFORME: resumen por juego ---'
SELECT game_code, levels_cleared, game_complete, best_score FROM v_game_summary ORDER BY game_code;

\echo '--- INFORME: marcador ---'
SELECT prizes, penalties, prizes_redeemed FROM v_scoreboard;

\echo '--- INFORME: uso por dispositivo ---'
SELECT device_kind, runs, win_rate_pct FROM v_device_usage ORDER BY device_kind;

\echo '--- INFORME: balance de dificultad ---'
SELECT game_code, level_name, attempts, win_rate_pct FROM v_difficulty_balance ORDER BY game_code, level_name;
