/*
  Configuração única do Supabase.
  Este arquivo é usado por todas as páginas (portfólio, login e admin).

  Aqui só fica a URL do projeto e a chave PÚBLICA (anon/publishable).
  Essa chave é feita pra ficar exposta no navegador, ela sozinha não
  dá acesso a nada que a trava de segurança (RLS) do banco não libere.

  NUNCA coloque aqui a chave secreta (service_role). Ela nunca deve
  aparecer em nenhum arquivo deste projeto.

  Toda página que usa este arquivo precisa carregar o script do
  Supabase por CDN ANTES dele, assim:

  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <script src="/js/banco.js"></script>
*/
(function () {
  "use strict";

  var URL_PROJETO = "https://uqfesgnxopvcidckjagw.supabase.co";
  var CHAVE_PUBLICA = "sb_publishable_417W1LKuCA_r2uyoHxdAbQ_MDXkHUwG";
  var EMAIL_DONA = "myukaoliveira@gmail.com";

  if (typeof window.supabase === "undefined") {
    console.error(
      "O script do Supabase não foi carregado antes de js/banco.js. " +
      "Confira se a tag <script src=\"https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2\"></script> " +
      "está antes desta."
    );
    return;
  }

  window.banco = window.supabase.createClient(URL_PROJETO, CHAVE_PUBLICA);
  window.BANCO_EMAIL_DONA = EMAIL_DONA;
  window.BANCO_URL_PROJETO = URL_PROJETO;
})();
