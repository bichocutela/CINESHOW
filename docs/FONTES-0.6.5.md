# Fontes e recuperação de reprodução — 0.6.5

Base da revisão: 09e685614a206973512aa74b2ba8a3e48a7b06e4. A imagem enviada mostra o player nativo recusando um capítulo do Xonados depois da resolução do endereço.

## Verificações de rede

Foram feitas consultas normais às páginas e rotas públicas já usadas pelos adaptadores. Não foram contornadas verificações de acesso. HTTP 200 na página não comprova a reprodução integral de todos os títulos.

| Fonte | Resultado desta rede | Alcance da verificação |
|---|---|---|
| Xonados | Página, sessão e capítulo de 05/11 responderam | Seleção da novela 5, página do capítulo e HTTP 206 no MP4 publicado. Cabeçalho indica H.264/AAC, 720p e cerca de 54 minutos. Foi lido apenas um trecho de diagnóstico, sem baixar o filme completo |
| Novelasflix | HTTP 200 | Catálogo, ficha com 179 referências a capítulos e capítulo de exemplo que publica iframe em novelascdn.link |
| Amyflix | HTTP 200 | Catálogo, ficha e links de episódios; o adaptador da API AJAX permanece coberto por testes |
| Animes Online | HTTP 200 | Catálogo, ficha e episódio que publica o player do Blogger |
| Mega Filmes | HTTP 200 | Catálogo e ficha que publica /player.php; fluxo do token/player está coberto por regressão |
| TV Aberta Online | HTTP 200 | Página e JSON completo com 125 novelas; resposta de cerca de 2,17 MB |
| Pobreflix | HTTP 403 | A rede de auditoria não conseguiu consultar o servidor |
| TopFlix | HTTP 403 | A rede de auditoria não conseguiu consultar o servidor |
| SuperFlix | HTTP 403 | A rede de auditoria não conseguiu consultar o servidor; preservada a reserva verificada dos diretórios ao vivo |

## Correções no app

- O retry do vídeo nativo renovava apenas o controller, reutilizando o mesmo URL. Agora há uma nova resolução da fonte e sessão por meio da página/identidade do capítulo, sem trocar silenciosamente o servidor ou o idioma escolhido.
- Os cabeçalhos dos arquivos diretos preservam o referer da página que publicou o vídeo. Cookies anônimos de sessão só acompanham requisições ao mesmo host; não são repassados indiscriminadamente a CDNs de terceiros.
- O player alternativo usa o motor já embarcado no app, oferece decodificação por software e compartilha o identificador de progresso. Mantém barra de tempo, tela cheia e avanço de capítulo.
- Falhas de vídeos sob demanda não instruem mais o usuário a procurar uma lista de canais. Há retry com link renovado, opção de player compatível, retorno aos detalhes e informação técnica com endereços/tokens omitidos.
- A página original da fonte pode ser aberta dentro do app. Seus próprios requisitos e verificações continuam dependendo do provedor.
- O timeout de inicialização do player padrão passa a 60 segundos. O MP4 examinado publica aproximadamente 2,46 MB de metadados iniciais; conexões lentas podem demorar antes da primeira imagem. Isso é uma possível contribuição para falhas, não uma comprovação da causa no aparelho do usuário.

## Validação e limites

Regressões verificam renovação de URL e headers, manutenção da identidade, falha sem substituir dados válidos, servidor/idioma escolhido e a ação de retry na interface. Os testes existentes de APIs/iframes, temporadas, cookies, identidade, downloads e reprodução permanecem na validação.

O player nativo depende do hardware, da rede e das bibliotecas do Android. Não houve teste em telefone físico nesta auditoria, nem reprodução integral de cada vídeo ou verificação de cada canal IPTV. Um bloqueio HTTP 403 ou indisponibilidade externa não é anunciado como fonte corrigida.
