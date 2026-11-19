-- Grocery List Manager: schema PostgreSQL (>= 13)
-- Accesso: solo il Grocery Backend (nessun altro servizio parla col database).

BEGIN;

-- Utenti: l'id e' il claim "sub" del JWT emesso dal provider SSO.
-- La riga si crea alla prima richiesta autenticata (upsert).
CREATE TABLE users (
    id               text PRIMARY KEY,
    email            text,
    telegram_chat_id text
);

-- Liste: piu' liste per utente, modificabili ed eliminabili.
-- L'id cresce con l'ordine di creazione: serve a trovare la "scorsa lista".
CREATE TABLE lists (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_id       text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name           text NOT NULL CHECK (length(btrim(name)) > 0),
    last_shared_at timestamptz
);
CREATE INDEX lists_owner_idx ON lists (owner_id, id DESC);

-- Elementi: NON persistenti. Si creano all'aggiunta e si cancellano
-- (DELETE vero, niente soft delete) alla rimozione o con la lista.
CREATE TABLE list_items (
    id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    list_id  bigint NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
    name     text NOT NULL CHECK (length(btrim(name)) > 0),
    quantity numeric(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit     text,
    category text NOT NULL DEFAULT 'Other'
             CHECK (category IN ('Dairy', 'Produce', 'Household', 'Bakery', 'Other')),
    checked  boolean NOT NULL DEFAULT false
);
-- deduplicazione: lo stesso prodotto compare una sola volta per lista,
-- senza distinguere maiuscole e spazi (indice su espressione, nessuna colonna extra)
CREATE UNIQUE INDEX list_items_dedup_idx ON list_items (list_id, lower(btrim(name)));

-- Storico / preferiti: PERSISTENTE, indipendente dagli elementi.
-- Una riga per utente e prodotto, aggiornata a ogni aggiunta.
-- Cancellare un elemento o una lista non tocca questa tabella.
CREATE TABLE product_history (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name             text NOT NULL CHECK (length(btrim(name)) > 0),
    category         text NOT NULL DEFAULT 'Other'
                     CHECK (category IN ('Dairy', 'Produce', 'Household', 'Bakery', 'Other')),
    default_quantity numeric(10,2) NOT NULL DEFAULT 1,
    unit             text,
    times_added      integer NOT NULL DEFAULT 1,
    last_added_at    timestamptz NOT NULL DEFAULT now(),
    last_list_id     bigint REFERENCES lists(id) ON DELETE SET NULL,
    is_favorite      boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX product_history_dedup_idx ON product_history (user_id, lower(btrim(name)));
CREATE INDEX product_history_recent_idx ON product_history (user_id, last_added_at DESC);

COMMIT;

-- ---------------------------------------------------------------------------
-- QUERY TIPICHE (parametri: $1 = id lista, $2 = nome, $3 = quantita,
-- $4 = unita, $5 = categoria, $6 = id utente dal JWT)
-- ---------------------------------------------------------------------------

-- 1) Aggiungere un elemento. Un'unica istruzione: controlla che la lista sia
--    dell'utente, inserisce l'elemento (o somma la quantita' se esiste gia')
--    e aggiorna lo storico. Se non restituisce righe, la lista non e' sua.
--
-- WITH new_item AS (
--     INSERT INTO list_items (list_id, name, quantity, unit, category)
--     SELECT l.id, btrim($2), $3, $4, $5 FROM lists l
--      WHERE l.id = $1 AND l.owner_id = $6
--     ON CONFLICT (list_id, lower(btrim(name)))
--       DO UPDATE SET quantity = list_items.quantity + EXCLUDED.quantity
--     RETURNING id, name, quantity, unit, category
-- ), hist AS (
--     INSERT INTO product_history
--            (user_id, name, category, default_quantity, unit, last_list_id)
--     SELECT $6, btrim($2), $5, $3, $4, $1 FROM new_item
--     ON CONFLICT (user_id, lower(btrim(name))) DO UPDATE
--        SET times_added      = product_history.times_added + 1,
--            last_added_at    = now(),
--            name             = EXCLUDED.name,
--            category         = EXCLUDED.category,
--            default_quantity = EXCLUDED.default_quantity,
--            unit             = EXCLUDED.unit,
--            last_list_id     = EXCLUDED.last_list_id
--     RETURNING 1
-- )
-- SELECT * FROM new_item;

-- 2) Modificare / cancellare un elemento (sempre con controllo del proprietario).
--    La cancellazione e' un DELETE vero e lo storico resta.
--
-- UPDATE list_items i SET quantity = $3, unit = $4, checked = $7
--   FROM lists l
--  WHERE i.id = $8 AND i.list_id = l.id AND l.owner_id = $6;
--
-- DELETE FROM list_items i USING lists l
--  WHERE i.id = $8 AND i.list_id = l.id AND l.owner_id = $6;

-- 3) Suggerimenti, versione semplice: gli ultimi prodotti aggiunti dall'utente
--    (preferiti in cima), escludendo quelli gia' nella lista corrente ($1).
--    Con un prefisso digitato ($9) si aggiunge: AND lower(h.name) LIKE lower($9) || '%'
--
-- SELECT h.name, h.category, h.default_quantity, h.unit
--   FROM product_history h
--  WHERE h.user_id = $6
--    AND NOT EXISTS (SELECT 1 FROM list_items i
--                     WHERE i.list_id = $1 AND lower(btrim(i.name)) = lower(h.name))
--  ORDER BY h.is_favorite DESC, h.last_added_at DESC
--  LIMIT 10;

-- 4) Suggerimenti, versione "scorsa lista": i prodotti aggiunti per ultimi
--    nella lista precedente a quella corrente ($1).
--
-- SELECT h.name, h.category, h.default_quantity, h.unit
--   FROM product_history h
--  WHERE h.user_id = $6
--    AND h.last_list_id = (SELECT id FROM lists
--                           WHERE owner_id = $6 AND id < $1
--                           ORDER BY id DESC LIMIT 1)
--  ORDER BY h.last_added_at DESC;

-- 5) Pulizia periodica opzionale: tiene piccolo lo storico.
--
-- DELETE FROM product_history
--  WHERE NOT is_favorite AND last_added_at < now() - interval '180 days';
