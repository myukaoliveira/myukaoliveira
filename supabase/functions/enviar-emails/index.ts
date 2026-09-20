// =============================================================
// EDGE FUNCTION "enviar-emails"
// =============================================================
// O QUE ISSO FAZ: recebe uma lista de marcas, um assunto e um
// e-mail em HTML, troca {{nome}} e {{marca}} pelo nome de cada
// marca, e manda um por um pelo Resend, esperando 200ms entre
// cada envio. Grava uma linha por destinatário na tabela
// "email_envios", pula quem está na tabela "email_optout", e para
// na hora se a cota diária do Resend acabar.
//
// SEGURANÇA: só aceita chamadas de quem está logado como
// myukaoliveira@gmail.com. Qualquer outra pessoa (ou ninguém
// logado) recebe recusa (401), antes de qualquer envio.
//
// A CHAVE DO RESEND NUNCA FICA NESTE ARQUIVO. Ela é lida de
// Deno.env.get("RESEND_API_KEY"), um segredo guardado no painel
// do Supabase (Edge Functions > enviar-emails > Secrets).
// =============================================================

import { createClient } from "npm:@supabase/supabase-js@2";

// E-mail que recebe as respostas das marcas (reply-to e rodapé de
// descadastro). Isto NÃO é segredo, é só um endereço de contato,
// por isso pode ficar aqui no código. Troque esta linha quando a
// Myuka confirmar o e-mail de contato definitivo.
const EMAIL_CONTATO = "myukaoliveira@gmail.com";

// Remetente usado nos envios. Sem domínio verificado no Resend,
// só é possível usar o domínio de teste deles (@resend.dev), que
// só entrega para o próprio e-mail da conta. Depois que a Myuka
// verificar o domínio dela, troque para algo como
// "Myuka Oliveira <contato@seudominio.com.br>".
const REMETENTE = "Myuka Oliveira <onboarding@resend.dev>";

const EMAIL_DONA = "myukaoliveira@gmail.com";
const MAXIMO_DESTINATARIOS = 250;
const PAUSA_ENTRE_ENVIOS_MS = 200;

const CABECALHOS_CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respostaJson(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CABECALHOS_CORS, "Content-Type": "application/json" },
  });
}

