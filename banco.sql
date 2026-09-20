-- =============================================================
-- BANCO DE DADOS DO PAINEL DA MYUKA
-- =============================================================
-- O QUE FAZER COM ESTE ARQUIVO:
-- 1. Entre no site do Supabase e abra o seu projeto.
-- 2. No menu da esquerda, clique em "SQL Editor".
-- 3. Clique em "New query".
-- 4. Copie ESTE ARQUIVO INTEIRO e cole na caixa em branco.
-- 5. Clique em "Run" (ou aperte Ctrl+Enter / Cmd+Enter).
-- 6. Deve aparecer "Success" no final. Se aparecer erro, pare e
--    me mostre a mensagem antes de tentar de novo.
--
-- Esse script pode ser rodado mais de uma vez sem problema: ele
-- sempre apaga a trava antiga antes de criar a nova, então rodar
-- de novo só atualiza as regras, não duplica nada (menos as linhas
-- de exemplo, que só são inseridas se a tabela estiver vazia).
-- =============================================================


-- =============================================================
-- BLOCO 0: EXTENSÃO NECESSÁRIA
-- Isso liga um recurso do Postgres que gera um código único (UUID)
-- para cada linha nova, sem eu precisar controlar números.
-- =============================================================
create extension if not exists pgcrypto;


-- =============================================================
-- BLOCO 1: TABELA "videos"
-- Os vídeos que aparecem na seção de destaque e nos nichos do
-- seu portfólio.
-- =============================================================
create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  link text,
  nicho text,
  formato text,
  marca text,
  destaque text,                 -- exemplo: "2,4M views"
  ordem integer not null default 0,
  visivel boolean not null default true,
  criado_em timestamptz not null default now()
);


-- =============================================================
-- BLOCO 2: TABELA "marcas"
-- A sua base de contatos de marcas (funil de vendas: lead até
-- cliente). É preenchida por você no painel e também pelo
-- formulário de contato do seu portfólio (como "lead").
-- =============================================================
create table if not exists public.marcas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  instagram text,
  email text,
  telefone text,
  situacao text not null default 'lead'
    check (situacao in ('lead', 'conversando', 'cliente', 'parada')),
  obs text,
  ultimo_contato date,
  criado_em timestamptz not null default now()
);


-- =============================================================
-- BLOCO 3: TABELA "marcas_trabalhadas"
-- Separada da tabela "marcas": aqui fica só o registro simples
-- de marcas com quem você já trabalhou de fato, com contato e a
-- data do trabalho. Não é o funil de vendas, é o seu histórico.
-- =============================================================
create table if not exists public.marcas_trabalhadas (
  id uuid primary key default gen_random_uuid(),
  marca text not null,
  telefone text,
  email text,
  data date,
  obs text,
  criado_em timestamptz not null default now()
);


-- =============================================================
-- BLOCO 4: TABELA "calendario"
-- As suas tarefas de gravar, editar e postar.
-- =============================================================
create table if not exists public.calendario (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  marca text,
  tipo text not null default 'gravar'
    check (tipo in ('gravar', 'editar', 'postar')),
  data date not null,
  status text not null default 'a_fazer'
    check (status in ('a_fazer', 'feito')),
  criado_em timestamptz not null default now()
);


-- =============================================================
-- BLOCO 5: TABELA "campanhas"
-- As suas campanhas fechadas com marcas, do briefing até a
-- entrega, com valor e pagamento.
-- =============================================================
create table if not exists public.campanhas (
  id uuid primary key default gen_random_uuid(),
  campanha text not null,
  cliente text,
  tipo text not null default 'Conteúdo'
    check (tipo in ('Conteúdo', 'Publicidade')),
  status text not null default 'Briefing'
    check (status in (
      'Briefing', 'Roteiro', 'Aprovação Roteiro', 'Gravação',
      'Edição', 'Aprovado', 'Entregue'
    )),
  qtd integer not null default 1,
  valor numeric(10,2) not null default 0,
  prazo date,
  pagamento text not null default 'pendente'
    check (pagamento in ('pendente', 'pago')),
  ativa boolean not null default true,
  favorita boolean not null default false,
  criado_em timestamptz not null default now()
);


