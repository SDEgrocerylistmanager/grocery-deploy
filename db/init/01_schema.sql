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
