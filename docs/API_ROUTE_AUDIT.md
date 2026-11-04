# Auditoria de rotas — 04/11/2026

| Fluxo | Rotas | Uso e limite |
|---|---|---|
| Pobreflix/TopFlix, catálogo | Página inicial e /wp-json/dooplay/search/?keyword=...&nonce=... | Lista, capas e busca; nonce da sessão. Rotas internas sem contrato público |
| DooPlay, reprodução | Página do título e /wp-json/dooplayer/v2/{post}/{type}/{source} | Consultar opções publicadas no título em paralelo. JSON de iframe não é MP4 |
| GD | Embed retornado pela fonte e POST /stream | Escolha publicada no HTML; pode retornar outro iframe |
| Xonados, catálogo | Script WTyNK e POST ZXDSX publicado pelo script | Descobrir IDs existentes. Nomes de seis IDs são mapeados no código; novos IDs exigem identificação |
| Xonados, capítulos | POST /RTRT, página selecionada, script YwZ, frame FzY, capítulo OnW | Nova sessão por reprodução, capítulo localizado por data |
| Xonados, histórico | POST /G_sTw e POST /Y_sTw com cursor de data | Listagem carrega uma página anterior; reprodução procura até três lotes |
| Xonados, mídia | URL declarada no source do capítulo | Range curto para validar formato, player nativo com Referer. Não deduzir URL por ID/data |
| Embedplay/WZ | /embed/{id}, /embed/{id}/{temporada}/{episodio} | Player externo retornado pela fonte; pode exigir anúncios/verificação |
| Embedplay/WZ, metadados | /api/status, /api/all-ids | Documentados, não usados na inicialização. Status/IDs não são URLs de vídeo |
| Ao vivo | https://iptv-org.github.io/api/{channels,streams,logos}.json | Catálogos em paralelo e cache local; não garantem acesso a cada transmissão |
| Backend opcional CINESHOW | /health, /v1/catalog, /v1/search, /v1/details, /v1/events | Catálogo/busca/detalhes usam backend se CINESHOW_API_URL estiver configurada. Código não comprova implantação. Eventos não são usados na interface |

## Ajustes 0.4.1

Removida a suposição de quatro players fixos. O título fornece os identificadores reais, inclusive não consecutivos. Trailers e duplicatas são ignorados; até 12 opções são consultadas em paralelo. Uma falha não elimina as outras opções.

A página do título descobre o domínio atual por redirecionamento HTTP e fornece as opções. Nos episódios isso elimina a consulta adicional à página inicial.

A validação Range acumula no máximo 1024 bytes entre blocos de rede. Antes, MP4 dividido em blocos pequenos podia ser rejeitado porque o primeiro bloco não continha a assinatura inteira. HTML continua rejeitado.

HTTP 301/302/303 deixam de reenviar o corpo do POST. HTTP 307/308 preservam método e corpo.

## Evidência e limites

As respostas reais e a identificação MP4/H.264/AAC anteriores estão registradas em PROVIDER_API_RESEARCH.md. Nesta revisão foram relidas a implementação atual e as documentações públicas de Embedplay e iptv-org. A nova consulta direta aos provedores não pôde ser concluída no ambiente; a ferramenta web também não abriu os JSONs DooPlay. Não foram coletadas novas medidas de latência nem declarada disponibilidade atual de todos os canais, filmes ou capítulos.

Os testes cobrem opções não consecutivas/duplicadas, falha de uma opção, exclusão de trailer, redirecionamento, renovação de sessão e assinatura de vídeo em vários blocos. Validam o protocolo; não substituem reprodução no Android nem garantem ausência de anúncios.

Para reduzir carga, não consultar all-ids a cada abertura nem guardar URLs efêmeras de mídia como catálogo permanente. O app já mostra catálogo salvo antes de atualizar, atrasa a busca por 400 ms e ignora resultados de buscas antigas.

Referências primárias: https://embedplayapi.top/ e https://github.com/iptv-org/api.