-- =============================================================
-- BLOCO 6: TABELA "roteiros"
-- Seus próprios roteiros de vídeo, escritos e guardados por você
-- na aba Roteiro do painel.
-- =============================================================
create table if not exists public.roteiros (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  nicho text,
  conteudo text,
  status text not null default 'rascunho'
    check (status in ('rascunho', 'pronto')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);


-- =============================================================
-- BLOCO 7: TABELA "marcados"
-- Guarda o que você já marcou como feito no checklist do
-- portfólio (aba Checklist). Cada item do checklist tem uma
-- chave de texto única (por exemplo "sobre-mim-foto-4x5") e essa
-- tabela só guarda se está marcado ou não.
-- =============================================================
create table if not exists public.marcados (
  chave text primary key,
  marcado boolean not null default true,
  atualizado_em timestamptz not null default now()
);


-- =============================================================
-- BLOCO 8: TABELA "visitas"
-- Registro simples de quem visita o seu portfólio, para as
-- métricas da aba Portfólio. Começa vazia, sem dado inventado.
-- =============================================================
create table if not exists public.visitas (
  id uuid primary key default gen_random_uuid(),
  data timestamptz not null default now(),
  pagina text,
  origem text
);


-- =============================================================
-- BLOCO 9: LIGAR A TRAVA DE SEGURANÇA (RLS) EM TODAS AS TABELAS
-- A partir daqui, nenhuma tabela deixa ninguém ler ou escrever
-- nada a não ser que exista uma regra (política) autorizando.
-- =============================================================
alter table public.videos              enable row level security;
alter table public.marcas              enable row level security;
alter table public.marcas_trabalhadas  enable row level security;
alter table public.calendario          enable row level security;
alter table public.campanhas           enable row level security;
alter table public.roteiros            enable row level security;
alter table public.marcados            enable row level security;
alter table public.visitas             enable row level security;


-- =============================================================
-- BLOCO 10: REGRAS (POLÍTICAS) DE CADA TABELA
--
-- Em todas elas, a regra da dona é a mesma: só quem estiver
-- logado com o e-mail myukaoliveira@gmail.com pode ler, criar,
-- editar ou apagar. Ninguém deslogado lê nada, com só duas
-- exceções (marcadas mais abaixo): inserir em "marcas" vindo do
-- formulário do site, e inserir em "visitas".
-- =============================================================

-- ---------- videos ----------
drop policy if exists "dona le videos" on public.videos;
create policy "dona le videos" on public.videos
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere videos" on public.videos;
create policy "dona insere videos" on public.videos
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita videos" on public.videos;
create policy "dona edita videos" on public.videos
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga videos" on public.videos;
create policy "dona apaga videos" on public.videos
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- ---------- marcas ----------
drop policy if exists "dona le marcas" on public.marcas;
create policy "dona le marcas" on public.marcas
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere marcas" on public.marcas;
create policy "dona insere marcas" on public.marcas
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita marcas" on public.marcas;
create policy "dona edita marcas" on public.marcas
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga marcas" on public.marcas;
create policy "dona apaga marcas" on public.marcas
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- EXCEÇÃO 1: o formulário de contato do portfólio, sem ninguém
-- logado, pode inserir uma marca nova, mas só como "lead". Não dá
-- pra inserir já como "cliente" por essa porta, por exemplo.
drop policy if exists "qualquer um envia lead pelo formulario" on public.marcas;
create policy "qualquer um envia lead pelo formulario" on public.marcas
  for insert
  to anon
  with check (situacao = 'lead');

-- ---------- marcas_trabalhadas ----------
drop policy if exists "dona le marcas trabalhadas" on public.marcas_trabalhadas;
create policy "dona le marcas trabalhadas" on public.marcas_trabalhadas
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere marcas trabalhadas" on public.marcas_trabalhadas;
create policy "dona insere marcas trabalhadas" on public.marcas_trabalhadas
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita marcas trabalhadas" on public.marcas_trabalhadas;
create policy "dona edita marcas trabalhadas" on public.marcas_trabalhadas
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga marcas trabalhadas" on public.marcas_trabalhadas;
create policy "dona apaga marcas trabalhadas" on public.marcas_trabalhadas
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- ---------- calendario ----------
drop policy if exists "dona le calendario" on public.calendario;
create policy "dona le calendario" on public.calendario
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere calendario" on public.calendario;
create policy "dona insere calendario" on public.calendario
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita calendario" on public.calendario;
create policy "dona edita calendario" on public.calendario
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga calendario" on public.calendario;
create policy "dona apaga calendario" on public.calendario
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- ---------- campanhas ----------
drop policy if exists "dona le campanhas" on public.campanhas;
create policy "dona le campanhas" on public.campanhas
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere campanhas" on public.campanhas;
create policy "dona insere campanhas" on public.campanhas
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita campanhas" on public.campanhas;
create policy "dona edita campanhas" on public.campanhas
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga campanhas" on public.campanhas;
create policy "dona apaga campanhas" on public.campanhas
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- ---------- roteiros ----------
drop policy if exists "dona le roteiros" on public.roteiros;
create policy "dona le roteiros" on public.roteiros
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere roteiros" on public.roteiros;
create policy "dona insere roteiros" on public.roteiros
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita roteiros" on public.roteiros;
create policy "dona edita roteiros" on public.roteiros
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga roteiros" on public.roteiros;
create policy "dona apaga roteiros" on public.roteiros
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- ---------- marcados ----------
drop policy if exists "dona le marcados" on public.marcados;
create policy "dona le marcados" on public.marcados
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere marcados" on public.marcados;
create policy "dona insere marcados" on public.marcados
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita marcados" on public.marcados;
create policy "dona edita marcados" on public.marcados
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga marcados" on public.marcados;
create policy "dona apaga marcados" on public.marcados
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- ---------- visitas ----------
drop policy if exists "dona le visitas" on public.visitas;
create policy "dona le visitas" on public.visitas
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga visitas" on public.visitas;
create policy "dona apaga visitas" on public.visitas
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

-- EXCEÇÃO 2: qualquer visitante do portfólio, sem estar logado,
-- pode registrar uma visita. Ele nunca consegue LER a tabela,
-- só adicionar uma linha nova.
drop policy if exists "qualquer um registra visita" on public.visitas;
create policy "qualquer um registra visita" on public.visitas
  for insert
  to anon
  with check (true);


-- =============================================================
-- BLOCO 11: A "PORTINHA" PÚBLICA DOS VÍDEOS
--
-- O seu portfólio (que qualquer pessoa acessa, sem login) precisa
-- mostrar os vídeos. Só que a tabela "videos" é privada (só você
-- lê, pelo bloco acima). A solução é esta função: ela entrega
-- somente os vídeos marcados como visíveis, e só os campos que o
-- site precisa mostrar. Ninguém consegue usar essa função pra ler
-- a tabela inteira nem os vídeos escondidos.
-- =============================================================
create or replace function public.videos_publicos()
returns table (
  id uuid,
  titulo text,
  link text,
  nicho text,
  formato text,
  marca text,
  destaque text,
  ordem integer
)
language sql
security definer
set search_path = public
as $$
  select id, titulo, link, nicho, formato, marca, destaque, ordem
  from public.videos
  where visivel = true
  order by ordem asc, criado_em asc;
$$;

grant execute on function public.videos_publicos() to anon, authenticated;


-- =============================================================
-- BLOCO 12: LINHAS DE EXEMPLO
-- Uma linha em cada lista, só pra você ver o formato. Todas têm
-- "(exemplo, apague)" no nome. Só são inseridas se a tabela ainda
-- estiver vazia, então rodar este script de novo não duplica.
-- Vídeos e visitas ficam de fora: vídeo de exemplo apareceria
-- escondido do site, e visitas tem que começar zerada de verdade.
-- =============================================================
insert into public.videos (titulo, link, nicho, formato, marca, destaque, ordem, visivel)
select 'Vídeo de exemplo (apague depois)', 'https://exemplo.com', 'beleza', 'Reels', 'Marca de exemplo', '0 views', 0, false
where not exists (select 1 from public.videos);

insert into public.marcas (nome, instagram, email, telefone, situacao, obs, ultimo_contato)
select 'Marca de exemplo (apague depois)', '@marcadeexemplo', 'contato@exemplo.com', '(00) 00000-0000', 'lead', 'Essa linha é só um exemplo de formato, pode apagar.', current_date
where not exists (select 1 from public.marcas);

insert into public.marcas_trabalhadas (marca, telefone, email, data, obs)
select 'Marca de exemplo (apague depois)', '(00) 00000-0000', 'contato@exemplo.com', current_date, 'Essa linha é só um exemplo de formato, pode apagar.'
where not exists (select 1 from public.marcas_trabalhadas);

insert into public.calendario (titulo, marca, tipo, data, status)
select 'Tarefa de exemplo (apague depois)', 'Marca de exemplo', 'gravar', current_date, 'a_fazer'
where not exists (select 1 from public.calendario);

insert into public.campanhas (campanha, cliente, tipo, status, qtd, valor, prazo, pagamento, ativa, favorita)
select 'Campanha de exemplo (apague depois)', 'Cliente de exemplo', 'Conteúdo', 'Briefing', 1, 0, current_date + 7, 'pendente', true, false
where not exists (select 1 from public.campanhas);

insert into public.roteiros (titulo, nicho, conteudo, status)
select 'Roteiro de exemplo (apague depois)', 'beleza', 'Escreva aqui o texto do seu roteiro. Essa linha é só um exemplo de formato, pode apagar.', 'rascunho'
where not exists (select 1 from public.roteiros);


-- =============================================================
-- BLOCO 13: VÍDEO MAIS ASSISTIDO + TEMPO REAL
-- Adiciona uma coluna em "visitas" pra saber qual vídeo foi
-- assistido em cada clique, e liga a tabela "visitas" no recurso
-- de tempo real do Supabase, pra o painel atualizar sozinho assim
-- que alguém visita o portfólio ou assiste um vídeo, sem precisar
-- dar F5.
-- =============================================================
alter table public.visitas
  add column if not exists video_id uuid references public.videos(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'visitas'
  ) then
    alter publication supabase_realtime add table public.visitas;
  end if;
end $$;


-- =============================================================
-- BLOCO 14: TABELA "prospeccao"
-- Sua base de prospecção: marcas que você ainda vai abordar ou já
-- abordou por conta própria (diferente da tabela "marcas", que é
-- o funil de vendas ligado ao formulário de contato do site). Só
-- você, logada, consegue ler, criar, editar ou apagar aqui, não
-- existe nenhuma exceção pública nessa tabela.
-- =============================================================
create table if not exists public.prospeccao (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  site text,
  instagram text,
  seguidores integer,
  email text,
  whatsapp text,
  pessoa_contato text,
  nicho text,
  origem text,
  status text not null default 'a_enviar'
    check (status in ('a_enviar', 'enviado', 'respondeu', 'proposta', 'fechado', 'sem_interesse')),
  observacao text,
  data date,
  criado_em timestamptz not null default now()
);

alter table public.prospeccao enable row level security;

drop policy if exists "dona le prospeccao" on public.prospeccao;
create policy "dona le prospeccao" on public.prospeccao
  for select
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona insere prospeccao" on public.prospeccao;
create policy "dona insere prospeccao" on public.prospeccao
  for insert
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona edita prospeccao" on public.prospeccao;
create policy "dona edita prospeccao" on public.prospeccao
  for update
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');

drop policy if exists "dona apaga prospeccao" on public.prospeccao;
create policy "dona apaga prospeccao" on public.prospeccao
  for delete
  using ((auth.jwt() ->> 'email') = 'myukaoliveira@gmail.com');


-- =============================================================
-- FIM DO SCRIPT
-- Depois de rodar com sucesso, falta um passo fora daqui: criar
-- o seu usuário de login (Authentication > Users > Add user, no
-- painel do Supabase, com o e-mail myukaoliveira@gmail.com e uma
-- senha sua). Isso está explicado no passo a passo que eu te
-- mandei na conversa.
-- =============================================================