function esperar(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function primeiroNomeDe(nomeCompleto: string) {
  return String(nomeCompleto || "").trim().split(/\s+/)[0] || nomeCompleto || "";
}

function aplicarModelo(html: string, nomeCompleto: string) {
  const primeiroNome = primeiroNomeDe(nomeCompleto);
  return String(html || "")
    .replace(/\{\{nome\}\}/g, primeiroNome)
    .replace(/\{\{marca\}\}/g, nomeCompleto || "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CABECALHOS_CORS });
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

    // ---------- 1. confere quem está chamando ----------
    const cabecalhoAuth = req.headers.get("Authorization") || "";
    const token = cabecalhoAuth.replace(/^Bearer\s+/i, "");
    if (!token) {
      return respostaJson({ erro: "Não autenticado." }, 401);
    }

    const clienteAuth = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const { data: dadosUsuario, error: erroUsuario } = await clienteAuth.auth.getUser(token);
    if (erroUsuario || !dadosUsuario || !dadosUsuario.user || dadosUsuario.user.email !== EMAIL_DONA) {
      return respostaJson({ erro: "Não autorizado." }, 401);
    }

    if (!RESEND_API_KEY) {
      return respostaJson({ erro: "A chave RESEND_API_KEY ainda não foi configurada nos segredos desta função." }, 500);
    }

    // ---------- 2. lê e valida o corpo da chamada ----------
    const corpo = await req.json();
    const assunto = String(corpo.assunto || "").trim();
    const html = String(corpo.html || "");
    const pularQuemJaRecebeu = corpo.pularQuemJaRecebeu !== false;
    let destinatarios = Array.isArray(corpo.destinatarios) ? corpo.destinatarios : [];

    if (!assunto || !html) {
      return respostaJson({ erro: "Faltou assunto ou o texto do e-mail." }, 400);
    }
    if (!destinatarios.length) {
      return respostaJson({ erro: "Nenhum destinatário foi enviado." }, 400);
    }
    if (destinatarios.length > MAXIMO_DESTINATARIOS) {
      return respostaJson({ erro: "No máximo " + MAXIMO_DESTINATARIOS + " destinatários por chamada. Divida em lotes menores." }, 400);
    }

    // remove e-mails repetidos (ex: mesma agência cuidando de duas marcas)
    const emailsVistos = new Set<string>();
    destinatarios = destinatarios.filter((d: any) => {
      const email = String(d.email || "").trim().toLowerCase();
      if (!email || emailsVistos.has(email)) return false;
      emailsVistos.add(email);
      return true;
    });

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ---------- 3. quem está descadastrado ----------
    const { data: linhasOptout } = await supabaseAdmin.from("email_optout").select("email");
    const listaOptout = new Set((linhasOptout || []).map((l: any) => String(l.email).toLowerCase()));

    // ---------- 4. quem já recebeu este mesmo assunto (se marcado) ----------
    let jaRecebeuEsteAssunto = new Set<string>();
    if (pularQuemJaRecebeu) {
      const { data: linhasEnviadas } = await supabaseAdmin
        .from("email_envios")
        .select("email")
        .eq("assunto", assunto)
        .eq("status", "ok");
      jaRecebeuEsteAssunto = new Set((linhasEnviadas || []).map((l: any) => String(l.email).toLowerCase()));
    }

    // ---------- 5. dispara um por um ----------
    let enviados = 0;
    let falhas = 0;
    let pulados = 0;
    let cotaExcedida = false;
    const idsMarcasEnviadasComSucesso: (string | number)[] = [];
    const total = destinatarios.length;
    let indiceProcessado = 0;

    for (indiceProcessado = 0; indiceProcessado < total; indiceProcessado++) {
      const destinatario = destinatarios[indiceProcessado];
      const emailDestino = String(destinatario.email || "").trim().toLowerCase();

      if (listaOptout.has(emailDestino) || jaRecebeuEsteAssunto.has(emailDestino)) {
        pulados++;
        continue;
      }

      const htmlFinal = aplicarModelo(html, destinatario.marca || destinatario.nome || "");

      let respostaResend: Response;
      try {
        respostaResend = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: "Bearer " + RESEND_API_KEY,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: REMETENTE,
            to: [destinatario.email],
            subject: assunto,
            html: htmlFinal,
            reply_to: EMAIL_CONTATO,
            headers: {
              "List-Unsubscribe": "<mailto:" + EMAIL_CONTATO + "?subject=SAIR>",
            },
          }),
        });
      } catch (erroRede) {
        falhas++;
        await supabaseAdmin.from("email_envios").insert({
          email: destinatario.email,
          assunto: assunto,
          status: "erro",
          erro: "Falha de rede ao chamar o Resend: " + String(erroRede),
        });
        await esperar(PAUSA_ENTRE_ENVIOS_MS);
        continue;
      }

      const corpoResposta = await respostaResend.json().catch(() => ({}));

      if (respostaResend.ok) {
        enviados++;
        if (destinatario.id) idsMarcasEnviadasComSucesso.push(destinatario.id);
        await supabaseAdmin.from("email_envios").insert({
          email: destinatario.email,
          assunto: assunto,
          status: "ok",
          resend_id: corpoResposta && corpoResposta.id ? String(corpoResposta.id) : null,
        });
      } else {
        const nomeErro = (corpoResposta && (corpoResposta.name || corpoResposta.error)) || "";
        const mensagemErro = (corpoResposta && corpoResposta.message) || respostaResend.statusText || "erro desconhecido";

        if (String(nomeErro).indexOf("daily_quota_exceeded") !== -1 || String(mensagemErro).indexOf("daily_quota_exceeded") !== -1) {
          cotaExcedida = true;
          break;
        }

        falhas++;
        await supabaseAdmin.from("email_envios").insert({
          email: destinatario.email,
          assunto: assunto,
          status: "erro",
          erro: mensagemErro,
        });
      }

      await esperar(PAUSA_ENTRE_ENVIOS_MS);
    }

    const faltando = cotaExcedida ? total - indiceProcessado : 0;

    // ---------- 6. marca as marcas que receberam com sucesso ----------
    if (idsMarcasEnviadasComSucesso.length) {
      await supabaseAdmin
        .from("marcas")
        .update({ ultimo_email_em: new Date().toISOString() })
        .in("id", idsMarcasEnviadasComSucesso);
    }

    return respostaJson({
      enviados: enviados,
      falhas: falhas,
      pulados: pulados,
      cotaExcedida: cotaExcedida,
      faltando: faltando,
    });
  } catch (erroGeral) {
    return respostaJson({ erro: "Erro inesperado na função: " + String(erroGeral) }, 500);
  }
});
