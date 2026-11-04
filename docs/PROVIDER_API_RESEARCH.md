# Investigação de reprodução — 04/11/2026

## Resultado verificável

| Fonte | Rota observada | Resposta confirmada | Limite |
|---|---|---|---|
| Xonados | Seleção POST `/RTRT`, scripts `YwZ`, lista `FzY`, capítulo `OnW` | HTML do capítulo contém `<source>` com mídia HTTPS; pedido Range retornou HTTP 206, video/mp4, assinatura ftyp | Rotas e parâmetros dependem da sessão e podem mudar; não são contrato público documentado |
| Pobreflix | GET `/wp-json/dooplayer/v2/{post}/{tipo}/{fonte}` | JSON com type=iframe e embed_url | O retorno não é um arquivo MP4/HLS |
| TopFlix | Mesma rota DooPlay | JSON com os mesmos quatro provedores no título testado | Mesmo limite; não valida reprodução nem ausência de anúncios |
| GD | GET do embed, escolha idS publicada no HTML, POST `/stream` | JSON com resources.iframe=true e endereço de outro player | A última resposta testada foi HTML, não vídeo direto |
| Embedplay/WZ | `/api/status`, `/api/all-ids`, `/embed/{id}` | Documentação pública e resposta JSON de status testadas | Catálogo/status não são URLs de mídia; a página informa requisito de anúncios/adblock |

## Testes ao vivo executados

- Raízes observadas: `casasdefilmes.com` redirecionou para
  `filmesamadoresgratis.com`; `filmevdeizle.com` para `filmeonlinebistrita.com`.
  O bloqueio estático anterior impedia também a migração legítima do provedor.
- O Fim da Rua: ambos os sites retornaram o post 164875 e os embeds
  `embed.embedplayer.site/tt27165187`, `superflixapi.fun/filme/tt27165187`,
  `embedplayapi.top/embed/tt27165187` e `www.2embed.cc/embed/tt27165187`.
- GD devolveu, por sua seleção normal de servidor, um player em
  `embedplayer2.xyz`. Esse endereço respondeu HTTP 200 text/html. Não foi
  identificado MP4/HLS explícito nessa última página.
- Xonados: uma sessão nova selecionou o ID 2 e localizou o capítulo 20261103.
  O `<source>` foi obtido do HTML, não deduzido por padrão de URL. Uma requisição
  de apenas 8192 bytes retornou HTTP 206, video/mp4 e assinatura MP4 válida.
  FFprobe identificou H.264, AAC, 1280x720 e duração 2853,151927 segundos.
  Não foi baixado o arquivo completo de aproximadamente 920 MB.
- A identificação de codec/transporte não comprova reprodução em um aparelho
  Android específico. A associação do ID 2 ao nome da novela vem do catálogo
  existente; não foi feita identificação visual de cenas ou personagens.

## Implementação 0.4.0

A seleção de reprodução agora consulta as rotas do provedor, em vez de enviar o
usuário à página completa do filme. A descoberta de raiz segue redirecionamentos
HTTP na consulta de metadados, valida a marca/estrutura do catálogo e não executa
JavaScript publicitário. Cookies são limitados ao host que os emitiu.

Para Xonados, cada reprodução renova a seleção/sessão, encontra o mesmo capítulo
por data e valida os primeiros bytes do vídeo antes de abrir o player nativo.
Links antigos `OnW` não são reutilizados como páginas de reprodução em uma
WebView sem a sessão que os gerou. O progresso usa um ID próprio por capítulo.

Para filmes e episódios DooPlay, o app lista os embeds devolvidos pela API. A
seleção GD consulta a rota de servidor exposta pelo próprio player. Uma URL só
é marcada como mídia direta se a resposta de bytes corresponder a vídeo; iframe
continua explicitamente classificado como player externo. Embeds são apresentados
em uma página mínima de iframe, com a origem/referer apropriados, e não por meio
das páginas completas dos agregadores. O player do provedor pode conter anúncios,
exigir verificação ou não responder. Isso não é apresentado como reprodução sem
anúncios garantida. Não há geração de tokens de autorização, solução de CAPTCHA
ou alteração de DRM.

## Referências primárias

- https://www.xonados.com/ e os scripts/requisições publicados pela própria página.
- https://filmesamadoresgratis.com/filme/o-fim-da-rua-0298151544/
- https://filmeonlinebistrita.com/filme/o-fim-da-rua-0298151544/
- https://embed.embedplayer.site/tt27165187 e `/assets/js/GStream.init.js`.
- https://embedplayapi.top/ (documentação do próprio provedor).

Nenhum cookie, nonce efêmero ou chave de player foi persistido neste relatório.
