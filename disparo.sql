-- =============================================================
-- DISPARO DE E-MAIL EM MASSA (aba "Prospecção" do painel)
-- =============================================================
-- ONDE COLAR: igual você já fez com o banco.sql. No site do
-- Supabase, abra o seu projeto, clique em "SQL Editor" no menu da
-- esquerda, depois em "New query", cole ESTE ARQUIVO INTEIRO e
-- clique em "Run" (ou Ctrl+Enter / Cmd+Enter).
--
-- Isso NÃO apaga nada que já existe. Ele só acrescenta duas
-- colunas novas na sua tabela "marcas" (com ALTER TABLE, que nunca
-- apaga dado) e cria duas tabelas novas, "email_envios" e
-- "email_optout". Pode rodar mais de uma vez sem duplicar nada.
-- =============================================================


-- =============================================================
-- BLOCO 1: DUAS COLUNAS NOVAS NA TABELA "marcas"
--
-- selecionada: marca se você escolheu essa marca a dedo, na aba
-- Marcas, pra mandar e-mail. Fica salva no banco, então não se
-- perde quando você fecha o painel.
--
-- ultimo_email_em: quando foi a última vez que você mandou um
-- e-mail de prospecção pra essa marca. É diferente do campo
-- "Último contato" que você já usa na aba Marcas (aquele você
-- preenche na mão); este aqui o sistema preenche sozinho, sempre
-- que um e-mail é enviado com sucesso.
-- =============================================================
alter table public.marcas
  add column if not exists selecionada boolean not null default false;

alter table public.marcas
  add column if not exists ultimo_email_em timestamptz;


-- =============================================================
-- BLOCO 2: TABELA "email_envios"
-- Uma linha para CADA e-mail que sai, com o assunto, se deu certo
-- ou não, o erro (quando der errado) e o id que o Resend devolve.
-- Isso é o que permite saber exatamente quem já recebeu e quem
-- ainda falta, mesmo se um disparo parar no meio.
-- =============================================================
create table if not exists public.email_envios (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  assunto text not null,
  status text not null check (status in ('ok', 'erro')),
  erro text,
  resend_id text,
  data timestamptz not null default now()
);

alter table public.email_envios enable row level security;

drop policy if exists "dona le email_envios" on public.email_envios;
create policy "dona le email_envios" on public.email_envios
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere email_envios" on public.email_envios;
create policy "dona insere email_envios" on public.email_envios
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita email_envios" on public.email_envios;
create policy "dona edita email_envios" on public.email_envios
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga email_envios" on public.email_envios;
create policy "dona apaga email_envios" on public.email_envios
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');


-- =============================================================
-- BLOCO 3: TABELA "email_optout"
-- A lista de quem respondeu SAIR e nunca mais pode receber e-mail
-- seu. O e-mail é a própria chave da tabela, então não dá pra
-- cadastrar o mesmo duas vezes.
-- =============================================================
create table if not exists public.email_optout (
  email text primary key,
  data timestamptz not null default now()
);

alter table public.email_optout enable row level security;

drop policy if exists "dona le email_optout" on public.email_optout;
create policy "dona le email_optout" on public.email_optout
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere email_optout" on public.email_optout;
create policy "dona insere email_optout" on public.email_optout
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita email_optout" on public.email_optout;
create policy "dona edita email_optout" on public.email_optout
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga email_optout" on public.email_optout;
create policy "dona apaga email_optout" on public.email_optout
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');


-- =============================================================
-- FIM DO SCRIPT
-- Depois de rodar com sucesso, o próximo passo é criar a Edge
-- Function "enviar-emails" e guardar a chave do Resend como
-- segredo dela. Isso está explicado passo a passo na conversa,
-- fora deste arquivo (a chave NUNCA vai dentro de um arquivo SQL
-- ou de código).
-- =============================================================
