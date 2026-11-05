# Fontes e rotas verificadas — CINESHOW 0.6.0

Verificação: 05/11/2026. Rotas públicas observadas em HTML/documentação do próprio site, sem credenciais, bypass de verificação ou geração de assinatura.

## SuperFlixAPI
Origem: https://superflixapi.fun. Documentação publicada: /doc.
- Catálogo rico: /filmes?page=N, /series?page=N, /animes?page=N, /doramas?page=N. Título, ano, capa e data-embed/data-title em base64 publicados na interface. Decodificar esses campos não fornece MP4.
- Busca: /pesquisar?s=TEXTO&paged=N&type=1 (filme), 2 (série), 3 (anime), 5 (dorama).
- IDs: /lista?category=filme|serie|anime|dorama&type=imdb|tmdb&format=json&limit=N. Listas de IDs não são fichas completas; não associar arrays de IMDb/TMDB por posição.
- Players: /filme/IMDB_OU_TMDB e /serie/TMDB[/TEMPORADA[/EPISODIO]]. O app abre os players publicados, sem prometer vídeo nativo.
- Canais: /lista?category=canais&format=json&limit=N; categorias channel_categories. Cada item oferece embed_url /canal/IDENTIFICADOR.
- Agenda: /lista?category=eventos&format=json&limit=N; categorias event_categories. Documentação também oferece guia e filtros sport/status/genre/q. Horários exibidos como informados pela fonte, sem inventar fuso.
- A busca category=pesquisa agrega canais/eventos; não substitui a busca de filmes.
- Canais/eventos organizados em Ao Vivo, ao lado de IPTV. Animes ficam somente na categoria Anime.
- Campos play_event_direct_url podem apontar para iframe: não são prova de mídia direta. Login/Turnstile não são automatizados.
- O app carrega páginas sob demanda, preserva cache e atualiza ao abrir; não baixa todo o catálogo de uma vez. O limite 500 das listas de canais/eventos é um limite explícito, não promessa de cobertura ilimitada.

## MegaFilmes
Origem https://megafilmeshd1.com.
- /filmes?page=N&sort=recent, /series?page=N&sort=recent, /categoria/SLUG, /search?q=TEXTO.
- /filme/SLUG e /serie/SLUG: descrição, ficha, capas poster-cache.php e episódios publicados em data-src.
- /player.php?type=filme&tmdb=ID ou type=serie&id=ID&season=N&episode=N.
- O próprio player publica generate_token.php com esses parâmetros; resposta JSON ok/url/mode. O app usa a rota declarada, sem criar assinaturas.
- Resultado verificado aponta para player embedyplayer.xyz, não MP4. Download só aparece como executável quando mídia direta for validada.
- Episódios têm identidade por série/temporada/número, não apenas pelo caminho player.php.

## Anime
Origem https://animesonlinecc.to.
- /anime/, /anime/page/N/, /genero/letra-a/ até z, /?s=TEXTO&post_type=tvshows&paged=N.
- /anime/SLUG: metadados de episódios; /episodio/SLUG: iframes publicados Dublado/Legendado.
- Naruto Shippuden retorna cerca de 927 KB de HTML com a lista completa. A análise ocorre fora da interface e somente 100 itens são construídos por bloco. Não existe paginação de rede de 100 episódios confirmada.
- Blogger video.g oferece player externo; URL googlevideo encontrada retornou HTML no teste e não foi considerada MP4.
- Recentes, episódios e novidades ficam dentro de Anime. SuperFlix também é opção de fonte Anime; o próprio player oferece sua seleção de episódios. No SuperFlix o filtro por letra verifica os resultados de busca publicados, com páginas sob demanda.
- Notificações são locais enquanto o app abre/está ativo, não push em segundo plano.

## Informações de títulos
- Sinopse e ficha públicas da fonte têm atribuição. Nota de usuários do site ou TMDb nunca é chamada de IMDb.
- Sugestão pública IMDb por ID confirma identidade/ano e elenco principal; não oferece sinopse nem notas.
- Backend opcional /v1/metadata?imdb_id=tt... usa OMDB_API_KEY somente no servidor. É necessário configurar e hospedar o backend para sinopse/nota OMDb e notas Rotten Tomatoes. Nenhuma chave foi fornecida nesta sessão; notas indisponíveis permanecem assim, sem valores inventados.
- Rotten Tomatoes exige correspondência canônica: Wikidata P345 → P1258, sem adivinhar slug. Marcas exibidas em texto, sem logos copiados.
- Elenco clicável pesquisa apenas títulos cujo elenco já foi confirmado e indexado no aparelho. Não é uma filmografia completa do IMDb.
- “Adicionados recentemente” ordena pela primeira detecção neste aparelho; não representa data de lançamento do filme.
- Controles e listas de capítulos respeitam a área segura do Android; listas de todos os tipos são divididas em blocos de até 100.

### Inventário complementar da documentação SuperFlix
- /lista?category=filme|serie|anime|dorama&type=generos&format=json: gêneros.
- Filtro de catálogo: genero=SLUG, IDs type=imdb|tmdb, ordem order=asc.
- category=animes é alias publicado de anime.
- category=busca é alias publicado de pesquisa para canais/eventos.
- format=json ou html conforme documentação; category=guia exibe a grade.
- Respostas verificadas nesta integração: 327 canais e 74 eventos, ambos HTTP 200; filmes e animes com 40 cards por página. Quantidades variam com a fonte.
